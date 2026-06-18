use powerjack_core::domain::{Exercise, Muscle, Program, Template};

use crate::{traits::WorkoutStorage, RepositoryError, RepositoryResult};

#[derive(Debug, Default)]
pub struct BrowserStorage;

impl WorkoutStorage for BrowserStorage {
    fn list_muscles(&self) -> RepositoryResult<Vec<Muscle>> {
        Err(RepositoryError::StorageUnavailable(
            "browser storage adapter is not implemented yet".into(),
        ))
    }

    fn list_exercises(&self) -> RepositoryResult<Vec<Exercise>> {
        Err(RepositoryError::StorageUnavailable(
            "browser storage adapter is not implemented yet".into(),
        ))
    }

    fn list_templates(&self) -> RepositoryResult<Vec<Template>> {
        Err(RepositoryError::StorageUnavailable(
            "browser storage adapter is not implemented yet".into(),
        ))
    }

    fn create_program_from_template(
        &self,
        _template_id: i64,
        _name: &str,
        _weeks: i64,
    ) -> RepositoryResult<Program> {
        Err(RepositoryError::StorageUnavailable(
            "browser storage adapter is not implemented yet".into(),
        ))
    }
}
