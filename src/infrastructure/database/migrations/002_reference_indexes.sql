CREATE INDEX IF NOT EXISTS idx_exercises_name ON exercises(name);
CREATE INDEX IF NOT EXISTS idx_exercises_primary_muscle ON exercises(primary_muscle_id);
CREATE INDEX IF NOT EXISTS idx_workouts_program_status ON workouts(program_id, status);
CREATE INDEX IF NOT EXISTS idx_lifts_workout_order ON lifts(workout_id, "order");
CREATE INDEX IF NOT EXISTS idx_workout_sets_lift_order ON workout_sets(lift_id, "order");
