use crate::{
    domain::*,
    repository::{RepositoryError, RepositoryResult},
};
use chrono::{DateTime, Utc};
use rusqlite::{params, Connection};
use serde::Deserialize;
use std::{
    collections::{HashMap, HashSet},
    str::FromStr,
};

pub struct Repository {
    conn: Connection,
}

impl Repository {
    pub fn new(conn: Connection) -> RepositoryResult<Self> {
        conn.execute_batch(SCHEMA)?;
        let repo = Self { conn };
        repo.seed_default_muscles()?;
        repo.seed_default_exercises()?;
        repo.initialize_app_state_if_missing()?;
        Ok(repo)
    }
    pub fn connection(&self) -> &Connection {
        &self.conn
    }
    fn now() -> String {
        Utc::now().to_rfc3339()
    }

    fn seed_default_muscles(&self) -> RepositoryResult<()> {
        let n = Self::now();
        for name in DEFAULT_MUSCLE_NAMES {
            self.conn.execute(
                "INSERT OR IGNORE INTO muscle(name,created_at,updated_at) VALUES(?,?,?)",
                params![name, n, n],
            )?;
        }
        Ok(())
    }

    pub fn seed_default_exercises(&self) -> RepositoryResult<()> {
        let seeds: Vec<DefaultExerciseSeed> = serde_json::from_str(DEFAULT_EXERCISES_JSON)
            .map_err(|e| RepositoryError::MappingError(e.to_string()))?;
        let mut muscles = HashMap::new();
        let rows = query(
            &self.conn,
            "SELECT id,name,created_at,updated_at FROM muscle",
            [],
            row_muscle,
        )?;
        for muscle in rows {
            muscles.insert(muscle.name, muscle.id);
        }

        let mut seen = HashSet::new();
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
            self.conn.execute(
                "INSERT INTO exercise(name,primary_muscle_id,body_weight,min_reps_hypertrophy,max_reps_hypertrophy,created_at,updated_at) VALUES(?,?,?,?,?,?,?)
                 ON CONFLICT(name) DO UPDATE SET primary_muscle_id=excluded.primary_muscle_id,body_weight=excluded.body_weight,min_reps_hypertrophy=excluded.min_reps_hypertrophy,max_reps_hypertrophy=excluded.max_reps_hypertrophy,updated_at=excluded.updated_at",
                params![
                    seed.name.as_str(),
                    primary_id.0,
                    seed.body_weight as i64,
                    seed.min_reps_hypertrophy,
                    seed.max_reps_hypertrophy,
                    n,
                    n
                ],
            )?;
            let exercise_id: i64 = self.conn.query_row(
                "SELECT id FROM exercise WHERE name=?",
                [seed.name.as_str()],
                |r| r.get(0),
            )?;
            self.conn.execute(
                "DELETE FROM exercise_secondary_muscle WHERE exercise_id=?",
                [exercise_id],
            )?;
            for secondary_id in secondary_ids {
                self.conn.execute(
                    "INSERT INTO exercise_secondary_muscle(exercise_id,muscle_id) VALUES(?,?)",
                    params![exercise_id, secondary_id.0],
                )?;
            }
        }
        Ok(())
    }

    pub fn create_muscle(&self, name: &str) -> RepositoryResult<Muscle> {
        let n = Self::now();
        self.conn.execute(
            "INSERT INTO muscle(name,created_at,updated_at) VALUES(?,?,?)",
            params![name, n, n],
        )?;
        self.get_muscle_by_id(MuscleId(self.conn.last_insert_rowid()))
    }
    pub fn get_muscle_by_id(&self, id: MuscleId) -> RepositoryResult<Muscle> {
        self.conn
            .query_row(
                "SELECT id,name,created_at,updated_at FROM muscle WHERE id=?",
                [id.0],
                row_muscle,
            )?
            .pipe(Ok)
    }
    pub fn list_muscles(&self) -> RepositoryResult<Vec<Muscle>> {
        query(
            &self.conn,
            "SELECT id,name,created_at,updated_at FROM muscle ORDER BY id",
            [],
            row_muscle,
        )
    }

    pub fn create_template(
        &self,
        name: &str,
        workouts_per_week: i64,
    ) -> RepositoryResult<Template> {
        let n = Self::now();
        self.conn.execute(
            "INSERT INTO template(name,workouts_per_week,created_at,updated_at) VALUES(?,?,?,?)",
            params![name, workouts_per_week, n, n],
        )?;
        self.get_template_by_id(TemplateId(self.conn.last_insert_rowid()))
    }
    pub fn get_template_by_id(&self, id: TemplateId) -> RepositoryResult<Template> {
        self.conn
            .query_row(
                "SELECT id,name,workouts_per_week,created_at,updated_at FROM template WHERE id=?",
                [id.0],
                row_template,
            )?
            .pipe(Ok)
    }
    pub fn list_templates(&self) -> RepositoryResult<Vec<Template>> {
        query(
            &self.conn,
            "SELECT id,name,workouts_per_week,created_at,updated_at FROM template ORDER BY id",
            [],
            row_template,
        )
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
            "INSERT INTO template_focus_muscle(template_id,muscle_id) VALUES(?,?)",
            params![t.0, m.0],
        )?;
        Ok(())
    }
    pub fn list_focus_muscles(&self, t: TemplateId) -> RepositoryResult<Vec<TemplateFocusMuscle>> {
        query(&self.conn,"SELECT template_id,muscle_id FROM template_focus_muscle WHERE template_id=? ORDER BY muscle_id",[t.0],|r|Ok(TemplateFocusMuscle{template_id:TemplateId(r.get(0)?),muscle_id:MuscleId(r.get(1)?)}))
    }

    pub fn create_workout_template(
        &self,
        template_id: TemplateId,
        order: i64,
    ) -> RepositoryResult<WorkoutTemplate> {
        let n = Self::now();
        self.conn.execute("INSERT INTO workout_template(template_id,\"order\",created_at,updated_at) VALUES(?,?,?,?)",params![template_id.0,order,n,n])?;
        self.get_workout_template_by_id(WorkoutTemplateId(self.conn.last_insert_rowid()))
    }
    pub fn get_workout_template_by_id(
        &self,
        id: WorkoutTemplateId,
    ) -> RepositoryResult<WorkoutTemplate> {
        self.conn.query_row("SELECT id,template_id,\"order\",created_at,updated_at FROM workout_template WHERE id=?",[id.0],row_workout_template)?.pipe(Ok)
    }
    pub fn list_workout_templates_by_template_id(
        &self,
        id: TemplateId,
    ) -> RepositoryResult<Vec<WorkoutTemplate>> {
        query(&self.conn,"SELECT id,template_id,\"order\",created_at,updated_at FROM workout_template WHERE template_id=? ORDER BY \"order\"",[id.0],row_workout_template)
    }

    pub fn create_exercise(
        &self,
        name: &str,
        primary: MuscleId,
        body_weight: bool,
        min: Option<i64>,
        max: Option<i64>,
    ) -> RepositoryResult<Exercise> {
        let n = Self::now();
        self.conn.execute("INSERT INTO exercise(name,primary_muscle_id,body_weight,min_reps_hypertrophy,max_reps_hypertrophy,created_at,updated_at) VALUES(?,?,?,?,?,?,?)",params![name,primary.0,body_weight as i64,min,max,n,n])?;
        self.get_exercise_by_id(ExerciseId(self.conn.last_insert_rowid()))
    }
    pub fn get_exercise_by_id(&self, id: ExerciseId) -> RepositoryResult<Exercise> {
        self.conn.query_row("SELECT id,name,primary_muscle_id,body_weight,min_reps_hypertrophy,max_reps_hypertrophy,created_at,updated_at FROM exercise WHERE id=?",[id.0],row_exercise)?.pipe(Ok)
    }
    pub fn list_exercises(&self) -> RepositoryResult<Vec<Exercise>> {
        query(&self.conn,"SELECT id,name,primary_muscle_id,body_weight,min_reps_hypertrophy,max_reps_hypertrophy,created_at,updated_at FROM exercise ORDER BY id",[],row_exercise)
    }
    pub fn list_exercises_by_primary_muscle(
        &self,
        muscle_id: MuscleId,
    ) -> RepositoryResult<Vec<Exercise>> {
        self.query_exercises(
            "WHERE primary_muscle_id=? ORDER BY name",
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
                "WHERE primary_muscle_id=? OR id IN (SELECT exercise_id FROM exercise_secondary_muscle WHERE muscle_id=?) ORDER BY name",
                &[&muscle_id.0, &muscle_id.0],
            )
        } else {
            self.list_exercises_by_primary_muscle(muscle_id)
        }
    }
    pub fn list_body_weight_exercises(&self) -> RepositoryResult<Vec<Exercise>> {
        self.query_exercises("WHERE body_weight=1 ORDER BY name", &[])
    }
    pub fn search_exercises_by_name(&self, query_text: &str) -> RepositoryResult<Vec<Exercise>> {
        let pattern = format!("%{query_text}%");
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
        let sql = format!("SELECT id,name,primary_muscle_id,body_weight,min_reps_hypertrophy,max_reps_hypertrophy,created_at,updated_at FROM exercise {clause}");
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(params, row_exercise)?;
        rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
    }
    pub fn add_secondary_muscle(&self, e: ExerciseId, m: MuscleId) -> RepositoryResult<()> {
        self.conn.execute(
            "INSERT INTO exercise_secondary_muscle(exercise_id,muscle_id) VALUES(?,?)",
            params![e.0, m.0],
        )?;
        Ok(())
    }
    pub fn list_secondary_muscles(
        &self,
        e: ExerciseId,
    ) -> RepositoryResult<Vec<ExerciseSecondaryMuscle>> {
        query(&self.conn,"SELECT exercise_id,muscle_id FROM exercise_secondary_muscle WHERE exercise_id=? ORDER BY muscle_id",[e.0],|r|Ok(ExerciseSecondaryMuscle{exercise_id:ExerciseId(r.get(0)?),muscle_id:MuscleId(r.get(1)?)}))
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

    pub fn create_lift_template(
        &self,
        workout_template_id: WorkoutTemplateId,
        exercise_id: ExerciseId,
        order: i64,
    ) -> RepositoryResult<LiftTemplate> {
        let n = Self::now();
        self.conn.execute("INSERT INTO lift_template(workout_template_id,exercise_id,\"order\",created_at,updated_at) VALUES(?,?,?,?,?)",params![workout_template_id.0,exercise_id.0,order,n,n])?;
        self.get_lift_template_by_id(LiftTemplateId(self.conn.last_insert_rowid()))
    }
    pub fn get_lift_template_by_id(&self, id: LiftTemplateId) -> RepositoryResult<LiftTemplate> {
        self.conn.query_row("SELECT id,workout_template_id,exercise_id,\"order\",created_at,updated_at FROM lift_template WHERE id=?",[id.0],row_lift_template)?.pipe(Ok)
    }
    pub fn list_lift_templates_by_workout_template_id(
        &self,
        id: WorkoutTemplateId,
    ) -> RepositoryResult<Vec<LiftTemplate>> {
        query(&self.conn,"SELECT id,workout_template_id,exercise_id,\"order\",created_at,updated_at FROM lift_template WHERE workout_template_id=? ORDER BY \"order\"",[id.0],row_lift_template)
    }

    pub fn create_program(
        &self,
        name: &str,
        weeks: i64,
        template_id: Option<TemplateId>,
    ) -> RepositoryResult<Program> {
        let n = Self::now();
        self.conn.execute("INSERT INTO program(name,program_length_weeks,template_id,created_at,updated_at) VALUES(?,?,?,?,?)",params![name,weeks,template_id.map(|v|v.0),n,n])?;
        let p = self.get_program_by_id(ProgramId(self.conn.last_insert_rowid()))?;
        self.update_active_program(Some(p.id))?;
        Ok(p)
    }

    pub fn create_program_from_template(
        &self,
        name: &str,
        weeks: i64,
        template_id: TemplateId,
    ) -> RepositoryResult<Program> {
        let program = self.create_program(name, weeks, Some(template_id))?;
        let workout_templates = self.list_workout_templates_by_template_id(template_id)?;
        let mut first_workout = None;
        let mut first_lift = None;
        for week in 1..=weeks {
            for wt in &workout_templates {
                let workout = self.create_workout(
                    program.id,
                    ((week - 1) * workout_templates.len() as i64) + wt.order,
                    wt.order,
                    week,
                )?;
                first_workout.get_or_insert(workout.id);
                for lt in self.list_lift_templates_by_workout_template_id(wt.id)? {
                    let lift = self.create_lift(workout.id, lt.exercise_id, lt.order)?;
                    first_lift.get_or_insert(lift.id);
                }
            }
        }
        self.update_active_workout(first_workout)?;
        self.update_active_lift(first_lift)?;
        Ok(program)
    }

    pub fn get_program_by_id(&self, id: ProgramId) -> RepositoryResult<Program> {
        self.conn.query_row("SELECT id,name,program_length_weeks,status,locked,template_id,created_at,updated_at FROM program WHERE id=?",[id.0],row_program)?.pipe(Ok)
    }
    pub fn list_programs(&self) -> RepositoryResult<Vec<Program>> {
        query(&self.conn,"SELECT id,name,program_length_weeks,status,locked,template_id,created_at,updated_at FROM program ORDER BY id",[],row_program)
    }

    pub fn create_workout(
        &self,
        program_id: ProgramId,
        order: i64,
        workout_day: i64,
        program_week: i64,
    ) -> RepositoryResult<Workout> {
        let n = Self::now();
        self.conn.execute("INSERT INTO workout(\"order\",workout_day,program_week,program_id,created_at,updated_at) VALUES(?,?,?,?,?,?)",params![order,workout_day,program_week,program_id.0,n,n])?;
        self.get_workout_by_id(WorkoutId(self.conn.last_insert_rowid()))
    }
    pub fn get_workout_by_id(&self, id: WorkoutId) -> RepositoryResult<Workout> {
        self.conn.query_row("SELECT id,\"order\",workout_day,program_week,hidden,locked,status,program_id,created_at,updated_at FROM workout WHERE id=?",[id.0],row_workout)?.pipe(Ok)
    }
    pub fn list_workouts_by_program_id(&self, id: ProgramId) -> RepositoryResult<Vec<Workout>> {
        query(&self.conn,"SELECT id,\"order\",workout_day,program_week,hidden,locked,status,program_id,created_at,updated_at FROM workout WHERE program_id=? ORDER BY \"order\"",[id.0],row_workout)
    }

    pub fn create_lift(
        &self,
        workout_id: WorkoutId,
        exercise_id: ExerciseId,
        order: i64,
    ) -> RepositoryResult<Lift> {
        let n = Self::now();
        self.conn.execute("INSERT INTO lift(exercise_id,workout_id,\"order\",created_at,updated_at) VALUES(?,?,?,?,?)",params![exercise_id.0,workout_id.0,order,n,n])?;
        self.get_lift_by_id(LiftId(self.conn.last_insert_rowid()))
    }
    pub fn get_lift_by_id(&self, id: LiftId) -> RepositoryResult<Lift> {
        self.conn.query_row("SELECT id,exercise_id,workout_id,locked,hidden,\"order\",status,planned,created_at,updated_at FROM lift WHERE id=?",[id.0],row_lift)?.pipe(Ok)
    }
    pub fn list_lifts_by_workout_id(&self, id: WorkoutId) -> RepositoryResult<Vec<Lift>> {
        query(&self.conn,"SELECT id,exercise_id,workout_id,locked,hidden,\"order\",status,planned,created_at,updated_at FROM lift WHERE workout_id=? ORDER BY \"order\"",[id.0],row_lift)
    }

    pub fn create_set(
        &self,
        lift_id: LiftId,
        order: i64,
        planned_reps: Option<i64>,
        planned_weight: Option<i64>,
    ) -> RepositoryResult<Set> {
        let n = Self::now();
        self.conn.execute("INSERT INTO \"set\"(planned_reps,planned_weight,\"order\",lift_id,created_at,updated_at) VALUES(?,?,?,?,?,?)",params![planned_reps,planned_weight,order,lift_id.0,n,n])?;
        self.get_set_by_id(SetId(self.conn.last_insert_rowid()))
    }
    pub fn get_set_by_id(&self, id: SetId) -> RepositoryResult<Set> {
        self.conn.query_row("SELECT id,planned_reps,actual_reps,planned_weight,actual_weight,\"order\",lift_id,locked,hidden,status,planned,created_at,updated_at FROM \"set\" WHERE id=?",[id.0],row_set)?.pipe(Ok)
    }
    pub fn list_sets_by_lift_id(&self, id: LiftId) -> RepositoryResult<Vec<Set>> {
        query(&self.conn,"SELECT id,planned_reps,actual_reps,planned_weight,actual_weight,\"order\",lift_id,locked,hidden,status,planned,created_at,updated_at FROM \"set\" WHERE lift_id=? ORDER BY \"order\"",[id.0],row_set)
    }

    pub fn create_feedback(
        &self,
        lift_id: LiftId,
        pain: Option<i64>,
        effort: Option<i64>,
    ) -> RepositoryResult<Feedback> {
        let n = Self::now();
        self.conn.execute("INSERT INTO feedback(level_of_pain,level_of_effort,lift_id,created_at,updated_at) VALUES(?,?,?,?,?)",params![pain,effort,lift_id.0,n,n])?;
        self.get_feedback_by_id(FeedbackId(self.conn.last_insert_rowid()))
    }
    pub fn get_feedback_by_id(&self, id: FeedbackId) -> RepositoryResult<Feedback> {
        self.conn.query_row("SELECT id,level_of_pain,level_of_effort,lift_id,created_at,updated_at FROM feedback WHERE id=?",[id.0],row_feedback)?.pipe(Ok)
    }
    pub fn list_feedback_by_lift_id(&self, id: LiftId) -> RepositoryResult<Vec<Feedback>> {
        query(&self.conn,"SELECT id,level_of_pain,level_of_effort,lift_id,created_at,updated_at FROM feedback WHERE lift_id=? ORDER BY id",[id.0],row_feedback)
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
        self.conn.query_row("SELECT id,active_program_id,active_workout_id,active_lift_id,user_body_weight_lb,user_body_weight_updated_last,created_at,updated_at FROM app_state WHERE id=1",[],row_app_state)?.pipe(Ok)
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
    pub fn update_user_body_weight(&self, weight: Option<i64>) -> RepositoryResult<AppState> {
        self.conn.execute("UPDATE app_state SET user_body_weight_lb=?,user_body_weight_updated_last=?,updated_at=? WHERE id=1",params![weight,weight.map(|_|Self::now()),Self::now()])?;
        self.get_app_state()
    }
}

fn dt(s: String) -> rusqlite::Result<DateTime<Utc>> {
    Ok(DateTime::parse_from_rfc3339(&s)
        .map_err(|e| {
            rusqlite::Error::FromSqlConversionFailure(0, rusqlite::types::Type::Text, Box::new(e))
        })?
        .with_timezone(&Utc))
}
fn status(s: String) -> rusqlite::Result<Status> {
    Status::from_str(&s).map_err(|e| {
        rusqlite::Error::FromSqlConversionFailure(
            0,
            rusqlite::types::Type::Text,
            Box::new(std::io::Error::new(std::io::ErrorKind::InvalidData, e)),
        )
    })
}
fn query<T, P, F>(conn: &Connection, sql: &str, params: P, mut f: F) -> RepositoryResult<Vec<T>>
where
    P: rusqlite::Params,
    F: FnMut(&rusqlite::Row<'_>) -> rusqlite::Result<T>,
{
    let mut stmt = conn.prepare(sql)?;
    let rows = stmt.query_map(params, |r| f(r))?;
    rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
}
trait Pipe: Sized {
    fn pipe<T>(self, f: impl FnOnce(Self) -> T) -> T {
        f(self)
    }
}
impl<T> Pipe for T {}
fn row_muscle(r: &rusqlite::Row) -> rusqlite::Result<Muscle> {
    Ok(Muscle {
        id: MuscleId(r.get(0)?),
        name: r.get(1)?,
        created_at: dt(r.get(2)?)?,
        updated_at: dt(r.get(3)?)?,
    })
}
fn row_template(r: &rusqlite::Row) -> rusqlite::Result<Template> {
    Ok(Template {
        id: TemplateId(r.get(0)?),
        name: r.get(1)?,
        workouts_per_week: r.get(2)?,
        created_at: dt(r.get(3)?)?,
        updated_at: dt(r.get(4)?)?,
    })
}
fn row_workout_template(r: &rusqlite::Row) -> rusqlite::Result<WorkoutTemplate> {
    Ok(WorkoutTemplate {
        id: WorkoutTemplateId(r.get(0)?),
        template_id: TemplateId(r.get(1)?),
        order: r.get(2)?,
        created_at: dt(r.get(3)?)?,
        updated_at: dt(r.get(4)?)?,
    })
}
fn row_lift_template(r: &rusqlite::Row) -> rusqlite::Result<LiftTemplate> {
    Ok(LiftTemplate {
        id: LiftTemplateId(r.get(0)?),
        workout_template_id: WorkoutTemplateId(r.get(1)?),
        exercise_id: ExerciseId(r.get(2)?),
        order: r.get(3)?,
        created_at: dt(r.get(4)?)?,
        updated_at: dt(r.get(5)?)?,
    })
}
fn row_exercise(r: &rusqlite::Row) -> rusqlite::Result<Exercise> {
    Ok(Exercise {
        id: ExerciseId(r.get(0)?),
        name: r.get(1)?,
        primary_muscle_id: MuscleId(r.get(2)?),
        body_weight: r.get::<_, i64>(3)? != 0,
        min_reps_hypertrophy: r.get(4)?,
        max_reps_hypertrophy: r.get(5)?,
        created_at: dt(r.get(6)?)?,
        updated_at: dt(r.get(7)?)?,
    })
}
fn row_program(r: &rusqlite::Row) -> rusqlite::Result<Program> {
    Ok(Program {
        id: ProgramId(r.get(0)?),
        name: r.get(1)?,
        program_length_weeks: r.get(2)?,
        status: status(r.get(3)?)?,
        locked: r.get::<_, i64>(4)? != 0,
        template_id: r.get::<_, Option<i64>>(5)?.map(TemplateId),
        created_at: dt(r.get(6)?)?,
        updated_at: dt(r.get(7)?)?,
    })
}
fn row_workout(r: &rusqlite::Row) -> rusqlite::Result<Workout> {
    Ok(Workout {
        id: WorkoutId(r.get(0)?),
        order: r.get(1)?,
        workout_day: r.get(2)?,
        program_week: r.get(3)?,
        hidden: r.get::<_, i64>(4)? != 0,
        locked: r.get::<_, i64>(5)? != 0,
        status: status(r.get(6)?)?,
        program_id: ProgramId(r.get(7)?),
        created_at: dt(r.get(8)?)?,
        updated_at: dt(r.get(9)?)?,
    })
}
fn row_lift(r: &rusqlite::Row) -> rusqlite::Result<Lift> {
    Ok(Lift {
        id: LiftId(r.get(0)?),
        exercise_id: ExerciseId(r.get(1)?),
        workout_id: WorkoutId(r.get(2)?),
        locked: r.get::<_, i64>(3)? != 0,
        hidden: r.get::<_, i64>(4)? != 0,
        order: r.get(5)?,
        status: status(r.get(6)?)?,
        planned: r.get::<_, i64>(7)? != 0,
        created_at: dt(r.get(8)?)?,
        updated_at: dt(r.get(9)?)?,
    })
}
fn row_set(r: &rusqlite::Row) -> rusqlite::Result<Set> {
    Ok(Set {
        id: SetId(r.get(0)?),
        planned_reps: r.get(1)?,
        actual_reps: r.get(2)?,
        planned_weight: r.get(3)?,
        actual_weight: r.get(4)?,
        order: r.get(5)?,
        lift_id: LiftId(r.get(6)?),
        locked: r.get::<_, i64>(7)? != 0,
        hidden: r.get::<_, i64>(8)? != 0,
        status: status(r.get(9)?)?,
        planned: r.get::<_, i64>(10)? != 0,
        created_at: dt(r.get(11)?)?,
        updated_at: dt(r.get(12)?)?,
    })
}
fn row_feedback(r: &rusqlite::Row) -> rusqlite::Result<Feedback> {
    Ok(Feedback {
        id: FeedbackId(r.get(0)?),
        level_of_pain: r.get(1)?,
        level_of_effort: r.get(2)?,
        lift_id: LiftId(r.get(3)?),
        created_at: dt(r.get(4)?)?,
        updated_at: dt(r.get(5)?)?,
    })
}
fn row_app_state(r: &rusqlite::Row) -> rusqlite::Result<AppState> {
    Ok(AppState {
        id: AppStateId(r.get(0)?),
        active_program_id: r.get::<_, Option<i64>>(1)?.map(ProgramId),
        active_workout_id: r.get::<_, Option<i64>>(2)?.map(WorkoutId),
        active_lift_id: r.get::<_, Option<i64>>(3)?.map(LiftId),
        user_body_weight_lb: r.get(4)?,
        user_body_weight_updated_last: r.get::<_, Option<String>>(5)?.map(dt).transpose()?,
        created_at: dt(r.get(6)?)?,
        updated_at: dt(r.get(7)?)?,
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

pub const SCHEMA: &str = r#"
PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS muscle(id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE, created_at TIMESTAMP NOT NULL, updated_at TIMESTAMP NOT NULL);
CREATE TABLE IF NOT EXISTS template(id INTEGER PRIMARY KEY, name TEXT NOT NULL, workouts_per_week INTEGER NOT NULL, created_at TIMESTAMP NOT NULL, updated_at TIMESTAMP NOT NULL);
CREATE TABLE IF NOT EXISTS template_focus_muscle(template_id INTEGER NOT NULL REFERENCES template(id) ON DELETE CASCADE, muscle_id INTEGER NOT NULL REFERENCES muscle(id), PRIMARY KEY(template_id,muscle_id));
CREATE TABLE IF NOT EXISTS workout_template(id INTEGER PRIMARY KEY, template_id INTEGER NOT NULL REFERENCES template(id) ON DELETE CASCADE, "order" INTEGER NOT NULL, created_at TIMESTAMP NOT NULL, updated_at TIMESTAMP NOT NULL, UNIQUE(template_id,"order"));
CREATE TABLE IF NOT EXISTS exercise(id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE, primary_muscle_id INTEGER NOT NULL REFERENCES muscle(id), body_weight BOOLEAN NOT NULL DEFAULT false, min_reps_hypertrophy INTEGER, max_reps_hypertrophy INTEGER, created_at TIMESTAMP NOT NULL, updated_at TIMESTAMP NOT NULL);
CREATE TABLE IF NOT EXISTS exercise_secondary_muscle(exercise_id INTEGER NOT NULL REFERENCES exercise(id) ON DELETE CASCADE, muscle_id INTEGER NOT NULL REFERENCES muscle(id), PRIMARY KEY(exercise_id,muscle_id));
CREATE TABLE IF NOT EXISTS lift_template(id INTEGER PRIMARY KEY, workout_template_id INTEGER NOT NULL REFERENCES workout_template(id) ON DELETE CASCADE, exercise_id INTEGER NOT NULL REFERENCES exercise(id), "order" INTEGER NOT NULL, created_at TIMESTAMP NOT NULL, updated_at TIMESTAMP NOT NULL, UNIQUE(workout_template_id,"order"));
CREATE TABLE IF NOT EXISTS program(id INTEGER PRIMARY KEY, name TEXT NOT NULL, program_length_weeks INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('complete','planned','halted','skipped','active')), locked BOOLEAN NOT NULL DEFAULT false, template_id INTEGER REFERENCES template(id), created_at TIMESTAMP NOT NULL, updated_at TIMESTAMP NOT NULL);
CREATE TABLE IF NOT EXISTS workout(id INTEGER PRIMARY KEY, "order" INTEGER NOT NULL, workout_day INTEGER NOT NULL, program_week INTEGER NOT NULL, hidden BOOLEAN NOT NULL DEFAULT false, locked BOOLEAN NOT NULL DEFAULT true, status TEXT NOT NULL DEFAULT 'planned' CHECK(status IN ('complete','planned','halted','skipped','active')), program_id INTEGER NOT NULL REFERENCES program(id) ON DELETE CASCADE, created_at TIMESTAMP NOT NULL, updated_at TIMESTAMP NOT NULL, UNIQUE(program_id,program_week,workout_day));
CREATE TABLE IF NOT EXISTS lift(id INTEGER PRIMARY KEY, exercise_id INTEGER NOT NULL REFERENCES exercise(id), workout_id INTEGER NOT NULL REFERENCES workout(id) ON DELETE CASCADE, locked BOOLEAN NOT NULL DEFAULT true, hidden BOOLEAN NOT NULL DEFAULT true, "order" INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'planned' CHECK(status IN ('complete','planned','halted','skipped','active')), planned BOOLEAN NOT NULL DEFAULT true, created_at TIMESTAMP NOT NULL, updated_at TIMESTAMP NOT NULL, UNIQUE(workout_id,"order"));
CREATE TABLE IF NOT EXISTS "set"(id INTEGER PRIMARY KEY, planned_reps INTEGER, actual_reps INTEGER, planned_weight INTEGER, actual_weight INTEGER, "order" INTEGER NOT NULL, lift_id INTEGER NOT NULL REFERENCES lift(id) ON DELETE CASCADE, locked BOOLEAN NOT NULL DEFAULT true, hidden BOOLEAN NOT NULL DEFAULT true, status TEXT NOT NULL DEFAULT 'planned' CHECK(status IN ('complete','planned','halted','skipped','active')), planned BOOLEAN NOT NULL DEFAULT true, created_at TIMESTAMP NOT NULL, updated_at TIMESTAMP NOT NULL, UNIQUE(lift_id,"order"));
CREATE TABLE IF NOT EXISTS feedback(id INTEGER PRIMARY KEY, level_of_pain INTEGER, level_of_effort INTEGER, lift_id INTEGER NOT NULL REFERENCES lift(id) ON DELETE CASCADE, created_at TIMESTAMP NOT NULL, updated_at TIMESTAMP NOT NULL);
CREATE TABLE IF NOT EXISTS app_state(id INTEGER PRIMARY KEY CHECK(id=1), active_program_id INTEGER REFERENCES program(id), active_workout_id INTEGER REFERENCES workout(id), active_lift_id INTEGER REFERENCES lift(id), user_body_weight_lb INTEGER, user_body_weight_updated_last TIMESTAMP, created_at TIMESTAMP NOT NULL, updated_at TIMESTAMP NOT NULL);
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
            assert!(exercise.min_reps_hypertrophy.unwrap_or_default() > 0);
            assert!(
                exercise.max_reps_hypertrophy.unwrap_or_default()
                    >= exercise.min_reps_hypertrophy.unwrap_or_default()
            );
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
    fn defaults_and_crud() {
        let r = repo();
        let m = r
            .list_muscles()
            .unwrap()
            .into_iter()
            .find(|m| m.name == "Chest")
            .unwrap();
        let t = r.create_template("Base", 3).unwrap();
        r.add_focus_muscle(t.id, m.id).unwrap();
        let wt = r.create_workout_template(t.id, 1).unwrap();
        let e = r
            .create_exercise("Bench", m.id, false, Some(6), Some(12))
            .unwrap();
        r.add_secondary_muscle(e.id, m.id).unwrap();
        assert!(r.add_secondary_muscle(e.id, m.id).is_err());
        let lt = r.create_lift_template(wt.id, e.id, 1).unwrap();
        assert_eq!(lt.order, 1);
        let p = r.create_program("P", 4, Some(t.id)).unwrap();
        assert_eq!(p.status, Status::Active);
        assert_eq!(r.get_app_state().unwrap().active_program_id, Some(p.id));
        let w = r.create_workout(p.id, 1, 1, 1).unwrap();
        assert!(w.locked);
        assert!(!w.hidden);
        let l = r.create_lift(w.id, e.id, 1).unwrap();
        assert!(l.locked && l.hidden && l.planned);
        let s = r.create_set(l.id, 1, Some(5), Some(225)).unwrap();
        assert!(s.locked && s.hidden && s.planned);
        let f = r.create_feedback(l.id, Some(1), Some(8)).unwrap();
        assert_eq!(f.level_of_effort, Some(8));
    }
    #[test]
    fn focus_limit_and_status_check() {
        let r = repo();
        let t = r.create_template("T", 2).unwrap();
        let ms: Vec<_> = (0..5)
            .map(|i| r.create_muscle(&format!("m{i}")).unwrap())
            .collect();
        for m in ms.iter().take(4) {
            r.add_focus_muscle(t.id, m.id).unwrap();
        }
        assert!(matches!(
            r.add_focus_muscle(t.id, ms[4].id),
            Err(RepositoryError::ValidationError(_))
        ));
        assert!(r.connection().execute("INSERT INTO program(name,program_length_weeks,status,created_at,updated_at) VALUES('bad',1,'bogus','x','x')",[]).is_err());
    }
}
