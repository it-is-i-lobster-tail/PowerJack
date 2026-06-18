use crate::db::models::*;
use crate::{
    domain::*,
    repository::{RepositoryError, RepositoryResult},
};
use chrono::Utc;
use rusqlite::{params, Connection};
use serde::Deserialize;
use std::collections::{HashMap, HashSet};

pub struct Repository {
    conn: Connection,
}
impl Repository {
    pub fn new(conn: Connection) -> RepositoryResult<Self> {
        conn.execute_batch(SCHEMA)?;
        Self::ensure_seed_support_columns(&conn)?;
        Self::seed_default_muscles(&conn)?;
        Self::seed_default_exercises_on_conn(&conn)?;
        Ok(Self { conn })
    }
    pub fn connection(&self) -> &Connection {
        &self.conn
    }
    fn now() -> String {
        Utc::now().to_rfc3339()
    }

    fn ensure_seed_support_columns(conn: &Connection) -> RepositoryResult<()> {
        for table in [
            "muscle",
            "template",
            "workout_template",
            "exercise",
            "lift_template",
        ] {
            Self::add_column_if_missing(conn, table, "body_weight", "INTEGER")?;
            Self::add_column_if_missing(conn, table, "min_reps_hypertrophy", "INTEGER")?;
            Self::add_column_if_missing(conn, table, "max_reps_hypertrophy", "INTEGER")?;
        }
        conn.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_exercise_name_unique ON exercise(name)",
            [],
        )?;
        Ok(())
    }

    fn add_column_if_missing(
        conn: &Connection,
        table: &str,
        column: &str,
        definition: &str,
    ) -> RepositoryResult<()> {
        let mut stmt = conn.prepare(&format!("PRAGMA table_info({table})"))?;
        let columns = stmt.query_map([], |r| r.get::<_, String>(1))?;
        for existing in columns {
            if existing? == column {
                return Ok(());
            }
        }
        conn.execute(
            &format!("ALTER TABLE {table} ADD COLUMN {column} {definition}"),
            [],
        )?;
        Ok(())
    }

    fn seed_default_muscles(conn: &Connection) -> RepositoryResult<()> {
        let n = Self::now();
        for name in DEFAULT_MUSCLE_NAMES {
            conn.execute(
                "INSERT OR IGNORE INTO muscle(name,created_at,updated_at) VALUES(?,?,?)",
                params![name, n, n],
            )?;
        }
        Ok(())
    }

    pub fn seed_default_exercises(&self) -> RepositoryResult<()> {
        Self::seed_default_exercises_on_conn(&self.conn)
    }

    fn seed_default_exercises_on_conn(conn: &Connection) -> RepositoryResult<()> {
        let seeds: Vec<DefaultExerciseSeed> = serde_json::from_str(DEFAULT_EXERCISES_JSON)
            .map_err(|e| RepositoryError::MappingError(e.to_string()))?;
        let mut muscles = HashMap::new();
        {
            let mut stmt = conn.prepare("SELECT id,name FROM muscle")?;
            let rows = stmt.query_map([], |r| Ok((r.get::<_, String>(1)?, r.get::<_, i64>(0)?)))?;
            for row in rows {
                let (name, id) = row?;
                muscles.insert(name, id);
            }
        }
        let mut seen: HashSet<String> = HashSet::new();
        for seed in seeds {
            if !seen.insert(seed.name.clone()) {
                return Err(RepositoryError::ValidationError(format!(
                    "duplicate seeded exercise '{}'",
                    seed.name
                )));
            }
            if seed.min_reps_hypertrophy <= 0
                || seed.max_reps_hypertrophy < seed.min_reps_hypertrophy
            {
                return Err(RepositoryError::ValidationError(format!(
                    "invalid rep range for '{}'",
                    seed.name
                )));
            }
            let primary_id = *muscles.get(seed.primary_muscle.as_str()).ok_or_else(|| {
                RepositoryError::ValidationError(format!(
                    "unknown primary muscle '{}' for '{}'",
                    seed.primary_muscle, seed.name
                ))
            })?;
            let mut secondary_ids = Vec::new();
            let mut secondary_seen = HashSet::new();
            for secondary in &seed.secondary_muscles {
                if secondary == &seed.primary_muscle {
                    return Err(RepositoryError::ValidationError(format!(
                        "secondary muscle matches primary for '{}'",
                        seed.name
                    )));
                }
                if !secondary_seen.insert(secondary.as_str()) {
                    return Err(RepositoryError::ValidationError(format!(
                        "duplicate secondary muscle for '{}'",
                        seed.name
                    )));
                }
                secondary_ids.push(*muscles.get(secondary.as_str()).ok_or_else(|| {
                    RepositoryError::ValidationError(format!(
                        "unknown secondary muscle '{}' for '{}'",
                        secondary, seed.name
                    ))
                })?);
            }
            let n = Self::now();
            conn.execute(
                "INSERT INTO exercise(name,parent_id,body_weight,min_reps_hypertrophy,max_reps_hypertrophy,created_at,updated_at) VALUES(?,?,?,?,?,?,?)
                 ON CONFLICT(name) DO UPDATE SET parent_id=excluded.parent_id,body_weight=excluded.body_weight,min_reps_hypertrophy=excluded.min_reps_hypertrophy,max_reps_hypertrophy=excluded.max_reps_hypertrophy,updated_at=excluded.updated_at",
                params![seed.name, primary_id, seed.body_weight as i64, seed.min_reps_hypertrophy, seed.max_reps_hypertrophy, n, n],
            )?;
            let exercise_id: i64 = conn.query_row(
                "SELECT id FROM exercise WHERE name=?",
                [seed.name.as_str()],
                |r| r.get(0),
            )?;
            conn.execute(
                "DELETE FROM exercise_secondary_muscle WHERE exercise_id=?",
                [exercise_id],
            )?;
            for secondary_id in secondary_ids {
                conn.execute(
                    "INSERT INTO exercise_secondary_muscle(exercise_id,muscle_id) VALUES(?,?)",
                    params![exercise_id, secondary_id],
                )?;
            }
        }
        Ok(())
    }

    pub fn create_muscle(&self, name: &str) -> RepositoryResult<Muscle> {
        self.create_named("muscle", name, None, None, None, None)?
            .try_into()
    }
    pub fn get_muscle_by_id(&self, id: MuscleId) -> RepositoryResult<Muscle> {
        self.get_timed("muscle", id.0)?.try_into()
    }
    pub fn list_muscles(&self) -> RepositoryResult<Vec<Muscle>> {
        self.list_timed("muscle", None)?
            .into_iter()
            .map(TryInto::try_into)
            .collect()
    }
    pub fn update_muscle(&self, m: &Muscle) -> RepositoryResult<Muscle> {
        self.update_named("muscle", m.id.0, &m.name, None, None, None, None)?;
        self.get_muscle_by_id(m.id)
    }
    pub fn delete_muscle(&self, id: MuscleId) -> RepositoryResult<()> {
        self.delete("muscle", id.0)
    }
    pub fn create_template(&self, name: &str, status: Status) -> RepositoryResult<Template> {
        self.create_named("template", name, Some(status), None, None, None)?
            .try_into()
    }
    pub fn get_template_by_id(&self, id: TemplateId) -> RepositoryResult<Template> {
        self.get_timed("template", id.0)?.try_into()
    }
    pub fn list_templates(&self) -> RepositoryResult<Vec<Template>> {
        self.list_timed("template", None)?
            .into_iter()
            .map(TryInto::try_into)
            .collect()
    }
    pub fn update_template(&self, t: &Template) -> RepositoryResult<Template> {
        self.update_named(
            "template",
            t.id.0,
            &t.name,
            Some(t.status),
            None,
            None,
            None,
        )?;
        self.get_template_by_id(t.id)
    }
    pub fn delete_template(&self, id: TemplateId) -> RepositoryResult<()> {
        self.delete("template", id.0)
    }
    pub fn create_workout_template(
        &self,
        template_id: TemplateId,
        name: &str,
        position: i64,
    ) -> RepositoryResult<WorkoutTemplate> {
        self.create_named(
            "workout_template",
            name,
            None,
            Some(template_id.0),
            None,
            Some(position),
        )?
        .try_into()
    }
    pub fn get_workout_template_by_id(
        &self,
        id: WorkoutTemplateId,
    ) -> RepositoryResult<WorkoutTemplate> {
        self.get_timed("workout_template", id.0)?.try_into()
    }
    pub fn list_workout_templates_by_template_id(
        &self,
        id: TemplateId,
    ) -> RepositoryResult<Vec<WorkoutTemplate>> {
        self.list_timed("workout_template", Some(id.0))?
            .into_iter()
            .map(TryInto::try_into)
            .collect()
    }
    pub fn update_workout_template(
        &self,
        w: &WorkoutTemplate,
    ) -> RepositoryResult<WorkoutTemplate> {
        self.update_named(
            "workout_template",
            w.id.0,
            &w.name,
            None,
            Some(w.template_id.0),
            None,
            Some(w.position),
        )?;
        self.get_workout_template_by_id(w.id)
    }
    pub fn delete_workout_template(&self, id: WorkoutTemplateId) -> RepositoryResult<()> {
        self.delete("workout_template", id.0)
    }
    pub fn create_exercise(&self, name: &str, primary: MuscleId) -> RepositoryResult<Exercise> {
        let n = Self::now();
        self.conn.execute(
            "INSERT INTO exercise(name,parent_id,body_weight,min_reps_hypertrophy,max_reps_hypertrophy,created_at,updated_at) VALUES(?,?,?,?,?,?,?)",
            params![name, primary.0, 0, 0, 0, n, n],
        )?;
        self.get_exercise_by_id(ExerciseId(self.conn.last_insert_rowid()))
    }
    pub fn get_exercise_by_id(&self, id: ExerciseId) -> RepositoryResult<Exercise> {
        self.get_timed("exercise", id.0)?.try_into()
    }
    pub fn list_exercises(&self) -> RepositoryResult<Vec<Exercise>> {
        self.list_timed("exercise", None)?
            .into_iter()
            .map(TryInto::try_into)
            .collect()
    }
    pub fn list_exercises_by_primary_muscle(
        &self,
        muscle_id: MuscleId,
    ) -> RepositoryResult<Vec<Exercise>> {
        self.query_exercises(
            "WHERE parent_id=? ORDER BY name",
            &[&muscle_id.0 as &dyn rusqlite::ToSql],
        )
    }
    pub fn list_exercises_by_muscle(
        &self,
        muscle_id: MuscleId,
        include_secondary: bool,
    ) -> RepositoryResult<Vec<Exercise>> {
        if include_secondary {
            self.query_exercises(
                "WHERE parent_id=? OR id IN (SELECT exercise_id FROM exercise_secondary_muscle WHERE muscle_id=?) ORDER BY name",
                &[&muscle_id.0, &muscle_id.0],
            )
        } else {
            self.list_exercises_by_primary_muscle(muscle_id)
        }
    }
    pub fn list_body_weight_exercises(&self) -> RepositoryResult<Vec<Exercise>> {
        self.query_exercises("WHERE body_weight=1 ORDER BY name", &[])
    }
    pub fn search_exercises_by_name(&self, query: &str) -> RepositoryResult<Vec<Exercise>> {
        let pattern = format!("%{}%", query);
        self.query_exercises(
            "WHERE name LIKE ? ORDER BY name",
            &[&pattern as &dyn rusqlite::ToSql],
        )
    }
    fn query_exercises(
        &self,
        clause: &str,
        params: &[&dyn rusqlite::ToSql],
    ) -> RepositoryResult<Vec<Exercise>> {
        let sql = format!("SELECT id,name,status,parent_id,secondary_id,position,body_weight,min_reps_hypertrophy,max_reps_hypertrophy,created_at,updated_at FROM exercise {clause}");
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(params, row_timed)?;
        rows.map(|r| r.map_err(Into::into).and_then(TryInto::try_into))
            .collect()
    }
    pub fn update_exercise(&self, e: &Exercise) -> RepositoryResult<Exercise> {
        self.conn.execute("UPDATE exercise SET name=?,parent_id=?,body_weight=?,min_reps_hypertrophy=?,max_reps_hypertrophy=?,updated_at=? WHERE id=?", params![e.name,e.primary_muscle_id.0,e.body_weight as i64,e.min_reps_hypertrophy,e.max_reps_hypertrophy,Self::now(),e.id.0])?;
        self.get_exercise_by_id(e.id)
    }
    pub fn delete_exercise(&self, id: ExerciseId) -> RepositoryResult<()> {
        self.delete("exercise", id.0)
    }
    pub fn create_lift_template(
        &self,
        wt: WorkoutTemplateId,
        ex: ExerciseId,
        position: i64,
    ) -> RepositoryResult<LiftTemplate> {
        self.create_named(
            "lift_template",
            "",
            None,
            Some(wt.0),
            Some(ex.0),
            Some(position),
        )?
        .try_into()
    }
    pub fn get_lift_template_by_id(&self, id: LiftTemplateId) -> RepositoryResult<LiftTemplate> {
        self.get_timed("lift_template", id.0)?.try_into()
    }
    pub fn list_lift_templates_by_workout_template_id(
        &self,
        id: WorkoutTemplateId,
    ) -> RepositoryResult<Vec<LiftTemplate>> {
        self.list_timed("lift_template", Some(id.0))?
            .into_iter()
            .map(TryInto::try_into)
            .collect()
    }
    pub fn update_lift_template(&self, l: &LiftTemplate) -> RepositoryResult<LiftTemplate> {
        self.update_named(
            "lift_template",
            l.id.0,
            "",
            None,
            Some(l.workout_template_id.0),
            Some(l.exercise_id.0),
            Some(l.position),
        )?;
        self.get_lift_template_by_id(l.id)
    }
    pub fn delete_lift_template(&self, id: LiftTemplateId) -> RepositoryResult<()> {
        self.delete("lift_template", id.0)
    }
    pub fn create_program(
        &self,
        name: &str,
        weeks: i64,
        status: Status,
        locked: bool,
        template_id: Option<TemplateId>,
    ) -> RepositoryResult<Program> {
        let n = Self::now();
        self.conn.execute("INSERT INTO program(name,program_length_weeks,status,locked,template_id,created_at,updated_at) VALUES(?,?,?,?,?,?,?)", params![name,weeks,status.as_str(),locked as i64,template_id.map(|v|v.0),n,n])?;
        self.get_program_by_id(ProgramId(self.conn.last_insert_rowid()))
    }
    pub fn get_program_by_id(&self, id: ProgramId) -> RepositoryResult<Program> {
        self.conn.query_row("SELECT id,name,program_length_weeks,status,locked,template_id,created_at,updated_at FROM program WHERE id=?",[id.0],|r|Ok(ProgramRow{id:r.get(0)?,name:r.get(1)?,program_length_weeks:r.get(2)?,status:r.get(3)?,locked:r.get(4)?,template_id:r.get(5)?,created_at:r.get(6)?,updated_at:r.get(7)?}))?.try_into()
    }
    pub fn list_programs(&self) -> RepositoryResult<Vec<Program>> {
        let mut s=self.conn.prepare("SELECT id,name,program_length_weeks,status,locked,template_id,created_at,updated_at FROM program ORDER BY id")?;
        let rows = s.query_map([], |r| {
            Ok(ProgramRow {
                id: r.get(0)?,
                name: r.get(1)?,
                program_length_weeks: r.get(2)?,
                status: r.get(3)?,
                locked: r.get(4)?,
                template_id: r.get(5)?,
                created_at: r.get(6)?,
                updated_at: r.get(7)?,
            })
        })?;
        rows.map(|r| r.map_err(Into::into).and_then(TryInto::try_into))
            .collect()
    }
    pub fn update_program(&self, p: &Program) -> RepositoryResult<Program> {
        self.conn.execute("UPDATE program SET name=?,program_length_weeks=?,status=?,locked=?,template_id=?,updated_at=? WHERE id=?", params![p.name,p.program_length_weeks,p.status.as_str(),p.locked as i64,p.template_id.map(|v|v.0),Self::now(),p.id.0])?;
        self.get_program_by_id(p.id)
    }
    pub fn delete_program(&self, id: ProgramId) -> RepositoryResult<()> {
        self.delete("program", id.0)
    }
    pub fn create_workout(
        &self,
        program_id: ProgramId,
        name: &str,
        status: Status,
    ) -> RepositoryResult<Workout> {
        let n = Self::now();
        self.conn.execute(
            "INSERT INTO workout(program_id,name,status,created_at,updated_at) VALUES(?,?,?,?,?)",
            params![program_id.0, name, status.as_str(), n, n],
        )?;
        self.get_workout_by_id(WorkoutId(self.conn.last_insert_rowid()))
    }
    pub fn get_workout_by_id(&self, id: WorkoutId) -> RepositoryResult<Workout> {
        self.conn.query_row("SELECT id,program_id,name,status,scheduled_at,created_at,updated_at FROM workout WHERE id=?",[id.0],|r|Ok(WorkoutRow{id:r.get(0)?,program_id:r.get(1)?,name:r.get(2)?,status:r.get(3)?,scheduled_at:r.get(4)?,created_at:r.get(5)?,updated_at:r.get(6)?}))?.try_into()
    }
    pub fn list_workouts_by_program_id(&self, id: ProgramId) -> RepositoryResult<Vec<Workout>> {
        self.query_workouts("WHERE program_id=?", id.0)
    }
    pub fn list_workouts(&self) -> RepositoryResult<Vec<Workout>> {
        self.query_workouts("", 0)
    }
    fn query_workouts(&self, clause: &str, arg: i64) -> RepositoryResult<Vec<Workout>> {
        let sql=format!("SELECT id,program_id,name,status,scheduled_at,created_at,updated_at FROM workout {clause} ORDER BY id");
        let mut s = self.conn.prepare(&sql)?;
        let rows = if clause.is_empty() {
            s.query_map([], row_workout)?
                .collect::<Result<Vec<_>, _>>()?
        } else {
            s.query_map([arg], row_workout)?
                .collect::<Result<Vec<_>, _>>()?
        };
        rows.into_iter().map(TryInto::try_into).collect()
    }
    pub fn update_workout(&self, w: &Workout) -> RepositoryResult<Workout> {
        self.conn.execute("UPDATE workout SET program_id=?,name=?,status=?,scheduled_at=?,updated_at=? WHERE id=?",params![w.program_id.0,w.name,w.status.as_str(),w.scheduled_at.map(|d|d.to_rfc3339()),Self::now(),w.id.0])?;
        self.get_workout_by_id(w.id)
    }
    pub fn delete_workout(&self, id: WorkoutId) -> RepositoryResult<()> {
        self.delete("workout", id.0)
    }
    pub fn create_lift(
        &self,
        workout_id: WorkoutId,
        exercise_id: ExerciseId,
        status: Status,
        position: i64,
    ) -> RepositoryResult<Lift> {
        let n = Self::now();
        self.conn.execute("INSERT INTO lift(workout_id,exercise_id,status,position,created_at,updated_at) VALUES(?,?,?,?,?,?)",params![workout_id.0,exercise_id.0,status.as_str(),position,n,n])?;
        self.get_lift_by_id(LiftId(self.conn.last_insert_rowid()))
    }
    pub fn get_lift_by_id(&self, id: LiftId) -> RepositoryResult<Lift> {
        self.conn.query_row("SELECT id,workout_id,exercise_id,status,position,created_at,updated_at FROM lift WHERE id=?",[id.0],row_lift)?.try_into()
    }
    pub fn list_lifts_by_workout_id(&self, id: WorkoutId) -> RepositoryResult<Vec<Lift>> {
        let mut s=self.conn.prepare("SELECT id,workout_id,exercise_id,status,position,created_at,updated_at FROM lift WHERE workout_id=? ORDER BY id")?;
        let rows = s.query_map([id.0], row_lift)?;
        rows.map(|r| r.map_err(Into::into).and_then(TryInto::try_into))
            .collect()
    }
    pub fn update_lift(&self, l: &Lift) -> RepositoryResult<Lift> {
        self.conn.execute("UPDATE lift SET workout_id=?,exercise_id=?,status=?,position=?,updated_at=? WHERE id=?",params![l.workout_id.0,l.exercise_id.0,l.status.as_str(),l.position,Self::now(),l.id.0])?;
        self.get_lift_by_id(l.id)
    }
    pub fn delete_lift(&self, id: LiftId) -> RepositoryResult<()> {
        self.delete("lift", id.0)
    }
    pub fn create_set(
        &self,
        lift_id: LiftId,
        position: i64,
        reps: i64,
        weight_lb: f64,
        completed: bool,
    ) -> RepositoryResult<Set> {
        let n = Self::now();
        self.conn.execute("INSERT INTO sets(lift_id,position,reps,weight_lb,completed,created_at,updated_at) VALUES(?,?,?,?,?,?,?)",params![lift_id.0,position,reps,weight_lb,completed as i64,n,n])?;
        self.get_set_by_id(SetId(self.conn.last_insert_rowid()))
    }
    pub fn get_set_by_id(&self, id: SetId) -> RepositoryResult<Set> {
        self.conn.query_row("SELECT id,lift_id,position,reps,weight_lb,completed,created_at,updated_at FROM sets WHERE id=?",[id.0],row_set)?.try_into()
    }
    pub fn list_sets_by_lift_id(&self, id: LiftId) -> RepositoryResult<Vec<Set>> {
        let mut s=self.conn.prepare("SELECT id,lift_id,position,reps,weight_lb,completed,created_at,updated_at FROM sets WHERE lift_id=? ORDER BY id")?;
        let rows = s.query_map([id.0], row_set)?;
        rows.map(|r| r.map_err(Into::into).and_then(TryInto::try_into))
            .collect()
    }
    pub fn update_set(&self, set: &Set) -> RepositoryResult<Set> {
        self.conn.execute("UPDATE sets SET lift_id=?,position=?,reps=?,weight_lb=?,completed=?,updated_at=? WHERE id=?",params![set.lift_id.0,set.position,set.reps,set.weight_lb,set.completed as i64,Self::now(),set.id.0])?;
        self.get_set_by_id(set.id)
    }
    pub fn delete_set(&self, id: SetId) -> RepositoryResult<()> {
        self.delete("sets", id.0)
    }
    pub fn create_feedback(
        &self,
        lift_id: LiftId,
        note: &str,
        rating: i64,
    ) -> RepositoryResult<Feedback> {
        let n = Self::now();
        self.conn.execute(
            "INSERT INTO feedback(lift_id,note,rating,created_at,updated_at) VALUES(?,?,?,?,?)",
            params![lift_id.0, note, rating, n, n],
        )?;
        self.get_feedback_by_id(FeedbackId(self.conn.last_insert_rowid()))
    }
    pub fn get_feedback_by_id(&self, id: FeedbackId) -> RepositoryResult<Feedback> {
        self.conn
            .query_row(
                "SELECT id,lift_id,note,rating,created_at,updated_at FROM feedback WHERE id=?",
                [id.0],
                row_feedback,
            )?
            .try_into()
    }
    pub fn list_feedback_by_lift_id(&self, id: LiftId) -> RepositoryResult<Vec<Feedback>> {
        let mut s=self.conn.prepare("SELECT id,lift_id,note,rating,created_at,updated_at FROM feedback WHERE lift_id=? ORDER BY id")?;
        let rows = s.query_map([id.0], row_feedback)?;
        rows.map(|r| r.map_err(Into::into).and_then(TryInto::try_into))
            .collect()
    }
    pub fn update_feedback(&self, f: &Feedback) -> RepositoryResult<Feedback> {
        self.conn.execute(
            "UPDATE feedback SET lift_id=?,note=?,rating=?,updated_at=? WHERE id=?",
            params![f.lift_id.0, f.note, f.rating, Self::now(), f.id.0],
        )?;
        self.get_feedback_by_id(f.id)
    }
    pub fn delete_feedback(&self, id: FeedbackId) -> RepositoryResult<()> {
        self.delete("feedback", id.0)
    }
    pub fn add_focus_muscle(&self, t: TemplateId, m: MuscleId) -> RepositoryResult<()> {
        let count: i64 = self.conn.query_row(
            "SELECT COUNT(*) FROM template_focus_muscle WHERE template_id=?",
            [t.0],
            |r| r.get(0),
        )?;
        if count >= 4 {
            return Err(RepositoryError::ValidationError(
                "templates may have at most 4 focus muscles".into(),
            ));
        }
        self.conn.execute(
            "INSERT OR IGNORE INTO template_focus_muscle(template_id,muscle_id) VALUES(?,?)",
            params![t.0, m.0],
        )?;
        Ok(())
    }
    pub fn remove_focus_muscle(&self, t: TemplateId, m: MuscleId) -> RepositoryResult<()> {
        self.conn.execute(
            "DELETE FROM template_focus_muscle WHERE template_id=? AND muscle_id=?",
            params![t.0, m.0],
        )?;
        Ok(())
    }
    pub fn list_focus_muscles(&self, t: TemplateId) -> RepositoryResult<Vec<TemplateFocusMuscle>> {
        let mut s=self.conn.prepare("SELECT template_id,muscle_id FROM template_focus_muscle WHERE template_id=? ORDER BY muscle_id")?;
        let rows = s.query_map([t.0], |r| {
            Ok(TemplateFocusMuscle {
                template_id: TemplateId(r.get(0)?),
                muscle_id: MuscleId(r.get(1)?),
            })
        })?;
        rows.map(|r| r.map_err(Into::into)).collect()
    }
    pub fn replace_focus_muscles(&self, t: TemplateId, ids: &[MuscleId]) -> RepositoryResult<()> {
        if ids.len() > 4 {
            return Err(RepositoryError::ValidationError(
                "templates may have at most 4 focus muscles".into(),
            ));
        }
        self.conn.execute(
            "DELETE FROM template_focus_muscle WHERE template_id=?",
            [t.0],
        )?;
        for id in ids {
            self.add_focus_muscle(t, *id)?;
        }
        Ok(())
    }
    pub fn add_secondary_muscle(&self, e: ExerciseId, m: MuscleId) -> RepositoryResult<()> {
        self.conn.execute(
            "INSERT OR IGNORE INTO exercise_secondary_muscle(exercise_id,muscle_id) VALUES(?,?)",
            params![e.0, m.0],
        )?;
        Ok(())
    }
    pub fn remove_secondary_muscle(&self, e: ExerciseId, m: MuscleId) -> RepositoryResult<()> {
        self.conn.execute(
            "DELETE FROM exercise_secondary_muscle WHERE exercise_id=? AND muscle_id=?",
            params![e.0, m.0],
        )?;
        Ok(())
    }
    pub fn list_secondary_muscles(
        &self,
        e: ExerciseId,
    ) -> RepositoryResult<Vec<ExerciseSecondaryMuscle>> {
        let mut s=self.conn.prepare("SELECT exercise_id,muscle_id FROM exercise_secondary_muscle WHERE exercise_id=? ORDER BY muscle_id")?;
        let rows = s.query_map([e.0], |r| {
            Ok(ExerciseSecondaryMuscle {
                exercise_id: ExerciseId(r.get(0)?),
                muscle_id: MuscleId(r.get(1)?),
            })
        })?;
        rows.map(|r| r.map_err(Into::into)).collect()
    }
    pub fn replace_secondary_muscles(
        &self,
        e: ExerciseId,
        ids: &[MuscleId],
    ) -> RepositoryResult<()> {
        self.conn.execute(
            "DELETE FROM exercise_secondary_muscle WHERE exercise_id=?",
            [e.0],
        )?;
        for id in ids {
            self.add_secondary_muscle(e, *id)?;
        }
        Ok(())
    }
    pub fn initialize_app_state_if_missing(&self) -> RepositoryResult<AppState> {
        let n = Self::now();
        self.conn.execute(
            "INSERT OR IGNORE INTO app_state(id,created_at,updated_at) VALUES(1,?,?)",
            params![n, n],
        )?;
        self.get_app_state()
    }
    pub fn get_app_state(&self) -> RepositoryResult<AppState> {
        self.initialize_app_state_if_missing_no_recurse()?;
        self.conn.query_row("SELECT id,active_program_id,active_workout_id,active_lift_id,user_body_weight_lb,created_at,updated_at FROM app_state WHERE id=1",[],|r|Ok(AppStateRow{id:r.get(0)?,active_program_id:r.get(1)?,active_workout_id:r.get(2)?,active_lift_id:r.get(3)?,user_body_weight_lb:r.get(4)?,created_at:r.get(5)?,updated_at:r.get(6)?}))?.try_into()
    }
    fn initialize_app_state_if_missing_no_recurse(&self) -> RepositoryResult<()> {
        let n = Self::now();
        self.conn.execute(
            "INSERT OR IGNORE INTO app_state(id,created_at,updated_at) VALUES(1,?,?)",
            params![n, n],
        )?;
        Ok(())
    }
    pub fn update_active_program(&self, id: Option<ProgramId>) -> RepositoryResult<AppState> {
        self.conn.execute(
            "UPDATE app_state SET active_program_id=?,updated_at=? WHERE id=1",
            params![id.map(|v| v.0), Self::now()],
        )?;
        self.get_app_state()
    }
    pub fn update_active_workout(&self, id: Option<WorkoutId>) -> RepositoryResult<AppState> {
        self.conn.execute(
            "UPDATE app_state SET active_workout_id=?,updated_at=? WHERE id=1",
            params![id.map(|v| v.0), Self::now()],
        )?;
        self.get_app_state()
    }
    pub fn update_active_lift(&self, id: Option<LiftId>) -> RepositoryResult<AppState> {
        self.conn.execute(
            "UPDATE app_state SET active_lift_id=?,updated_at=? WHERE id=1",
            params![id.map(|v| v.0), Self::now()],
        )?;
        self.get_app_state()
    }
    pub fn clear_active_program_state(&self) -> RepositoryResult<AppState> {
        self.conn.execute("UPDATE app_state SET active_program_id=NULL,active_workout_id=NULL,active_lift_id=NULL,updated_at=? WHERE id=1",[Self::now()])?;
        self.get_app_state()
    }
    pub fn update_user_body_weight(&self, weight_lb: Option<f64>) -> RepositoryResult<AppState> {
        self.conn.execute(
            "UPDATE app_state SET user_body_weight_lb=?,updated_at=? WHERE id=1",
            params![weight_lb, Self::now()],
        )?;
        self.get_app_state()
    }
    fn create_named(
        &self,
        table: &str,
        name: &str,
        status: Option<Status>,
        parent: Option<i64>,
        secondary: Option<i64>,
        position: Option<i64>,
    ) -> RepositoryResult<TimedRow> {
        let n = Self::now();
        self.conn.execute(&format!("INSERT INTO {table}(name,status,parent_id,secondary_id,position,created_at,updated_at) VALUES(?,?,?,?,?,?,?)"),params![name,status.map(|s|s.as_str()),parent,secondary,position,n,n])?;
        self.get_timed(table, self.conn.last_insert_rowid())
    }
    fn get_timed(&self, table: &str, id: i64) -> RepositoryResult<TimedRow> {
        self.conn.query_row(&format!("SELECT id,name,status,parent_id,secondary_id,position,body_weight,min_reps_hypertrophy,max_reps_hypertrophy,created_at,updated_at FROM {table} WHERE id=?"),[id],row_timed)?.pipe(Ok)
    }
    fn list_timed(&self, table: &str, parent: Option<i64>) -> RepositoryResult<Vec<TimedRow>> {
        let sql = if parent.is_some() {
            format!("SELECT id,name,status,parent_id,secondary_id,position,body_weight,min_reps_hypertrophy,max_reps_hypertrophy,created_at,updated_at FROM {table} WHERE parent_id=? ORDER BY id")
        } else {
            format!("SELECT id,name,status,parent_id,secondary_id,position,body_weight,min_reps_hypertrophy,max_reps_hypertrophy,created_at,updated_at FROM {table} ORDER BY id")
        };
        let mut s = self.conn.prepare(&sql)?;
        let rows = if let Some(p) = parent {
            s.query_map([p], row_timed)?
                .collect::<Result<Vec<_>, _>>()?
        } else {
            s.query_map([], row_timed)?.collect::<Result<Vec<_>, _>>()?
        };
        Ok(rows)
    }
    fn update_named(
        &self,
        table: &str,
        id: i64,
        name: &str,
        status: Option<Status>,
        parent: Option<i64>,
        secondary: Option<i64>,
        position: Option<i64>,
    ) -> RepositoryResult<()> {
        self.conn.execute(&format!("UPDATE {table} SET name=?,status=?,parent_id=?,secondary_id=?,position=?,updated_at=? WHERE id=?"),params![name,status.map(|s|s.as_str()),parent,secondary,position,Self::now(),id])?;
        Ok(())
    }
    fn delete(&self, table: &str, id: i64) -> RepositoryResult<()> {
        let n = self
            .conn
            .execute(&format!("DELETE FROM {table} WHERE id=?"), [id])?;
        if n == 0 {
            Err(RepositoryError::NotFound)
        } else {
            Ok(())
        }
    }
}
trait Pipe: Sized {
    fn pipe<T>(self, f: impl FnOnce(Self) -> T) -> T {
        f(self)
    }
}
impl<T> Pipe for T {}
fn row_timed(r: &rusqlite::Row) -> rusqlite::Result<TimedRow> {
    Ok(TimedRow {
        id: r.get(0)?,
        name: r.get(1)?,
        status: r.get(2)?,
        parent_id: r.get(3)?,
        secondary_id: r.get(4)?,
        position: r.get(5)?,
        body_weight: r.get(6)?,
        min_reps_hypertrophy: r.get(7)?,
        max_reps_hypertrophy: r.get(8)?,
        created_at: r.get(9)?,
        updated_at: r.get(10)?,
    })
}
fn row_workout(r: &rusqlite::Row) -> rusqlite::Result<WorkoutRow> {
    Ok(WorkoutRow {
        id: r.get(0)?,
        program_id: r.get(1)?,
        name: r.get(2)?,
        status: r.get(3)?,
        scheduled_at: r.get(4)?,
        created_at: r.get(5)?,
        updated_at: r.get(6)?,
    })
}
fn row_lift(r: &rusqlite::Row) -> rusqlite::Result<LiftRow> {
    Ok(LiftRow {
        id: r.get(0)?,
        workout_id: r.get(1)?,
        exercise_id: r.get(2)?,
        status: r.get(3)?,
        position: r.get(4)?,
        created_at: r.get(5)?,
        updated_at: r.get(6)?,
    })
}
fn row_set(r: &rusqlite::Row) -> rusqlite::Result<SetRow> {
    Ok(SetRow {
        id: r.get(0)?,
        lift_id: r.get(1)?,
        position: r.get(2)?,
        reps: r.get(3)?,
        weight_lb: r.get(4)?,
        completed: r.get(5)?,
        created_at: r.get(6)?,
        updated_at: r.get(7)?,
    })
}
fn row_feedback(r: &rusqlite::Row) -> rusqlite::Result<FeedbackRow> {
    Ok(FeedbackRow {
        id: r.get(0)?,
        lift_id: r.get(1)?,
        note: r.get(2)?,
        rating: r.get(3)?,
        created_at: r.get(4)?,
        updated_at: r.get(5)?,
    })
}
pub const DEFAULT_MUSCLE_NAMES: &[&str] = &[
    "Chest",
    "Shoulders",
    "Biceps",
    "Triceps",
    "Back",
    "Core",
    "Glutes",
    "Hamstrings",
    "Quads",
    "Calves",
    "Wrists",
];

const DEFAULT_EXERCISES_JSON: &str = include_str!("../seeds/default_exercises.json");

#[derive(Debug, Deserialize)]
struct DefaultExerciseSeed {
    name: String,
    primary_muscle: String,
    secondary_muscles: Vec<String>,
    body_weight: bool,
    min_reps_hypertrophy: i64,
    max_reps_hypertrophy: i64,
}

const SCHEMA: &str = r#"
PRAGMA foreign_keys=ON;
CREATE TABLE IF NOT EXISTS muscle(id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE, status TEXT, parent_id INTEGER, secondary_id INTEGER, position INTEGER, body_weight INTEGER, min_reps_hypertrophy INTEGER, max_reps_hypertrophy INTEGER, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS template(id INTEGER PRIMARY KEY, name TEXT NOT NULL, status TEXT NOT NULL, parent_id INTEGER, secondary_id INTEGER, position INTEGER, body_weight INTEGER, min_reps_hypertrophy INTEGER, max_reps_hypertrophy INTEGER, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS workout_template(id INTEGER PRIMARY KEY, name TEXT NOT NULL, status TEXT, parent_id INTEGER NOT NULL REFERENCES template(id) ON DELETE CASCADE, secondary_id INTEGER, position INTEGER NOT NULL DEFAULT 0, body_weight INTEGER, min_reps_hypertrophy INTEGER, max_reps_hypertrophy INTEGER, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS exercise(id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE, status TEXT, parent_id INTEGER NOT NULL REFERENCES muscle(id), secondary_id INTEGER, position INTEGER, body_weight INTEGER NOT NULL DEFAULT 0, min_reps_hypertrophy INTEGER NOT NULL DEFAULT 0, max_reps_hypertrophy INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS lift_template(id INTEGER PRIMARY KEY, name TEXT, status TEXT, parent_id INTEGER NOT NULL REFERENCES workout_template(id) ON DELETE CASCADE, secondary_id INTEGER NOT NULL REFERENCES exercise(id), position INTEGER NOT NULL DEFAULT 0, body_weight INTEGER, min_reps_hypertrophy INTEGER, max_reps_hypertrophy INTEGER, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS program(id INTEGER PRIMARY KEY, name TEXT NOT NULL, program_length_weeks INTEGER NOT NULL, status TEXT NOT NULL, locked INTEGER NOT NULL DEFAULT 0, template_id INTEGER REFERENCES template(id), created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS workout(id INTEGER PRIMARY KEY, program_id INTEGER NOT NULL REFERENCES program(id) ON DELETE CASCADE, name TEXT NOT NULL, status TEXT NOT NULL, scheduled_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS lift(id INTEGER PRIMARY KEY, workout_id INTEGER NOT NULL REFERENCES workout(id) ON DELETE CASCADE, exercise_id INTEGER NOT NULL REFERENCES exercise(id), status TEXT NOT NULL, position INTEGER NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS sets(id INTEGER PRIMARY KEY, lift_id INTEGER NOT NULL REFERENCES lift(id) ON DELETE CASCADE, position INTEGER NOT NULL, reps INTEGER NOT NULL, weight_lb REAL NOT NULL, completed INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS feedback(id INTEGER PRIMARY KEY, lift_id INTEGER NOT NULL REFERENCES lift(id) ON DELETE CASCADE, note TEXT NOT NULL, rating INTEGER NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS template_focus_muscle(template_id INTEGER NOT NULL REFERENCES template(id) ON DELETE CASCADE, muscle_id INTEGER NOT NULL REFERENCES muscle(id), PRIMARY KEY(template_id,muscle_id));
CREATE TABLE IF NOT EXISTS exercise_secondary_muscle(exercise_id INTEGER NOT NULL REFERENCES exercise(id) ON DELETE CASCADE, muscle_id INTEGER NOT NULL REFERENCES muscle(id), PRIMARY KEY(exercise_id,muscle_id));
CREATE TABLE IF NOT EXISTS app_state(id INTEGER PRIMARY KEY CHECK(id=1), active_program_id INTEGER REFERENCES program(id), active_workout_id INTEGER REFERENCES workout(id), active_lift_id INTEGER REFERENCES lift(id), user_body_weight_lb REAL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
"#;

#[cfg(test)]
mod tests {
    use super::*;
    fn repo() -> Repository {
        Repository::new(Connection::open_in_memory().unwrap()).unwrap()
    }

    #[test]
    fn seeds_default_muscles_on_init() {
        let r = repo();
        let muscles = r.list_muscles().unwrap();
        let names: Vec<_> = muscles.iter().map(|m| m.name.as_str()).collect();

        assert_eq!(names, DEFAULT_MUSCLE_NAMES);
        assert!(muscles.iter().all(|m| m.created_at == m.updated_at));
    }

    #[test]
    fn default_muscle_seed_is_idempotent_and_preserves_existing_rows() {
        let conn = Connection::open_in_memory().unwrap();
        let r = Repository::new(conn).unwrap();
        let chest = r
            .list_muscles()
            .unwrap()
            .into_iter()
            .find(|m| m.name == "Chest")
            .unwrap();
        let custom = r.create_muscle("Neck").unwrap();
        let chest_created_at = chest.created_at;
        let custom_id = custom.id;

        let r = Repository::new(r.conn).unwrap();
        let muscles = r.list_muscles().unwrap();

        assert_eq!(muscles.iter().filter(|m| m.name == "Chest").count(), 1);
        assert_eq!(
            muscles
                .iter()
                .find(|m| m.name == "Chest")
                .unwrap()
                .created_at,
            chest_created_at
        );
        assert_eq!(
            muscles.iter().find(|m| m.name == "Neck").unwrap().id,
            custom_id
        );
    }

    #[test]
    fn seeds_default_exercise_catalog_and_filters_it() {
        let r = repo();
        let exercises = r.list_exercises().unwrap();
        assert!((200..=400).contains(&exercises.len()));

        let mut names = HashSet::new();
        for exercise in &exercises {
            assert!(names.insert(exercise.name.clone()));
            assert!(exercise.primary_muscle_id.0 > 0);
            assert!(exercise.min_reps_hypertrophy > 0);
            assert!(exercise.max_reps_hypertrophy >= exercise.min_reps_hypertrophy);
        }
        for excluded in ["Plank", "Wall Sit", "Farmer's Carry"] {
            assert!(!names.contains(excluded));
        }

        let muscles = r.list_muscles().unwrap();
        let muscle_by_name: HashMap<_, _> =
            muscles.iter().map(|m| (m.name.as_str(), m.id)).collect();
        let chest = muscle_by_name["Chest"];
        let core = muscle_by_name["Core"];
        let back = muscle_by_name["Back"];
        let quads = muscle_by_name["Quads"];

        let push_up = exercises.iter().find(|e| e.name == "Push-Up").unwrap();
        assert!(push_up.body_weight);
        let lat_pulldown = exercises.iter().find(|e| e.name == "Lat Pulldown").unwrap();
        assert!(!lat_pulldown.body_weight);
        let squat = exercises
            .iter()
            .find(|e| e.name == "Barbell Back Squat")
            .unwrap();
        let leg_press = exercises.iter().find(|e| e.name == "Leg Press").unwrap();
        assert!(squat.max_reps_hypertrophy < leg_press.max_reps_hypertrophy);

        assert!(r
            .list_exercises_by_primary_muscle(chest)
            .unwrap()
            .iter()
            .all(|e| e.primary_muscle_id == chest));
        assert!(r
            .list_exercises_by_muscle(core, true)
            .unwrap()
            .iter()
            .any(|e| e.name == "Push-Up"));
        assert!(r
            .list_body_weight_exercises()
            .unwrap()
            .iter()
            .any(|e| e.name == "Pull-Up"));
        assert!(r
            .search_exercises_by_name("deadlift")
            .unwrap()
            .iter()
            .any(|e| e.primary_muscle_id == back || e.primary_muscle_id == quads));
    }

    #[test]
    fn default_exercise_seed_is_idempotent_and_refreshes_secondaries() {
        let r = repo();
        let before = r.list_exercises().unwrap().len();
        let push_up = r
            .list_exercises()
            .unwrap()
            .into_iter()
            .find(|e| e.name == "Push-Up")
            .unwrap();
        r.replace_secondary_muscles(push_up.id, &[]).unwrap();

        r.seed_default_exercises().unwrap();
        assert_eq!(r.list_exercises().unwrap().len(), before);
        assert!(!r.list_secondary_muscles(push_up.id).unwrap().is_empty());
    }

    #[test]
    fn crud_and_child_lists() {
        let r = repo();
        let m = r.create_muscle("Serratus").unwrap();
        let m2 = r.create_muscle("Teres Major").unwrap();
        let t = r.create_template("Base", Status::Planned).unwrap();
        r.add_focus_muscle(t.id, m.id).unwrap();
        assert_eq!(r.list_focus_muscles(t.id).unwrap().len(), 1);
        let wt = r.create_workout_template(t.id, "Day 1", 1).unwrap();
        let e = r.create_exercise("Bench", m.id).unwrap();
        r.add_secondary_muscle(e.id, m2.id).unwrap();
        assert_eq!(r.list_secondary_muscles(e.id).unwrap().len(), 1);
        let _lt = r.create_lift_template(wt.id, e.id, 1).unwrap();
        assert_eq!(
            r.list_lift_templates_by_workout_template_id(wt.id)
                .unwrap()
                .len(),
            1
        );
        let p = r
            .create_program("P", 4, Status::Active, false, Some(t.id))
            .unwrap();
        let w = r.create_workout(p.id, "W", Status::Planned).unwrap();
        assert_eq!(r.list_workouts_by_program_id(p.id).unwrap().len(), 1);
        let l = r.create_lift(w.id, e.id, Status::Planned, 1).unwrap();
        assert_eq!(r.list_lifts_by_workout_id(w.id).unwrap().len(), 1);
        let s = r.create_set(l.id, 1, 5, 225.0, false).unwrap();
        let f = r.create_feedback(l.id, "ok", 3).unwrap();
        assert_eq!(r.list_sets_by_lift_id(l.id).unwrap()[0].id, s.id);
        assert_eq!(r.list_feedback_by_lift_id(l.id).unwrap()[0].id, f.id);
        let mut p2 = p.clone();
        p2.locked = true;
        assert!(r.update_program(&p2).unwrap().locked);
        r.delete_set(s.id).unwrap();
        assert!(matches!(
            r.get_set_by_id(s.id),
            Err(RepositoryError::NotFound)
        ));
    }
    #[test]
    fn invalid_status_errors() {
        let r = repo();
        r.connection().execute("INSERT INTO program(name,program_length_weeks,status,locked,created_at,updated_at) VALUES('bad',1,'bogus',0,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z')",[]).unwrap();
        assert!(matches!(
            r.list_programs(),
            Err(RepositoryError::MappingError(_))
        ));
    }
    #[test]
    fn app_state_singleton_and_focus_limit() {
        let r = repo();
        assert_eq!(r.get_app_state().unwrap().id, AppStateId(1));
        let m: Vec<_> = (0..5)
            .map(|i| r.create_muscle(&format!("m{i}")).unwrap())
            .collect();
        let t = r.create_template("T", Status::Planned).unwrap();
        r.replace_focus_muscles(t.id, &[m[0].id, m[1].id, m[2].id, m[3].id])
            .unwrap();
        assert!(matches!(
            r.add_focus_muscle(t.id, m[4].id),
            Err(RepositoryError::ValidationError(_))
        ));
        assert_eq!(
            r.update_user_body_weight(Some(200.0))
                .unwrap()
                .user_body_weight_lb,
            Some(200.0)
        );
    }
}
