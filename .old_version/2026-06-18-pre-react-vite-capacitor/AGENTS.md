# Repository Guidelines

## Project Overview

PowerJack is a local-first workout planning and logging app built with Rust, Dioxus, and SQLite for a single user. Keep it low-friction: resume the active workout, log reps and weight, and progress without cloud sync, authentication, or multi-user concerns.

The model centers on muscles, exercises, templates, programs, workouts, lifts, sets, feedback, and singleton app state. Programs come from reusable templates; workouts contain ordered lifts; lifts contain ordered sets; app state tracks the active program, workout, and lift.

## Project Structure & Module Organization

- `src/lib.rs` exposes the public modules.
- `src/domain/mod.rs` defines domain structs, ID newtypes, and status parsing.
- `src/repository.rs` contains shared repository error/result types.
- `src/db/repositories/mod.rs` owns the SQLite schema, CRUD methods, row mapping helpers, and tests.
- `src/db/models/mod.rs` contains database row structs.
- `.reference_images/` contains example PNGs for the intended Dioxus UI look and flow. Review these before building or changing screens.

## Build, Test, and Development Commands

- `cargo check` validates the crate quickly.
- `cargo test` runs unit tests, including in-memory SQLite coverage.
- `cargo fmt` formats all Rust files with `rustfmt`.
- `cargo clippy --all-targets --all-features` runs lint checks across library and test targets.
Run `cargo fmt` and `cargo test` before opening pull requests.

## Coding Style & Naming Conventions

Use standard Rust formatting: 4-space indentation, `snake_case` for functions and fields, `PascalCase` for structs/enums/newtype IDs, and `SCREAMING_SNAKE_CASE` for constants. Keep domain IDs as explicit newtypes such as `ProgramId(pub i64)`. Preserve repository style: return `RepositoryResult<T>`, convert `rusqlite::Error` through `RepositoryError`, and keep SQL column ordering aligned with row mapping functions.

## Testing Guidelines

Tests use Rust's built-in test framework. Place narrow unit tests next to the module under test with `#[cfg(test)]`; repository tests live in `src/db/repositories/mod.rs` and use `Connection::open_in_memory()`. Name tests after behavior, for example `defaults_and_crud`. Cover schema constraints, default values, and app-state side effects.

## Commit & Pull Request Guidelines

The existing history favors short imperative commit subjects, for example `Implement SQLite persistence model` and `Add SQLite repository CRUD layer`. Keep commits focused and describe the observable change.

Pull requests should include a summary, linked issue or Linear ticket when applicable, test results such as `cargo test`, and notes for schema or persistence changes.

## Security & Configuration Tips

`rusqlite` uses the bundled SQLite feature, so contributors do not need a system SQLite install. Avoid logging sensitive workout or user-state data in future application layers. Keep generated databases, local build output, and temporary files out of version control.
