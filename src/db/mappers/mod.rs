use super::models::*;
use crate::{
    domain::*,
    repository::{RepositoryError, RepositoryResult},
};
use chrono::{DateTime, Utc};
use std::str::FromStr;
fn dt(s: &str) -> RepositoryResult<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(s)
        .map(|d| d.with_timezone(&Utc))
        .map_err(|e| RepositoryError::MappingError(e.to_string()))
}
fn st(s: &str) -> RepositoryResult<Status> {
    Status::from_str(s).map_err(RepositoryError::MappingError)
}
impl TryFrom<TimedRow> for Muscle {
    type Error = RepositoryError;
    fn try_from(r: TimedRow) -> RepositoryResult<Self> {
        Ok(Self {
            id: MuscleId(r.id),
            name: r.name,
            created_at: dt(&r.created_at)?,
            updated_at: dt(&r.updated_at)?,
        })
    }
}
impl TryFrom<TimedRow> for Template {
    type Error = RepositoryError;
    fn try_from(r: TimedRow) -> RepositoryResult<Self> {
        Ok(Self {
            id: TemplateId(r.id),
            name: r.name,
            status: st(r.status.as_deref().unwrap_or("planned"))?,
            created_at: dt(&r.created_at)?,
            updated_at: dt(&r.updated_at)?,
        })
    }
}
impl TryFrom<TimedRow> for WorkoutTemplate {
    type Error = RepositoryError;
    fn try_from(r: TimedRow) -> RepositoryResult<Self> {
        Ok(Self {
            id: WorkoutTemplateId(r.id),
            template_id: TemplateId(
                r.parent_id
                    .ok_or_else(|| RepositoryError::MappingError("missing template_id".into()))?,
            ),
            name: r.name,
            position: r.position.unwrap_or_default(),
            created_at: dt(&r.created_at)?,
            updated_at: dt(&r.updated_at)?,
        })
    }
}
impl TryFrom<TimedRow> for LiftTemplate {
    type Error = RepositoryError;
    fn try_from(r: TimedRow) -> RepositoryResult<Self> {
        Ok(Self {
            id: LiftTemplateId(r.id),
            workout_template_id: WorkoutTemplateId(r.parent_id.ok_or_else(|| {
                RepositoryError::MappingError("missing workout_template_id".into())
            })?),
            exercise_id: ExerciseId(
                r.secondary_id
                    .ok_or_else(|| RepositoryError::MappingError("missing exercise_id".into()))?,
            ),
            position: r.position.unwrap_or_default(),
            created_at: dt(&r.created_at)?,
            updated_at: dt(&r.updated_at)?,
        })
    }
}
impl TryFrom<TimedRow> for Exercise {
    type Error = RepositoryError;
    fn try_from(r: TimedRow) -> RepositoryResult<Self> {
        Ok(Self {
            id: ExerciseId(r.id),
            name: r.name,
            primary_muscle_id: MuscleId(r.parent_id.ok_or_else(|| {
                RepositoryError::MappingError("missing primary_muscle_id".into())
            })?),
            body_weight: r.body_weight.unwrap_or_default() != 0,
            min_reps_hypertrophy: r.min_reps_hypertrophy.unwrap_or(0),
            max_reps_hypertrophy: r.max_reps_hypertrophy.unwrap_or(0),
            created_at: dt(&r.created_at)?,
            updated_at: dt(&r.updated_at)?,
        })
    }
}
impl TryFrom<ProgramRow> for Program {
    type Error = RepositoryError;
    fn try_from(r: ProgramRow) -> RepositoryResult<Self> {
        Ok(Self {
            id: ProgramId(r.id),
            name: r.name,
            program_length_weeks: r.program_length_weeks,
            status: st(&r.status)?,
            locked: r.locked != 0,
            template_id: r.template_id.map(TemplateId),
            created_at: dt(&r.created_at)?,
            updated_at: dt(&r.updated_at)?,
        })
    }
}
impl TryFrom<WorkoutRow> for Workout {
    type Error = RepositoryError;
    fn try_from(r: WorkoutRow) -> RepositoryResult<Self> {
        Ok(Self {
            id: WorkoutId(r.id),
            program_id: ProgramId(r.program_id),
            name: r.name,
            status: st(&r.status)?,
            scheduled_at: r.scheduled_at.as_deref().map(dt).transpose()?,
            created_at: dt(&r.created_at)?,
            updated_at: dt(&r.updated_at)?,
        })
    }
}
impl TryFrom<LiftRow> for Lift {
    type Error = RepositoryError;
    fn try_from(r: LiftRow) -> RepositoryResult<Self> {
        Ok(Self {
            id: LiftId(r.id),
            workout_id: WorkoutId(r.workout_id),
            exercise_id: ExerciseId(r.exercise_id),
            status: st(&r.status)?,
            position: r.position,
            created_at: dt(&r.created_at)?,
            updated_at: dt(&r.updated_at)?,
        })
    }
}
impl TryFrom<SetRow> for Set {
    type Error = RepositoryError;
    fn try_from(r: SetRow) -> RepositoryResult<Self> {
        Ok(Self {
            id: SetId(r.id),
            lift_id: LiftId(r.lift_id),
            position: r.position,
            reps: r.reps,
            weight_lb: r.weight_lb,
            completed: r.completed != 0,
            created_at: dt(&r.created_at)?,
            updated_at: dt(&r.updated_at)?,
        })
    }
}
impl TryFrom<FeedbackRow> for Feedback {
    type Error = RepositoryError;
    fn try_from(r: FeedbackRow) -> RepositoryResult<Self> {
        Ok(Self {
            id: FeedbackId(r.id),
            lift_id: LiftId(r.lift_id),
            note: r.note,
            rating: r.rating,
            created_at: dt(&r.created_at)?,
            updated_at: dt(&r.updated_at)?,
        })
    }
}
impl TryFrom<AppStateRow> for AppState {
    type Error = RepositoryError;
    fn try_from(r: AppStateRow) -> RepositoryResult<Self> {
        Ok(Self {
            id: AppStateId(r.id),
            active_program_id: r.active_program_id.map(ProgramId),
            active_workout_id: r.active_workout_id.map(WorkoutId),
            active_lift_id: r.active_lift_id.map(LiftId),
            user_body_weight_lb: r.user_body_weight_lb,
            created_at: dt(&r.created_at)?,
            updated_at: dt(&r.updated_at)?,
        })
    }
}
