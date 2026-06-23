ALTER TABLE app_state
ADD COLUMN rest_timer_state TEXT NOT NULL DEFAULT 'idle' CHECK (rest_timer_state IN ('idle', 'running', 'expired', 'cancelled'));

ALTER TABLE app_state
ADD COLUMN rest_timer_workout_id INTEGER REFERENCES workouts(id) ON DELETE SET NULL;

ALTER TABLE app_state
ADD COLUMN rest_timer_lift_id INTEGER REFERENCES lifts(id) ON DELETE SET NULL;

ALTER TABLE app_state
ADD COLUMN rest_timer_next_set_id INTEGER REFERENCES workout_sets(id) ON DELETE SET NULL;

ALTER TABLE app_state
ADD COLUMN rest_timer_started_at TEXT;

ALTER TABLE app_state
ADD COLUMN rest_timer_duration_seconds INTEGER NOT NULL DEFAULT 120 CHECK (rest_timer_duration_seconds > 0);

ALTER TABLE app_state
ADD COLUMN rest_timer_remaining_seconds INTEGER NOT NULL DEFAULT 0 CHECK (rest_timer_remaining_seconds >= 0);
