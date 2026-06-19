PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS muscles (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS equipment (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  weight_overloadable INTEGER NOT NULL DEFAULT 1,
  rep_overloadable INTEGER NOT NULL DEFAULT 1,
  time_overloadable INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS exercises (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  primary_muscle_id INTEGER NOT NULL REFERENCES muscles(id),
  equipment_id INTEGER NOT NULL REFERENCES equipment(id),
  min_reps_hypertrophy INTEGER NOT NULL,
  max_reps_hypertrophy INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (min_reps_hypertrophy > 0),
  CHECK (max_reps_hypertrophy >= min_reps_hypertrophy)
);

CREATE TABLE IF NOT EXISTS exercise_secondary_muscles (
  exercise_id INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
  muscle_id INTEGER NOT NULL REFERENCES muscles(id) ON DELETE CASCADE,
  PRIMARY KEY (exercise_id, muscle_id)
);

CREATE TABLE IF NOT EXISTS templates (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  workouts_per_week INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (workouts_per_week BETWEEN 1 AND 7)
);

CREATE TABLE IF NOT EXISTS template_focus_muscles (
  template_id INTEGER NOT NULL REFERENCES templates(id) ON DELETE CASCADE,
  muscle_id INTEGER NOT NULL REFERENCES muscles(id),
  PRIMARY KEY (template_id, muscle_id)
);

CREATE TABLE IF NOT EXISTS workout_templates (
  id INTEGER PRIMARY KEY,
  template_id INTEGER NOT NULL REFERENCES templates(id) ON DELETE CASCADE,
  "order" INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (template_id, "order")
);

CREATE TABLE IF NOT EXISTS lift_templates (
  id INTEGER PRIMARY KEY,
  workout_template_id INTEGER NOT NULL REFERENCES workout_templates(id) ON DELETE CASCADE,
  exercise_id INTEGER NOT NULL REFERENCES exercises(id),
  "order" INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (workout_template_id, "order")
);

CREATE TABLE IF NOT EXISTS programs (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  program_length_weeks INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('planned', 'active', 'complete', 'halted', 'skipped')),
  locked INTEGER NOT NULL DEFAULT 0,
  template_id INTEGER NOT NULL REFERENCES templates(id),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS workouts (
  id INTEGER PRIMARY KEY,
  "order" INTEGER NOT NULL,
  workout_day INTEGER NOT NULL,
  program_week INTEGER NOT NULL,
  hidden INTEGER NOT NULL DEFAULT 0,
  locked INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ('planned', 'active', 'complete', 'halted', 'skipped')),
  program_id INTEGER NOT NULL REFERENCES programs(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS lifts (
  id INTEGER PRIMARY KEY,
  exercise_id INTEGER NOT NULL REFERENCES exercises(id),
  workout_id INTEGER NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
  locked INTEGER NOT NULL DEFAULT 1,
  hidden INTEGER NOT NULL DEFAULT 1,
  "order" INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ('planned', 'active', 'complete', 'halted', 'skipped')),
  planned INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS workout_sets (
  id INTEGER PRIMARY KEY,
  planned_reps INTEGER,
  actual_reps INTEGER,
  planned_weight INTEGER,
  actual_weight INTEGER,
  "order" INTEGER NOT NULL,
  lift_id INTEGER NOT NULL REFERENCES lifts(id) ON DELETE CASCADE,
  locked INTEGER NOT NULL DEFAULT 1,
  hidden INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ('planned', 'active', 'complete', 'halted', 'skipped')),
  planned INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (actual_reps IS NULL OR actual_reps > 0),
  CHECK (actual_weight IS NULL OR actual_weight > 0)
);

CREATE TABLE IF NOT EXISTS feedback (
  id INTEGER PRIMARY KEY,
  level_of_pain INTEGER NOT NULL,
  level_of_effort INTEGER NOT NULL,
  lift_id INTEGER NOT NULL REFERENCES lifts(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (level_of_pain BETWEEN 0 AND 10),
  CHECK (level_of_effort BETWEEN 0 AND 10)
);

CREATE TABLE IF NOT EXISTS app_state (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  active_program_id INTEGER REFERENCES programs(id),
  active_workout_id INTEGER REFERENCES workouts(id),
  active_lift_id INTEGER REFERENCES lifts(id),
  user_body_weight_lb INTEGER,
  user_body_weight_updated_last TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
