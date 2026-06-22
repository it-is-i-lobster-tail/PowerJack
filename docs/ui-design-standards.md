# PowerJack UI Design Standards

These standards are the source of truth for PowerJack UI changes. Read this before changing React views, CSS, shared UI primitives, design tokens, motion, copy, routes, screenshots, or reference images.

## Product Feeling

PowerJack should feel calm, fast, solid, and local-first. The app is for focused lifting, not social fitness, health tracking, or gamified entertainment.

- Prioritize the active workout, active lift, and fast set logging.
- Communicate state clearly without loud decoration.
- Avoid dashboards during workout execution, social feeds, motivational slogans, confetti, XP, badges, and streak mechanics.
- Keep the emotional target simple: open the app, lift, log sets, and move on.

## Visual Language

Use the Steel Focus palette from `src/shared/styles/tokens.css`.

- Background: `#0F1214`
- Surface: `#1C1F22`
- Raised surface: `#2A2E34`
- Primary text: `#E6E9EC`
- Muted text: `#9CA3AF`
- Border: `#374151`
- Accent green: `#22C55E`
- Warning orange: `#F97316`
- Info blue: `#3B82F6`
- Error red: `#EF4444`

Use green for selected, active, success, and complete states. Use orange for caution or destructive confirmation. Use red only for validation errors and destructive failure. Use blue only for information. Never rely on color alone; pair color with border, icon, text, disabled affordance, or layout structure.

## Layout And Density

Build mobile-first, then widen for browser layouts.

- Use 12-16px page gutters on mobile and an 8px spacing rhythm.
- Prefer dark surfaces, 1px borders, compact dividers, and restrained fills.
- Do not nest cards inside cards unless the hierarchy truly requires it.
- Do not use large decorative shadows except for modals and elevated overlays.
- Keep primary touch targets at least 44px tall where practical.
- Keep the next step or primary action easy to find without making it visually loud.

Workout logging must stay compact:

- Use shared row labels for set tables.
- Keep set number, reps, weight, and log status on one horizontal plane.
- Do not create a large card for every set.
- Do not stack reps and weight vertically in normal set rows.
- Keep active workout context visible near the top.

## Components And Typography

Use harder edges for structure and softer edges for actions.

- Cards, sections, containers: 0-6px radius.
- Inputs: 6-8px radius.
- Buttons: 10-12px radius.
- Modals: 8-10px radius.

Use system fonts. Prefer tabular numbers for reps, weight, and workout metrics.

- Screen title: 22-24px, 700.
- Week/day heading: 18-20px, 700.
- Exercise name: 16-17px, 650-700.
- Set row values: 15-16px, 500-600.
- Labels: 12-13px, 500.
- Helper text: 12px, 400-500.

Keep labels short. Avoid decorative fonts, broad all-caps text, and marketing-style copy.

## State, Motion, And Copy

State should be obvious without being loud.

- Selected options use accent border plus subtle filled state.
- Disabled controls look unavailable and remain readable.
- Completed sets use a green check plus a slight row highlight or outline.
- Locked workouts are readable but clearly not editable.
- Errors use red only where the user must correct or acknowledge a failure.

Use motion only to communicate cause and effect.

- Button press feedback: 80-120ms.
- Input focus feedback: 100-150ms.
- Row complete highlight: 150-200ms.
- Expansion, collapse, modal fade, and modal scale: 150-220ms.
- Interaction feedback must not delay logging or navigation.

Copy should be short, calm, and direct: `Next`, `Back`, `Finish Workout`, `Add Exercise`, `Search Exercise`, `No`, `Yes`. Avoid cute copy, shame language, and over-explaining obvious UI.

## Accessibility And Agent Readiness

- Keep controls accessible by role and name.
- Add stable `data-agent-id` selectors to navigable controls and important workflow surfaces.
- Preserve `window.__POWERJACK_AGENT__.reset()` for deterministic browser tests.
- Use semantic controls first. If a custom role is needed, make selected, disabled, and focused states readable to assistive technology.
- Do not use color as the only state indicator.

## Visual QA

Use `docs/reference_images/` as the visual baseline before changing related screens. Important references include:

- `Start_new_program_example.png` for `/`.
- `Button_highlight_example.png` for pressed/selected feedback.
- `program_length_in_weeks_no_selection_next_button_disabled.png` and `program_length_in_weeks_selection_next_button_enabled.png` for setup selection states.
- `template_builder_base.png`, `template_builder_search_exersise.png`, and added-exercise references for builder density.
- `program_week_1_workout_1_no_logged_sets.png`, `program_week_1_workout_1_text_box_for_logging_selected.png`, `visual_of_a_workout_logged.png`, and `workout_finish_workout_when_all_sets_complete_button.png` for workout logging.
- `completed_workout_locked.png` and `ui_when_a_lift_in_a_workout_as_been_completed.png` for complete and locked states.

Before handoff for a UI-affecting change, record:

- Which standards and reference images were checked.
- Whether browser and mobile viewport QA were run.
- Screenshot, Playwright, or other visual evidence for layout changes.
- Any intentional deviation from these standards and why it was necessary.

## UX Design Standards Check

Run `npm run ux:check` before committing UI-affecting work. Treat it as the agent pre-commit checklist for React views, CSS, tokens, copy, routes, motion, screenshots, and reference images.

The script does not replace judgment. It points to this standard, lists likely UI-affecting changed files, and reminds the agent what evidence must be included before handoff.
