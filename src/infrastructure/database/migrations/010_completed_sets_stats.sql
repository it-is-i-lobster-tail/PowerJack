CREATE TABLE IF NOT EXISTS completed_sets_stats (
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  program_id INTEGER NOT NULL REFERENCES programs(id) ON DELETE CASCADE,
  set_id INTEGER PRIMARY KEY REFERENCES workout_sets(id) ON DELETE CASCADE,
  chest REAL NOT NULL DEFAULT 0 CHECK (chest IN (0, 0.5, 1)),
  back REAL NOT NULL DEFAULT 0 CHECK (back IN (0, 0.5, 1)),
  biceps REAL NOT NULL DEFAULT 0 CHECK (biceps IN (0, 0.5, 1)),
  triceps REAL NOT NULL DEFAULT 0 CHECK (triceps IN (0, 0.5, 1)),
  shoulders REAL NOT NULL DEFAULT 0 CHECK (shoulders IN (0, 0.5, 1)),
  core REAL NOT NULL DEFAULT 0 CHECK (core IN (0, 0.5, 1)),
  quads REAL NOT NULL DEFAULT 0 CHECK (quads IN (0, 0.5, 1)),
  hamstrings REAL NOT NULL DEFAULT 0 CHECK (hamstrings IN (0, 0.5, 1)),
  glutes REAL NOT NULL DEFAULT 0 CHECK (glutes IN (0, 0.5, 1)),
  calves REAL NOT NULL DEFAULT 0 CHECK (calves IN (0, 0.5, 1)),
  forearms REAL NOT NULL DEFAULT 0 CHECK (forearms IN (0, 0.5, 1)),
  CHECK (
    chest + back + biceps + triceps + shoulders + core + quads + hamstrings + glutes + calves + forearms > 0
  )
);

CREATE INDEX IF NOT EXISTS idx_completed_sets_stats_created_at
ON completed_sets_stats(created_at);

CREATE INDEX IF NOT EXISTS idx_completed_sets_stats_program_created_at
ON completed_sets_stats(program_id, created_at);
