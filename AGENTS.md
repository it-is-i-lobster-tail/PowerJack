# PowerJack Agent Guide

## Project Direction

PowerJack is being rebuilt as a client-only `React + TypeScript + Vite + Capacitor` app. The first phase is local-first: no runtime server, no SSR, no auth, no sync, and no HTTP API. Browser testing comes first, then native iOS testing.

## Commands

- `npm run dev`: start Vite at `http://127.0.0.1:5173/` with `--host 0.0.0.0`.
- `npm run build`: type-check and create the static Vite bundle.
- `npm run check`: run TypeScript, ESLint, and unit tests.
- `npm run ux:check`: run the agent UX Design Standards Check before committing UI-affecting work.
- `npm run test`: run Vitest.
- `npm run test:e2e`: run Playwright smoke tests.
- `npm run test:e2e:headed`: run Playwright headed.
- `npm run cap:sync`: build and sync Capacitor.

## Architecture Rules

- UI components may not import from `src/infrastructure/`.
- Raw SQL may exist only under `src/infrastructure/database/`.
- Capacitor APIs may exist only under `src/infrastructure/platform/` or database adapter setup.
- Business rules must be pure functions in `src/domain/`.
- User workflows belong in `src/application/` use cases.
- Persistence is accessed through domain repository interfaces.
- Do not copy the entire database into a global React store.
- Feature UI belongs under `src/features/<feature>/`.
- Reusable primitives belong under `src/shared/ui/`.
- Shared design tokens belong under `src/shared/styles/`.
- New dependencies require an ADR in `docs/adr/`.

## Program And Template Flow

- Program creation starts at `/`, then routes through `/start/select-template`, `/start/program-length`, and a final `Start` action.
- A template is the reusable plan: template name, focus muscles, days per week, ordered workout days, and ordered exercise ids per day.
- A program is an instance of a selected template with a defined timeline such as program length in weeks.
- New template creation routes through `/templates/new/name`, `/templates/new/muscle-focus`, `/templates/new/days-per-week`, and `/templates/new/builder`.
- Template names must be 1-24 characters. Show the red `x/24` counter only when the user exceeds 24 characters.
- Muscle Group Focus must require at least one selected muscle, allow at most four, and use a visible `x/4` counter.
- Save Template must stay disabled until the name is valid, at least one focus muscle is selected, days per week is selected, and every day has at least one exercise.
- Select Template rows must show focused muscles as compact chips on the right side of the row when present.
- Do not seed demo templates. Seed only reference muscles, equipment, and exercises.
- After saving a template, return to Select Template with the saved template visible and selected.

## Database Rules

- Use immutable numbered migrations in `src/infrastructure/database/migrations/`.
- Do not edit a released migration; add a new migration.
- Keep database column names snake_case and map them to camelCase domain types.
- Normalize the original drawSQL intent; do not preserve export typos like `feeback`, `ative_lift_id`, `acutual_reps`, or `workout_tempalte_id`.
- Use `workout_sets`, not a table named `set`.
- Seed reference muscles, equipment, and exercises idempotently.
- Repository boundaries follow workflows, not one CRUD class per table.
- Web SQLite may not support explicit nested `BEGIN TRANSACTION` calls; keep aggregate repository saves behind `DatabaseClient.transaction` so platform behavior stays isolated in the adapter.

## iOS Development Rules

- Read `docs/ios-development-standards.md` before changing Capacitor config, platform adapters, database plugins, generated iOS project files, or mobile text inputs.
- Treat physical iPhone console output as evidence to triage, not proof of an app bug; distinguish app-owned failures from Apple, WebKit, UIKit, and iOS keyboard service noise.
- Release and TestFlight builds must not emit SQL rows, SQLite payloads, template names, workout data, or other local user data through Capacitor bridge or database logs.
- Mobile text inputs must declare intent with semantic attributes such as `type`, `inputMode`, `autoComplete`, `autoCorrect`, `spellCheck`, `autoCapitalize`, and `enterKeyHint` when applicable.
- For Capacitor config, database adapter, platform API, generated iOS project, or mobile keyboard changes, record iPhone QA notes with device model, iOS version, build configuration, route, interaction, and relevant log findings.
- If the `ios/` project or native dependencies are unavailable in the worktree, note which native logging or physical-device checks remain pending.

## Design Rules

- Read `docs/ui-design-standards.md` before changing React views, CSS, design tokens, layout, copy, motion, routes, screenshots, or reference images.
- Read `docs/typography-standards.md` and use the `powerjack-typography` skill before changing text sizes, heading hierarchy, or typography-related CSS.
- Use the Steel Focus palette from `src/shared/styles/tokens.css`.
- Use only the shared typography tokens from `src/shared/styles/tokens.css`: `--font-size-header-1`, `--font-size-header-2`, `--font-size-sub-header`, and `--font-size-info`.
- Build mobile-first, then browser-wide.
- Match the supplied references in `docs/reference_images/`; `/` must match `Start_new_program_example.png`.
- Keep workout logging compact: shared labels, horizontal set rows, and no large card per set.
- Use green for selected, active, success, and complete states.
- Use orange for caution/destructive confirmation and red only for validation/destructive failure.
- Never rely on color alone for state.
- Keep copy short, calm, and direct.
- Avoid social fitness patterns, dashboards during workout execution, confetti, XP, badges, and loud gamification.

## Agent And Test Readiness

- Add stable `data-agent-id` selectors to navigable controls and important workflow surfaces.
- Keep controls accessible by role and name.
- Preserve `window.__POWERJACK_AGENT__.reset()` for deterministic browser tests.
- Every UI story needs browser E2E coverage and screenshot/visual QA when layout changes.
- Mobile-affecting stories need mobile viewport Playwright coverage.
- Before committing UI-affecting work, run `npm run ux:check` and record the UX Design Standards Check result in the handoff.
- UI handoffs must note which standards/reference images were checked, what browser or mobile visual QA was run, and any intentional design-standard deviation.
- iOS-affecting handoffs must note whether production-like device logs were checked for data-bearing Capacitor or SQLite bridge output.
- Before handoff, run `npm run check`; run `npm run test:e2e` when routes or UI flows change.
