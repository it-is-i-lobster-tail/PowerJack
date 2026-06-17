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
    pub status: Status,
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
    pub name: String,
    pub position: i64,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct LiftTemplate {
    pub id: LiftTemplateId,
    pub workout_template_id: WorkoutTemplateId,
    pub exercise_id: ExerciseId,
    pub position: i64,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct Exercise {
    pub id: ExerciseId,
    pub name: String,
    pub primary_muscle_id: MuscleId,
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
    pub program_id: ProgramId,
    pub name: String,
    pub status: Status,
    pub scheduled_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct Lift {
    pub id: LiftId,
    pub workout_id: WorkoutId,
    pub exercise_id: ExerciseId,
    pub status: Status,
    pub position: i64,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct Set {
    pub id: SetId,
    pub lift_id: LiftId,
    pub position: i64,
    pub reps: i64,
    pub weight_lb: f64,
    pub completed: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct Feedback {
    pub id: FeedbackId,
    pub lift_id: LiftId,
    pub note: String,
    pub rating: i64,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct AppState {
    pub id: AppStateId,
    pub active_program_id: Option<ProgramId>,
    pub active_workout_id: Option<WorkoutId>,
    pub active_lift_id: Option<LiftId>,
    pub user_body_weight_lb: Option<f64>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
