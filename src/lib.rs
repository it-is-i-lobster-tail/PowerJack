#[cfg(not(target_arch = "wasm32"))]
pub mod db;
pub mod domain;
#[cfg(not(target_arch = "wasm32"))]
pub mod repository;
pub mod ui;
