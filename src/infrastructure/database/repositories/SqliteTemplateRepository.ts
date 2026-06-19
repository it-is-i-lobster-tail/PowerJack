import type {
  CompletedTemplateDraft,
  Template,
  TemplateAggregate,
  TemplateSummary,
} from "../../../domain/templates/Template";
import type { TemplateRepository } from "../../../domain/templates/TemplateRepository";
import type { DatabaseClient } from "../DatabaseClient";
import {
  mapTemplateRow,
  mapTemplateSummaryRow,
  type TemplateRow,
  type TemplateSummaryRow,
} from "../mappers/templateMapper";

interface LastInsertIdRow extends Record<string, unknown> {
  id: number;
}

interface CountRow extends Record<string, unknown> {
  count: number;
}

interface TemplateAggregateDayRow extends Record<string, unknown> {
  id: number;
  order: number;
  exercise_ids: string | null;
}

export class SqliteTemplateRepository implements TemplateRepository {
  constructor(private readonly db: DatabaseClient) {}

  async list(): Promise<TemplateSummary[]> {
    const rows = await this.db.query<TemplateSummaryRow>(
      `
        SELECT
          templates.id,
          templates.name,
          templates.workouts_per_week,
          COUNT(lift_templates.id) AS exercise_count,
          (
            SELECT GROUP_CONCAT(focus_muscles.id || ':' || focus_muscles.name, '|')
            FROM (
              SELECT muscles.id, muscles.name
              FROM template_focus_muscles
              INNER JOIN muscles ON muscles.id = template_focus_muscles.muscle_id
              WHERE template_focus_muscles.template_id = templates.id
              ORDER BY muscles.name ASC
            ) AS focus_muscles
          ) AS focus_muscles,
          templates.created_at,
          templates.updated_at
        FROM templates
        LEFT JOIN workout_templates ON workout_templates.template_id = templates.id
        LEFT JOIN lift_templates ON lift_templates.workout_template_id = workout_templates.id
        WHERE templates.deleted_at IS NULL
        GROUP BY templates.id
        ORDER BY templates.updated_at DESC, templates.id DESC
      `,
    );

    return rows.map(mapTemplateSummaryRow);
  }

  async findById(id: number): Promise<Template | null> {
    const rows = await this.db.query<TemplateRow>(
      `
        SELECT
          templates.id,
          templates.name,
          templates.workouts_per_week,
          GROUP_CONCAT(template_focus_muscles.muscle_id, ',') AS focus_muscle_ids,
          templates.created_at,
          templates.updated_at
        FROM templates
        LEFT JOIN template_focus_muscles ON template_focus_muscles.template_id = templates.id
        WHERE templates.id = ? AND templates.deleted_at IS NULL
        GROUP BY templates.id
      `,
      [id],
    );
    return rows[0] ? mapTemplateRow(rows[0]) : null;
  }

  async loadAggregate(id: number): Promise<TemplateAggregate | null> {
    const template = await this.findById(id);

    if (!template) {
      return null;
    }

    const dayRows = await this.db.query<TemplateAggregateDayRow>(
      `
        SELECT
          workout_templates.id,
          workout_templates."order",
          (
            SELECT GROUP_CONCAT(ordered_lifts.exercise_id, ',')
            FROM (
              SELECT lift_templates.exercise_id
              FROM lift_templates
              WHERE lift_templates.workout_template_id = workout_templates.id
              ORDER BY lift_templates."order" ASC
            ) AS ordered_lifts
          ) AS exercise_ids
        FROM workout_templates
        WHERE workout_templates.template_id = ?
        ORDER BY workout_templates."order" ASC
      `,
      [id],
    );

    return {
      id: template.id,
      name: template.name,
      workoutsPerWeek: template.workoutsPerWeek,
      focusMuscleIds: template.focusMuscleIds,
      days: dayRows.map((row) => ({
        id: row.id,
        order: row.order,
        exerciseIds: row.exercise_ids
          ? row.exercise_ids.split(",").map((value) => Number(value))
          : [],
      })),
    };
  }

  async save(draft: CompletedTemplateDraft): Promise<TemplateSummary> {
    const templateId = await this.db.transaction(async (client) => {
      await client.run(
        `
          INSERT INTO templates (name, workouts_per_week, created_at, updated_at)
          VALUES (?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        `,
        [draft.name, draft.workoutsPerWeek],
      );

      const templateId = await loadLastInsertId(client);

      await writeTemplateAggregate(client, templateId, draft);

      return templateId;
    });

    return this.loadRequiredSummary(templateId);
  }

  async update(id: number, draft: CompletedTemplateDraft): Promise<TemplateSummary> {
    const existing = await this.findById(id);

    if (!existing) {
      throw new Error("Template could not be loaded.");
    }

    await this.db.transaction(async (client) => {
      await client.run(
        `
          UPDATE templates
          SET name = ?, workouts_per_week = ?, updated_at = CURRENT_TIMESTAMP
          WHERE id = ? AND deleted_at IS NULL
        `,
        [draft.name, draft.workoutsPerWeek, id],
      );
      await client.run("DELETE FROM template_focus_muscles WHERE template_id = ?", [id]);
      await client.run("DELETE FROM workout_templates WHERE template_id = ?", [id]);
      await writeTemplateAggregate(client, id, draft);
    });

    return this.loadRequiredSummary(id);
  }

  async softDelete(id: number): Promise<void> {
    await this.db.run(
      `
        UPDATE templates
        SET deleted_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND deleted_at IS NULL
      `,
      [id],
    );
  }

  async isUsedByActiveProgram(id: number): Promise<boolean> {
    const rows = await this.db.query<CountRow>(
      `
        SELECT COUNT(*) AS count
        FROM app_state
        INNER JOIN programs ON programs.id = app_state.active_program_id
        WHERE app_state.id = 1
          AND programs.template_id = ?
          AND programs.status = 'active'
      `,
      [id],
    );

    return (rows[0]?.count ?? 0) > 0;
  }

  async resetForAgent(): Promise<void> {
    await this.db.run("DELETE FROM templates");
  }

  private async loadRequiredSummary(templateId: number): Promise<TemplateSummary> {
    const summaries = await this.db.query<TemplateSummaryRow>(
      `
        SELECT
          templates.id,
          templates.name,
          templates.workouts_per_week,
          COUNT(lift_templates.id) AS exercise_count,
          (
            SELECT GROUP_CONCAT(focus_muscles.id || ':' || focus_muscles.name, '|')
            FROM (
              SELECT muscles.id, muscles.name
              FROM template_focus_muscles
              INNER JOIN muscles ON muscles.id = template_focus_muscles.muscle_id
              WHERE template_focus_muscles.template_id = templates.id
              ORDER BY muscles.name ASC
            ) AS focus_muscles
          ) AS focus_muscles,
          templates.created_at,
          templates.updated_at
        FROM templates
        LEFT JOIN workout_templates ON workout_templates.template_id = templates.id
        LEFT JOIN lift_templates ON lift_templates.workout_template_id = workout_templates.id
        WHERE templates.id = ? AND templates.deleted_at IS NULL
        GROUP BY templates.id
      `,
      [templateId],
    );

    if (!summaries[0]) {
      throw new Error("Saved template could not be loaded.");
    }

    return mapTemplateSummaryRow(summaries[0]);
  }
}

async function writeTemplateAggregate(
  client: DatabaseClient,
  templateId: number,
  draft: CompletedTemplateDraft,
): Promise<void> {
  for (const muscleId of draft.focusMuscleIds) {
    await client.run("INSERT INTO template_focus_muscles (template_id, muscle_id) VALUES (?, ?)", [
      templateId,
      muscleId,
    ]);
  }

  for (const day of draft.days) {
    await client.run(
      `
        INSERT INTO workout_templates (template_id, "order", created_at, updated_at)
        VALUES (?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      `,
      [templateId, day.order],
    );

    const workoutTemplateId = await loadLastInsertId(client);

    for (const [index, exerciseId] of day.exerciseIds.entries()) {
      await client.run(
        `
          INSERT INTO lift_templates
            (workout_template_id, exercise_id, "order", created_at, updated_at)
          VALUES (?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        `,
        [workoutTemplateId, exerciseId, index + 1],
      );
    }
  }
}

async function loadLastInsertId(client: DatabaseClient): Promise<number> {
  const rows = await client.query<LastInsertIdRow>("SELECT last_insert_rowid() AS id");
  const id = rows[0]?.id;

  if (!id) {
    throw new Error("Failed to load inserted row id.");
  }

  return id;
}
