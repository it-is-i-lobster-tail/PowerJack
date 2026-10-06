# Repository Instructions

- Explain only by default. Do not write, edit, create, delete, move, or patch any file unless the user gives explicit permission and explicitly instructs you to make that file change.
- When the user asks how code should be reworked, provide explanation and illustrative code only. Do not interpret discussion, examples, requests for guidance, or phrases like “let’s rework this” as permission to modify files.
- Before making any file change, verify that the current user message explicitly authorizes implementation or editing. If it does not, do not change files.

## Required simulator check: bottom bar and number pad

Every agent MUST run this check on the iOS Simulator before handing off any change that touches UI, layout, navigation, or text input. Do it in both light and dark mode, with the software keyboard showing (Simulator > I/O > Keyboard > uncheck "Connect Hardware Keyboard").

1. **Bottom bar is never covered.** On Program detail (Resume / Start), New Program (Start Program), New Template (Save) and a workout's exercise screen (the exercise strip), nothing sits under, touches or covers the gear and the Programs / Templates switcher.
2. **The number pad covers the bottom of the screen.** On a workout's exercise screen, tap a Weight or Reps field. The number pad slides over the bottom of the screen. The exercise strip, the gear and the switcher stay where they were and do not move up above the number pad.

Also run `PowerJackTests/KeyboardLayoutTests`. It guards the layout pieces behind these rules (`powerJackTabPage` and `keyboardSlidesOver()`), but only the simulator shows the real screens, so the check above is still required. Say in your hand-off that you ran both and what you saw.
