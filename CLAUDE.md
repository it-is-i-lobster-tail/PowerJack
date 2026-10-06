# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Working rules (from AGENTS.md — these override defaults)

- **Explain only by default.** Do not write, edit, create, delete, move, or patch any file unless the current user message explicitly authorizes that file change.
- Requests for guidance, discussion, examples, or phrases like "let's rework this" are **not** permission to edit. Answer with explanation and illustrative code instead.
- **Required simulator check.** Before handing off any UI, layout, navigation or text-input change, run the bottom bar and number pad check in AGENTS.md on the simulator (light and dark) and run `KeyboardLayoutTests`.
- `.agents/skills/coach/SKILL.md` defines a "coach" mode (teach, don't implement; prefer official Apple docs) for learning/understanding questions.

## Project

PowerJack is a native iOS strength-training app: SwiftUI + SwiftData, Swift Testing, no third-party dependencies.

- Xcode project: `PowerJack/PowerJack.xcodeproj`, single scheme `PowerJack`, targets `PowerJack` and `PowerJackTests` (bundle IDs `com.stanleycloud.*`).
- iPhone only, deployment target iOS 26.2.
- Build settings: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency, so code is main-actor isolated unless marked otherwise. Tests are `@MainActor` too.
- The target uses file-system-synchronized groups, so new `.swift` files under `PowerJack/PowerJack/` are picked up automatically. There's no need to edit `project.pbxproj` to add files.

## Commands

The XcodeBuildMCP and `xcode` (Xcode `mcpbridge`) MCP servers are configured. Prefer them: call `session_show_defaults` first, then `build_sim` / `build_run_sim` / `test_sim` / `screenshot`. The equivalent CLI commands:

```bash
# Build
xcodebuild -project PowerJack/PowerJack.xcodeproj -scheme PowerJack \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build

# All tests
xcodebuild -project PowerJack/PowerJack.xcodeproj -scheme PowerJack \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test

# One suite / one Swift Testing test (note the trailing "()" on test functions)
  ... test -only-testing:PowerJackTests/CreationFlowTests
  ... test -only-testing:'PowerJackTests/CreationFlowTests/programLengthClamping()'
```

No linter or formatter is configured.

## Architecture

### Layout
`PowerJack/PowerJack/` is split into `App/` (entry point + root view), `Features/<Feature>/{Models,Views,Views/Components,Views/Components/Drafts}` for Exercises, Templates, Programs and Workouts, and `Shared/` (Models, Persistence, Extensions, Logging, UI, PreviewSupport).

### Domain model graph
- **Template side (editable blueprint):** `TemplateProgram` → `TemplateWorkout` → `TemplateExercise` → `Exercise`.
- **Program side (instance the user runs):** `Program` (holds its `TemplateProgram`) → `ProgramWeek` → `Workout` → `WorkoutExercise` → `WorkoutSet`.
- `Program.init` builds `programLengthWeeks` weeks (clamped 1…12). Only week 1 is populated from the template, with 2 sets per exercise. Later weeks start empty.
- Every model type must be registered in `PowerJackSchema.schema` (`Shared/Persistence/PowerJackSchema.swift`). CloudKit is off.

### Model conventions (follow these when touching `@Model` types)
- Stored properties use a `…Value` suffix (`statusValue`, `workoutsValue`, `orderValue`). Views read them through computed accessors in extensions (`status`, `workouts`, `order`).
- To-many relationships are stored unordered. Each child has an `order` Int, and the public accessor returns the children **sorted by `order`**. `Array.moveAndReorder` (`Shared/Extensions/Array+OrderedModel.swift`) rewrites the `order` values after a drag-reorder.
- Lifecycle uses `Status` (`planned/active/complete/skipped/stopped`) plus a `locked` flag. Mutations go through guarded methods (`start()`, `complete()`, `stop()`, `skip()`, `add…()`) that refuse invalid transitions and log through `Logger.<category>` (`Shared/Logging/Logger+PowerJack.swift`) instead of throwing. `…AndCascade()` variants push a transition down the tree.
- `Workout` is inverted: it starts `locked = true` while planned, and `start()` unlocks it. Structural edits like `addWorkoutExercise` are only allowed while it is still locked (planned).
- `StatusProviding` + `Collection.active` (`Shared/Extensions/Collection+Active.swift`) find the single active element. If sync ever produces more than one, it logs a warning and returns the first.

### Draft pattern for create/edit forms
Forms never bind to `@Model` objects directly. Each editable model has a value-type `…Draft` struct in `Views/Components/Drafts/`:
- The draft is initialized from an optional existing model.
- It owns validation limits as static constants and exposes `canSave`.
- `make…()` creates a new model graph. `apply(to:)` writes changes back to an existing one.
- Views (e.g. `TemplateProgramNew`) hold the draft in `@State`, pass a binding to a shared `…Form`, and save with `modelContext.insertAndSave(_:)` (`Shared/Persistence/ModelContext+Save.swift`). That helper deletes the inserted model if the save fails. Save errors are shown with `.saveErrorAlert`.
- `TemplateProgramDraft` always keeps 6 workout drafts and toggles `enabled` from `workoutsPerWeek`, so disabled days keep their contents.

### Exercise catalog
`ExerciseCatalog` (`Shared/Persistence/ExerciseCatalog.swift`) seeds the built-in exercises at app launch. The seed is idempotent and keyed by the permanent `catalogID`: never change an existing ID. Catalog exercises have `userCreated == false`, and `ExerciseDraft` refuses to edit them.

### Previews & seed data
- The app uses an in-memory store when `XCODE_RUNNING_FOR_PREVIEWS == "1"`.
- Previews use `PowerJackSeed` (`Shared/PreviewSupport/`): `makeInMemoryContainer()`, `exercises()`, `weekOneProgress()`, `emptyWorkout()`, which return the scenario structs `PowerJackProgramSeedScenario` / `PowerJackWorkoutSeedScenario`. Wrap navigation-dependent previews in `NavigationPreviewHost`.
- `PowerJackTests/PreviewRenderingTests.swift` (XCTest) renders the preview screens and checks the seed scenarios. Keep it passing when you change previews or seeds. The other test files use Swift Testing.

### UI
- The root is a paged `TabView` (Programs / Templates) with a custom `SlidingGlassPicker` bottom inset instead of a tab bar.
- Shared styling is in `Shared/UI` (Liquid Glass surfaces, `GlassFormScaffold`, `LayoutMetrics`, `VisualOpacity`). Reuse these rather than adding ad-hoc styling.

<!-- imported-from: codex:project:instructions -->
# Repository Instructions

- Explain only by default. Do not write, edit, create, delete, move, or patch any file unless the user gives explicit permission and explicitly instructs you to make that file change.
- When the user asks how code should be reworked, provide explanation and illustrative code only. Do not interpret discussion, examples, requests for guidance, or phrases like “let’s rework this” as permission to modify files.
- Before making any file change, verify that the current user message explicitly authorizes implementation or editing. If it does not, do not change files.
