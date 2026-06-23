# PowerJack Typography Standards

These standards define every app text size. Use the CSS variables in `src/shared/styles/tokens.css`; do not hard-code pixel, rem, em, or viewport-scaled font sizes in app CSS.

## Font Scale

| Role | Token | Size | Use |
| --- | --- | --- | --- |
| `header-1` | `var(--font-size-header-1)` | `34px` | Primary screen titles and route-level page headings. |
| `header-2` | `var(--font-size-header-2)` | `22px` | Section headings, modal titles, card titles, and important metric values. |
| `sub-header` | `var(--font-size-sub-header)` | `16px` | Body text, button labels, primary row text, form values, and prominent status text. |
| `info` | `var(--font-size-info)` | `13px` | Helper text, compact labels, metadata, counters, badges, and secondary controls. |

## Rules

- Browser default text sizing is not an approved typography role. App defaults must set unstyled text to `var(--font-size-sub-header)` through the global reset.
- Semantic text elements such as `h1`, `h2`, `small`, and `legend` must inherit from the tokenized default or receive an explicit typography token in component CSS.
- Use font weight, color, spacing, and layout to create hierarchy within these four sizes.
- Do not use `clamp()`, viewport units, or route-specific pixel values for text sizing.
- Keep headings visually consistent across top-level routes; `Programs`, `Templates`, and `Data Visualization` pages all use `header-1`.
- Use tabular numbers for reps, weight, dates, and workout metrics when numeric alignment matters.
- Any non-text technical exception must include an inline `Typography exception` CSS comment explaining why a token cannot be used. The exception is not a typography role.
