use thiserror::Error;
#[derive(Debug, Error, PartialEq)]
pub enum RepositoryError {
    #[error("not found")]
    NotFound,
    #[error("validation error: {0}")]
    ValidationError(String),
    #[error("database error: {0}")]
    DatabaseError(String),
    #[error("mapping error: {0}")]
    MappingError(String),
}
impl From<rusqlite::Error> for RepositoryError {
    fn from(e: rusqlite::Error) -> Self {
        match e {
            rusqlite::Error::QueryReturnedNoRows => Self::NotFound,
            other => Self::DatabaseError(other.to_string()),
        }
    }
}
pub type RepositoryResult<T> = Result<T, RepositoryError>;
