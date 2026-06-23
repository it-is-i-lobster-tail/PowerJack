PRAGMA foreign_keys = OFF;

CREATE TABLE programs_new (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  program_length_weeks INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('planned', 'active', 'completed', 'halted', 'skipped')),
  locked INTEGER NOT NULL DEFAULT 0,
  template_id INTEGER NOT NULL REFERENCES templates(id),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE workouts_new (
  id INTEGER PRIMARY KEY,
  "order" INTEGER NOT NULL,
  workout_day INTEGER NOT NULL,
  program_week INTEGER NOT NULL,
  hidden INTEGER NOT NULL DEFAULT 0,
  locked INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ('planned', 'active', 'completed', 'halted', 'skipped')),
  program_id INTEGER NOT NULL REFERENCES programs_new(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE lifts_new (
  id INTEGER PRIMARY KEY,
  exercise_id INTEGER NOT NULL REFERENCES exercises(id),
  workout_id INTEGER NOT NULL REFERENCES workouts_new(id) ON DELETE CASCADE,
  locked INTEGER NOT NULL DEFAULT 1,
  hidden INTEGER NOT NULL DEFAULT 1,
  "order" INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ('planned', 'active', 'completed', 'halted', 'skipped')),
  planned INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  manual_checkin_status TEXT NOT NULL DEFAULT 'none',
  manual_checkin_source_lift_id INTEGER REFERENCES lifts_new(id)
);

CREATE TABLE workout_sets_new (
  id INTEGER PRIMARY KEY,
  planned_reps INTEGER,
  actual_reps INTEGER,
  planned_weight INTEGER,
  actual_weight INTEGER,
  "order" INTEGER NOT NULL,
  lift_id INTEGER NOT NULL REFERENCES lifts_new(id) ON DELETE CASCADE,
  locked INTEGER NOT NULL DEFAULT 1,
  hidden INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ('planned', 'active', 'completed', 'halted', 'skipped')),
  planned INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (actual_reps IS NULL OR actual_reps > 0),
  CHECK (actual_weight IS NULL OR actual_weight > 0)
);

CREATE TABLE feedback_new (
  id INTEGER PRIMARY KEY,
  level_of_pain INTEGER NOT NULL,
  level_of_effort INTEGER NOT NULL,
  lift_id INTEGER NOT NULL REFERENCES lifts_new(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (level_of_pain BETWEEN 0 AND 10),
  CHECK (level_of_effort BETWEEN 0 AND 10)
);

CREATE TABLE app_state_new (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  active_program_id INTEGER REFERENCES programs_new(id),
  active_workout_id INTEGER REFERENCES workouts_new(id),
  active_lift_id INTEGER REFERENCES lifts_new(id),
  user_body_weight_lb INTEGER,
  user_body_weight_updated_last TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  rest_timer_state TEXT NOT NULL DEFAULT 'idle' CHECK (rest_timer_state IN ('idle', 'running', 'expired', 'cancelled')),
  rest_timer_workout_id INTEGER REFERENCES workouts_new(id) ON DELETE SET NULL,
  rest_timer_lift_id INTEGER REFERENCES lifts_new(id) ON DELETE SET NULL,
  rest_timer_next_set_id INTEGER REFERENCES workout_sets_new(id) ON DELETE SET NULL,
  rest_timer_started_at TEXT,
  rest_timer_duration_seconds INTEGER NOT NULL DEFAULT 120 CHECK (rest_timer_duration_seconds > 0),
  rest_timer_remaining_seconds INTEGER NOT NULL DEFAULT 0 CHECK (rest_timer_remaining_seconds >= 0)
);

INSERT INTO programs_new (
  id,
  name,
  program_length_weeks,
  status,
  locked,
  template_id,
  created_at,
  updated_at
)
SELECT
  id,
  name,
  program_length_weeks,
  CASE status WHEN 'complete' THEN 'completed' ELSE status END,
  locked,
  template_id,
  created_at,
  updated_at
FROM programs;

INSERT INTO workouts_new (
  id,
  "order",
  workout_day,
  program_week,
  hidden,
  locked,
  status,
  program_id,
  created_at,
  updated_at
)
SELECT
  id,
  "order",
  workout_day,
  program_week,
  hidden,
  locked,
  CASE status WHEN 'complete' THEN 'completed' ELSE status END,
  program_id,
  created_at,
  updated_at
FROM workouts;

INSERT INTO lifts_new (
  id,
  exercise_id,
  workout_id,
  locked,
  hidden,
  "order",
  status,
  planned,
  created_at,
  updated_at,
  manual_checkin_status,
  manual_checkin_source_lift_id
)
SELECT
  id,
  exercise_id,
  workout_id,
  locked,
  hidden,
  "order",
  CASE status WHEN 'complete' THEN 'completed' ELSE status END,
  planned,
  created_at,
  updated_at,
  manual_checkin_status,
  manual_checkin_source_lift_id
FROM lifts;

INSERT INTO workout_sets_new (
  id,
  planned_reps,
  actual_reps,
  planned_weight,
  actual_weight,
  "order",
  lift_id,
  locked,
  hidden,
  status,
  planned,
  created_at,
  updated_at
)
SELECT
  id,
  planned_reps,
  actual_reps,
  planned_weight,
  actual_weight,
  "order",
  lift_id,
  locked,
  hidden,
  CASE status WHEN 'complete' THEN 'completed' ELSE status END,
  planned,
  created_at,
  updated_at
FROM workout_sets;

INSERT INTO feedback_new (
  id,
  level_of_pain,
  level_of_effort,
  lift_id,
  created_at,
  updated_at
)
SELECT
  id,
  level_of_pain,
  level_of_effort,
  lift_id,
  created_at,
  updated_at
FROM feedback;

INSERT INTO app_state_new (
  id,
  active_program_id,
  active_workout_id,
  active_lift_id,
  user_body_weight_lb,
  user_body_weight_updated_last,
  created_at,
  updated_at,
  rest_timer_state,
  rest_timer_workout_id,
  rest_timer_lift_id,
  rest_timer_next_set_id,
  rest_timer_started_at,
  rest_timer_duration_seconds,
  rest_timer_remaining_seconds
)
SELECT
  id,
  active_program_id,
  active_workout_id,
  active_lift_id,
  user_body_weight_lb,
  user_body_weight_updated_last,
  created_at,
  updated_at,
  rest_timer_state,
  rest_timer_workout_id,
  rest_timer_lift_id,
  rest_timer_next_set_id,
  rest_timer_started_at,
  rest_timer_duration_seconds,
  rest_timer_remaining_seconds
FROM app_state;

DROP TABLE app_state;
DROP TABLE feedback;
DROP TABLE workout_sets;
DROP TABLE lifts;
DROP TABLE workouts;
DROP TABLE programs;

ALTER TABLE programs_new RENAME TO programs;
ALTER TABLE workouts_new RENAME TO workouts;
ALTER TABLE lifts_new RENAME TO lifts;
ALTER TABLE workout_sets_new RENAME TO workout_sets;
ALTER TABLE feedback_new RENAME TO feedback;
ALTER TABLE app_state_new RENAME TO app_state;

CREATE INDEX IF NOT EXISTS idx_workouts_program_status ON workouts(program_id, status);
CREATE INDEX IF NOT EXISTS idx_lifts_workout_order ON lifts(workout_id, "order");
CREATE INDEX IF NOT EXISTS idx_workout_sets_lift_order ON workout_sets(lift_id, "order");

PRAGMA foreign_keys = ON;
