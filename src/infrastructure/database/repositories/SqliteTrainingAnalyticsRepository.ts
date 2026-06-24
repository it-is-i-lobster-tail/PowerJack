import type { CompletedSetEvent } from "../../../domain/analytics/TrainingAnalytics";
import type { TrainingAnalyticsRepository } from "../../../domain/analytics/TrainingAnalyticsRepository";
import type { EntityId } from "../../../domain/ids";
import {
  completedSetStatsColumns,
  completedSetStatsMuscles,
  type CompletedSetStatsValues,
} from "../completedSetStats";
import type { DatabaseClient } from "../DatabaseClient";

type CompletedSetStatsRow = CompletedSetStatsValues & Record<string, unknown> & {
  set_id: number;
  completed_at: string;
};

interface MuscleLookupRow extends Record<string, unknown> {
  id: number;
  name: string;
}

const completedSetStatsSelectColumns = completedSetStatsColumns.join(", ");
const completedSetStatsMuscleNamePlaceholders = completedSetStatsMuscles.map(() => "?").join(", ");
const completedSetStatsMuscleNames = completedSetStatsMuscles.map(([muscleName]) => muscleName);

export class SqliteTrainingAnalyticsRepository implements TrainingAnalyticsRepository {
  constructor(private readonly db: DatabaseClient) {}

  async loadCompletedSetEvents(input: {
    fromInclusive: string;
    toExclusive: string;
  }): Promise<CompletedSetEvent[]> {
    const rows = await this.db.query<CompletedSetStatsRow>(
      `
        SELECT
          set_id,
          created_at AS completed_at,
          ${completedSetStatsSelectColumns}
        FROM completed_sets_stats
        WHERE
          datetime(created_at) >= datetime(?)
          AND datetime(created_at) < datetime(?)
        ORDER BY created_at ASC, set_id ASC
      `,
      [input.fromInclusive, input.toExclusive],
    );

    return expandCompletedSetStatsRows(rows, await loadCompletedSetStatsMuscleLookup(this.db));
  }

  async loadCompletedSetEventsForProgram(programId: EntityId): Promise<CompletedSetEvent[]> {
    const rows = await this.db.query<CompletedSetStatsRow>(
      `
        SELECT
          set_id,
          created_at AS completed_at,
          ${completedSetStatsSelectColumns}
        FROM completed_sets_stats
        WHERE program_id = ?
        ORDER BY created_at ASC, set_id ASC
      `,
      [programId],
    );

    return expandCompletedSetStatsRows(rows, await loadCompletedSetStatsMuscleLookup(this.db));
  }
}

async function loadCompletedSetStatsMuscleLookup(
  db: DatabaseClient,
): Promise<Map<string, MuscleLookupRow>> {
  const rows = await db.query<MuscleLookupRow>(
    `
      SELECT id, name
      FROM muscles
      WHERE name IN (${completedSetStatsMuscleNamePlaceholders})
    `,
    completedSetStatsMuscleNames,
  );

  return new Map(rows.map((row) => [row.name, row]));
}

function expandCompletedSetStatsRows(
  rows: CompletedSetStatsRow[],
  musclesByName: ReadonlyMap<string, MuscleLookupRow>,
): CompletedSetEvent[] {
  const events = rows.flatMap((row) =>
    completedSetStatsMuscles.flatMap(([muscleName, column]) => {
      const setCredit = row[column];

      if (setCredit <= 0) {
        return [];
      }

      const muscle = musclesByName.get(muscleName);

      if (!muscle) {
        throw new Error(`Cannot load completed set stats for muscle ${muscleName}.`);
      }

      return [
        {
          completedAt: row.completed_at,
          muscleId: muscle.id,
          muscleName: muscle.name,
          setCredit,
          setId: row.set_id,
        },
      ];
    }),
  );

  return events.sort((left, right) => {
    const completedAtComparison = left.completedAt.localeCompare(right.completedAt);

    if (completedAtComparison !== 0) {
      return completedAtComparison;
    }

    const muscleComparison = left.muscleName.localeCompare(right.muscleName);

    if (muscleComparison !== 0) {
      return muscleComparison;
    }

    return left.setId - right.setId;
  });
}
