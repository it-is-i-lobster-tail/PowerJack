use crate::{db::repositories::Repository, domain::Muscle};
use rusqlite::Connection;
use std::{
    env, fs,
    path::{Path, PathBuf},
};

const DB_ENV_VAR: &str = "POWERJACK_DB_PATH";
const DB_FILE_NAME: &str = "powerjack.sqlite3";

pub fn list_muscles() -> Result<Vec<Muscle>, String> {
    let repo = open_repository()?;
    repo.list_muscles().map_err(|err| err.to_string())
}

fn open_repository() -> Result<Repository, String> {
    let path = database_path()?;
    if let Some(parent) = path.parent() {
        create_dir_if_needed(parent)?;
    }

    let conn = Connection::open(&path)
        .map_err(|err| format!("failed to open database at {}: {err}", path.display()))?;
    Repository::new(conn).map_err(|err| err.to_string())
}

fn database_path() -> Result<PathBuf, String> {
    if let Some(path) = env::var_os(DB_ENV_VAR).filter(|path| !path.is_empty()) {
        return Ok(PathBuf::from(path));
    }

    default_data_dir().map(|dir| dir.join(DB_FILE_NAME))
}

#[cfg(target_os = "macos")]
fn default_data_dir() -> Result<PathBuf, String> {
    env::var_os("HOME")
        .filter(|home| !home.is_empty())
        .map(PathBuf::from)
        .map(|home| {
            home.join("Library")
                .join("Application Support")
                .join("PowerJack")
        })
        .ok_or_else(|| "HOME is not set; cannot locate PowerJack app data directory".to_string())
}

#[cfg(target_os = "windows")]
fn default_data_dir() -> Result<PathBuf, String> {
    env::var_os("APPDATA")
        .filter(|appdata| !appdata.is_empty())
        .map(PathBuf::from)
        .map(|appdata| appdata.join("PowerJack"))
        .ok_or_else(|| "APPDATA is not set; cannot locate PowerJack app data directory".to_string())
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
fn default_data_dir() -> Result<PathBuf, String> {
    if let Some(data_home) = env::var_os("XDG_DATA_HOME").filter(|path| !path.is_empty()) {
        return Ok(PathBuf::from(data_home).join("powerjack"));
    }

    env::var_os("HOME")
        .filter(|home| !home.is_empty())
        .map(PathBuf::from)
        .map(|home| home.join(".local").join("share").join("powerjack"))
        .ok_or_else(|| "HOME is not set; cannot locate PowerJack app data directory".to_string())
}

fn create_dir_if_needed(path: &Path) -> Result<(), String> {
    fs::create_dir_all(path).map_err(|err| {
        format!(
            "failed to create database directory {}: {err}",
            path.display()
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::repositories::DEFAULT_MUSCLE_NAMES;
    use std::sync::Mutex;
    use tempfile::tempdir;

    static ENV_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn list_muscles_uses_env_db_path_and_seeds_defaults() {
        let _guard = ENV_LOCK.lock().unwrap();
        let previous = env::var_os(DB_ENV_VAR);
        let dir = tempdir().unwrap();
        let db_path = dir.path().join(DB_FILE_NAME);

        env::set_var(DB_ENV_VAR, &db_path);
        let names: Vec<_> = list_muscles()
            .unwrap()
            .into_iter()
            .map(|muscle| muscle.name)
            .collect();

        match previous {
            Some(path) => env::set_var(DB_ENV_VAR, path),
            None => env::remove_var(DB_ENV_VAR),
        }

        assert!(db_path.exists());
        assert_eq!(names, DEFAULT_MUSCLE_NAMES);
    }
}
