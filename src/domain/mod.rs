use chrono::{DateTime, Utc};
use std::str::FromStr;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    Complete,
    Planned,
    Halted,
    Skipped,
    Active,
}
impl Status {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Complete => "complete",
            Self::Planned => "planned",
            Self::Halted => "halted",
            Self::Skipped => "skipped",
            Self::Active => "active",
        }
    }
}
impl FromStr for Status {
    type Err = String;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "complete" => Ok(Self::Complete),
            "planned" => Ok(Self::Planned),
            "halted" => Ok(Self::Halted),
            "skipped" => Ok(Self::Skipped),
            "active" => Ok(Self::Active),
            other => Err(format!("invalid status '{other}'")),
        }
    }
}
macro_rules! id {
    ($name:ident) => {
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
        pub struct $name(pub i64);
    };
}
id!(MuscleId);
id!(TemplateId);
id!(WorkoutTemplateId);
id!(LiftTemplateId);
id!(ExerciseId);
id!(ProgramId);
id!(WorkoutId);
id!(LiftId);
id!(SetId);
id!(FeedbackId);
id!(AppStateId);

#[derive(Debug, Clone, PartialEq)]
pub struct Muscle {
    pub id: MuscleId,
    pub name: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct Template {
    pub id: TemplateId,
    pub name: String,
    pub workouts_per_week: i64,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct TemplateFocusMuscle {
    pub template_id: TemplateId,
    pub muscle_id: MuscleId,
}
#[derive(Debug, Clone, PartialEq)]
pub struct WorkoutTemplate {
    pub id: WorkoutTemplateId,
    pub template_id: TemplateId,
    pub order: i64,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct LiftTemplate {
    pub id: LiftTemplateId,
    pub workout_template_id: WorkoutTemplateId,
    pub exercise_id: ExerciseId,
    pub order: i64,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct Exercise {
    pub id: ExerciseId,
    pub name: String,
    pub primary_muscle_id: MuscleId,
    pub body_weight: bool,
    pub min_reps_hypertrophy: Option<i64>,
    pub max_reps_hypertrophy: Option<i64>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct ExerciseSecondaryMuscle {
    pub exercise_id: ExerciseId,
    pub muscle_id: MuscleId,
}
#[derive(Debug, Clone, PartialEq)]
pub struct Program {
    pub id: ProgramId,
    pub name: String,
    pub program_length_weeks: i64,
    pub status: Status,
    pub locked: bool,
    pub template_id: Option<TemplateId>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct Workout {
    pub id: WorkoutId,
    pub order: i64,
    pub workout_day: i64,
    pub program_week: i64,
    pub hidden: bool,
    pub locked: bool,
    pub status: Status,
    pub program_id: ProgramId,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct Lift {
    pub id: LiftId,
    pub exercise_id: ExerciseId,
    pub workout_id: WorkoutId,
    pub locked: bool,
    pub hidden: bool,
    pub order: i64,
    pub status: Status,
    pub planned: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct Set {
    pub id: SetId,
    pub planned_reps: Option<i64>,
    pub actual_reps: Option<i64>,
    pub planned_weight: Option<i64>,
    pub actual_weight: Option<i64>,
    pub order: i64,
    pub lift_id: LiftId,
    pub locked: bool,
    pub hidden: bool,
    pub status: Status,
    pub planned: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct Feedback {
    pub id: FeedbackId,
    pub level_of_pain: Option<i64>,
    pub level_of_effort: Option<i64>,
    pub lift_id: LiftId,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct AppState {
    pub id: AppStateId,
    pub active_program_id: Option<ProgramId>,
    pub active_workout_id: Option<WorkoutId>,
    pub active_lift_id: Option<LiftId>,
    pub user_body_weight_lb: Option<i64>,
    pub user_body_weight_updated_last: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
