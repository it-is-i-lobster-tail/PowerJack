use powerjack_core::domain::{Exercise, Muscle, Program, Template};

use crate::RepositoryResult;

pub trait WorkoutStorage {
    fn list_muscles(&self) -> RepositoryResult<Vec<Muscle>>;
    fn list_templates(&self) -> RepositoryResult<Vec<Template>>;
    fn list_exercises(&self) -> RepositoryResult<Vec<Exercise>>;
    fn create_program_from_template(
        &self,
        template_id: i64,
        name: &str,
        weeks: i64,
    ) -> RepositoryResult<Program>;
}
