# ADR 0003: PowerJack UI Design Standards

## Decision

PowerJack treats `docs/ui-design-standards.md` as the canonical design standard for UI, CSS, motion, copy, and visual QA. Agents must consult it before UI-affecting changes and run `npm run ux:check` before committing those changes.

The UX check is a dependency-free repository script, not a Husky hook or tracked Git hook. Git hooks are local by default unless the repository configures a shared hooks path, so the durable shared enforcement point is the repo script plus the `AGENTS.md` agent contract.

## Consequences

- Future UI work has one repo-owned standard for Steel Focus color, density, component shape, motion, copy tone, accessibility, reference-image comparison, and QA evidence.
- UI handoffs must include whether the standards were checked, which visual QA was run, and any intentional deviation.
- `npm run ux:check` becomes the standard agent pre-commit reminder for UI-affecting changes.
- The check is advisory and human-reviewed; it does not replace browser testing, mobile viewport QA, screenshots, or E2E coverage when those are required.
