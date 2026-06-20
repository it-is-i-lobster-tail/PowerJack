import type { DatabaseClient } from "../DatabaseClient";
import { referenceEquipment, referenceExercises, referenceMuscles } from "./referenceData";

interface NamedIdRow extends Record<string, unknown> {
  id: number;
  name: string;
}

export async function seedReferenceData(db: DatabaseClient): Promise<void> {
  const canonicalMuscleNames = referenceMuscles.map((muscle) => muscle);
  const canonicalEquipmentNames = referenceEquipment.map((equipment) => equipment.name);
  const canonicalExerciseNames = referenceExercises.map((exercise) => exercise.name);

  for (const muscle of referenceMuscles) {
    await db.run("INSERT OR IGNORE INTO muscles (name) VALUES (?)", [muscle]);
  }

  for (const equipment of referenceEquipment) {
    await db.run(
      `
        INSERT OR IGNORE INTO equipment
          (name, weight_overloadable, rep_overloadable, time_overloadable)
        VALUES (?, ?, ?, ?)
      `,
      [
        equipment.name,
        equipment.weightOverloadable ? 1 : 0,
        equipment.repOverloadable ? 1 : 0,
        equipment.timeOverloadable ? 1 : 0,
      ],
    );
    await db.run(
      `
        UPDATE equipment
        SET
          weight_overloadable = ?,
          rep_overloadable = ?,
          time_overloadable = ?
        WHERE name = ?
      `,
      [
        equipment.weightOverloadable ? 1 : 0,
        equipment.repOverloadable ? 1 : 0,
        equipment.timeOverloadable ? 1 : 0,
        equipment.name,
      ],
    );
  }

  const muscles = await db.query<NamedIdRow>("SELECT id, name FROM muscles");
  const equipmentRows = await db.query<NamedIdRow>("SELECT id, name FROM equipment");
  const muscleIds = new Map(muscles.map((row) => [row.name, row.id]));
  const equipmentIds = new Map(equipmentRows.map((row) => [row.name, row.id]));

  for (const exercise of referenceExercises) {
    const primaryMuscleId = muscleIds.get(exercise.primaryMuscle);
    const equipmentId = equipmentIds.get(exercise.equipment);

    if (!primaryMuscleId || !equipmentId) {
      throw new Error(`Missing seed dependency for ${exercise.name}`);
    }

    await db.run(
      `
        INSERT OR IGNORE INTO exercises
          (name, primary_muscle_id, equipment_id, reps_only, min_reps_hypertrophy, max_reps_hypertrophy)
        VALUES (?, ?, ?, ?, ?, ?)
      `,
      [
        exercise.name,
        primaryMuscleId,
        equipmentId,
        exercise.repsOnly ? 1 : 0,
        exercise.minRepsHypertrophy,
        exercise.maxRepsHypertrophy,
      ],
    );
    await db.run(
      `
        UPDATE exercises
        SET
          primary_muscle_id = ?,
          equipment_id = ?,
          reps_only = ?,
          min_reps_hypertrophy = ?,
          max_reps_hypertrophy = ?,
          updated_at = CURRENT_TIMESTAMP
        WHERE name = ?
      `,
      [
        primaryMuscleId,
        equipmentId,
        exercise.repsOnly ? 1 : 0,
        exercise.minRepsHypertrophy,
        exercise.maxRepsHypertrophy,
        exercise.name,
      ],
    );

    const exerciseRows = await db.query<NamedIdRow>("SELECT id, name FROM exercises WHERE name = ?", [
      exercise.name,
    ]);
    const exerciseId = exerciseRows[0]?.id;

    if (!exerciseId) {
      throw new Error(`Failed to load seeded exercise ${exercise.name}`);
    }

    await db.run("DELETE FROM exercise_secondary_muscles WHERE exercise_id = ?", [exerciseId]);

    for (const secondaryMuscle of exercise.secondaryMuscles) {
      const secondaryMuscleId = muscleIds.get(secondaryMuscle);

      if (!secondaryMuscleId) {
        throw new Error(`Missing secondary muscle ${secondaryMuscle}`);
      }

      await db.run(
        "INSERT OR IGNORE INTO exercise_secondary_muscles (exercise_id, muscle_id) VALUES (?, ?)",
        [exerciseId, secondaryMuscleId],
      );
    }
  }

  await removeStaleReferenceData(db, canonicalExerciseNames, canonicalEquipmentNames, canonicalMuscleNames);
  await db.run("INSERT OR IGNORE INTO app_state (id) VALUES (1)");
}

async function removeStaleReferenceData(
  db: DatabaseClient,
  canonicalExerciseNames: readonly string[],
  canonicalEquipmentNames: readonly string[],
  canonicalMuscleNames: readonly string[],
): Promise<void> {
  const exercisePlaceholders = placeholders(canonicalExerciseNames);
  const equipmentPlaceholders = placeholders(canonicalEquipmentNames);
  const musclePlaceholders = placeholders(canonicalMuscleNames);

  await db.run(
    `
      DELETE FROM exercises
      WHERE name NOT IN (${exercisePlaceholders})
        AND id NOT IN (SELECT exercise_id FROM lift_templates)
        AND id NOT IN (SELECT exercise_id FROM lifts)
    `,
    [...canonicalExerciseNames],
  );
  await db.run(
    `
      DELETE FROM equipment
      WHERE name NOT IN (${equipmentPlaceholders})
        AND id NOT IN (SELECT equipment_id FROM exercises)
    `,
    [...canonicalEquipmentNames],
  );
  await db.run(
    `
      DELETE FROM muscles
      WHERE name NOT IN (${musclePlaceholders})
        AND id NOT IN (SELECT primary_muscle_id FROM exercises)
        AND id NOT IN (SELECT muscle_id FROM exercise_secondary_muscles)
        AND id NOT IN (SELECT muscle_id FROM template_focus_muscles)
    `,
    [...canonicalMuscleNames],
  );
}

function placeholders(values: readonly unknown[]): string {
  return values.map(() => "?").join(", ");
}
