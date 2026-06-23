# PowerJack iOS Development Standards

These standards apply to Capacitor, iOS device testing, native plugin behavior, mobile text inputs, and logs from physical iPhones.

PowerJack is local-first. Native iOS work must protect local user data, preserve fast workout entry, and avoid chasing harmless Apple framework noise unless it is tied to visible app behavior.

## Device Log Triage

Treat iPhone console output as evidence, not proof of an app bug.

- First check whether the warning names PowerJack code, Capacitor code, WebKit/UIKit internals, or a system text-input service.
- Treat a warning as actionable when it correlates with a user-visible issue, data loss, crash, failed persistence, broken keyboard focus, or repeated app-owned error path.
- Treat Apple framework keyboard and layout messages as log-only until a visible defect is reproduced.
- When recording device warnings, include the route, action, device model, iOS version, build configuration, and whether the issue is visible or log-only.

Known warning patterns:

- `Unable to simultaneously satisfy constraints` involving `_UIButtonBarButton`, `_UIModernBarButton`, or UIKit button wrappers is usually native UIKit layout recovery. Investigate only when native toolbar, navigation, or accessory UI is visibly broken.
- `RTIInputSystemClient ... Can only set suggestions for an active session` is usually iOS text suggestion state changing after focus moves. Investigate only when text entry, focus, or keyboard suggestions visibly fail.
- `The variant selector cell index number could not be found.` is usually iOS keyboard variant/autocorrection UI noise. Investigate only when typing glitches, focus flickers, or suggestions visibly break.
- `Attempted to update accumulator ... after completion has already been called` is usually iOS text-input service noise. Investigate only when it correlates with dropped characters or input instability.
- `TO JS`, `To Native`, or `CapacitorSQLite query` logs can include app data. Treat these as production-sensitive even when they are expected in debug builds.

## Production Logging

Release and TestFlight builds must not emit user data through native bridge or database logs.

- Do not log SQL rows, SQLite payloads, template names, workout names, set entries, body weight values, or other local user data in production-like builds.
- Debug builds may keep verbose Capacitor bridge logs when needed for development.
- Prefer supported Capacitor or plugin logging controls for the installed version. If the native iOS project needs custom behavior, gate verbose logs by Xcode build configuration.
- Before handoff for Capacitor, platform, or database-adapter changes, state whether a production-like iPhone build was checked for data-bearing logs.

## Text Inputs On iOS

Every mobile text input should declare intent clearly so WKWebView and iOS keyboard services behave predictably.

- Use semantic attributes such as `type`, `inputMode`, `autoComplete`, `autoCorrect`, `spellCheck`, `autoCapitalize`, and `enterKeyHint`.
- Disable autocomplete, autocorrect, and spellcheck for app-local labels, search fields, structured workout values, and other text where iOS suggestions are not useful.
- Keep autocapitalization useful for human-readable names when it does not change validation semantics.
- Do not add `maxLength` when the workflow intentionally allows over-limit entry to show validation feedback.
- Verify keyboard-affecting changes on a physical iPhone when practical, especially for focused routes and compact setup or workout screens.

## Physical iPhone QA

Browser tests come first, but native iOS verification is required when work touches Capacitor config, platform adapters, database plugins, mobile text inputs, or generated iOS project files.

Record:

- Device model and iOS version.
- Build configuration, such as Debug, Release, or TestFlight.
- Route and interaction tested.
- Whether the keyboard covers required controls, drops characters, flickers focus, or changes navigation behavior.
- Whether device logs contain app-owned errors or data-bearing native bridge output.

If the `ios/` project or native dependencies are not present in the current worktree, note that native logging implementation and production-like device verification are still pending.
