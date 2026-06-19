#[derive(Debug, Clone)]
pub struct TimedRow {
    pub id: i64,
    pub name: String,
    pub status: Option<String>,
    pub parent_id: Option<i64>,
    pub secondary_id: Option<i64>,
    pub position: Option<i64>,
    pub body_weight: Option<i64>,
    pub min_reps_hypertrophy: Option<i64>,
    pub max_reps_hypertrophy: Option<i64>,
    pub created_at: String,
    pub updated_at: String,
}
#[derive(Debug, Clone)]
pub struct ProgramRow {
    pub id: i64,
    pub name: String,
    pub program_length_weeks: i64,
    pub status: String,
    pub locked: i64,
    pub template_id: Option<i64>,
    pub created_at: String,
    pub updated_at: String,
}
#[derive(Debug, Clone)]
pub struct WorkoutRow {
    pub id: i64,
    pub program_id: i64,
    pub name: String,
    pub status: String,
    pub scheduled_at: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}
#[derive(Debug, Clone)]
pub struct LiftRow {
    pub id: i64,
    pub workout_id: i64,
    pub exercise_id: i64,
    pub status: String,
    pub position: i64,
    pub created_at: String,
    pub updated_at: String,
}
#[derive(Debug, Clone)]
pub struct SetRow {
    pub id: i64,
    pub lift_id: i64,
    pub position: i64,
    pub reps: i64,
    pub weight_lb: f64,
    pub completed: i64,
    pub created_at: String,
    pub updated_at: String,
}
#[derive(Debug, Clone)]
pub struct FeedbackRow {
    pub id: i64,
    pub lift_id: i64,
    pub note: String,
    pub rating: i64,
    pub created_at: String,
    pub updated_at: String,
}
#[derive(Debug, Clone)]
pub struct AppStateRow {
    pub id: i64,
    pub active_program_id: Option<i64>,
    pub active_workout_id: Option<i64>,
    pub active_lift_id: Option<i64>,
    pub user_body_weight_lb: Option<f64>,
    pub created_at: String,
    pub updated_at: String,
}
