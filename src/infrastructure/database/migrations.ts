import initialSchema from "./migrations/001_initial_schema.sql?raw";
import referenceIndexes from "./migrations/002_reference_indexes.sql?raw";
import templateSoftDelete from "./migrations/003_template_soft_delete.sql?raw";
import uniqueFeedbackLift from "./migrations/004_unique_feedback_lift.sql?raw";
import liftManualCheckin from "./migrations/005_lift_manual_checkin.sql?raw";
import exerciseRepsOnly from "./migrations/006_exercise_reps_only.sql?raw";

export interface DatabaseMigration {
  id: number;
  name: string;
  sql: string;
}

export const databaseMigrations: DatabaseMigration[] = [
  { id: 1, name: "initial_schema", sql: initialSchema },
  { id: 2, name: "reference_indexes", sql: referenceIndexes },
  { id: 3, name: "template_soft_delete", sql: templateSoftDelete },
  { id: 4, name: "unique_feedback_lift", sql: uniqueFeedbackLift },
  { id: 5, name: "lift_manual_checkin", sql: liftManualCheckin },
  { id: 6, name: "exercise_reps_only", sql: exerciseRepsOnly },
];
