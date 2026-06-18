use powerjack_core::domain::{Muscle, Program, Template};

#[cfg(feature = "server-storage")]
pub fn list_muscles() -> Result<Vec<Muscle>, String> {
    powerjack_storage::server_sqlite::list_muscles()
}

#[cfg(feature = "server-storage")]
pub fn list_templates() -> Result<Vec<Template>, String> {
    powerjack_storage::server_sqlite::list_templates()
}

#[cfg(feature = "server-storage")]
pub fn create_program_from_template(
    template_id: i64,
    name: &str,
    weeks: i64,
) -> Result<Program, String> {
    powerjack_storage::server_sqlite::create_program_from_template(template_id, name, weeks)
}

#[cfg(not(feature = "server-storage"))]
pub fn list_muscles() -> Result<Vec<Muscle>, String> {
    use powerjack_storage::{browser_storage::BrowserStorage, traits::WorkoutStorage};

    BrowserStorage.list_muscles().map_err(|err| err.to_string())
}

#[cfg(not(feature = "server-storage"))]
pub fn list_templates() -> Result<Vec<Template>, String> {
    use powerjack_storage::{browser_storage::BrowserStorage, traits::WorkoutStorage};

    BrowserStorage
        .list_templates()
        .map_err(|err| err.to_string())
}

#[cfg(not(feature = "server-storage"))]
pub fn create_program_from_template(
    template_id: i64,
    name: &str,
    weeks: i64,
) -> Result<Program, String> {
    use powerjack_storage::{browser_storage::BrowserStorage, traits::WorkoutStorage};

    BrowserStorage
        .create_program_from_template(template_id, name, weeks)
        .map_err(|err| err.to_string())
}
