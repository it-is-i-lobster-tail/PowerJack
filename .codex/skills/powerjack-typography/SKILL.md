---
name: powerjack-typography
description: Use when changing PowerJack typography, text sizing, heading hierarchy, CSS font-size declarations, UI design standards, or visual QA for text-heavy React screens. Ensures app text follows the four shared typography tokens in docs/typography-standards.md and src/shared/styles/tokens.css.
---

# PowerJack Typography

## Overview

Keep PowerJack text sizing consistent across React screens, shared UI, and docs. Apply the four-role typography scale and verify no unreviewed raw font-size declarations remain.

## Workflow

1. Read `docs/typography-standards.md`, `docs/ui-design-standards.md`, and `src/shared/styles/tokens.css` before changing typography.
2. Use only these text-size tokens in app CSS:
   - `var(--font-size-header-1)` for route-level screen titles.
   - `var(--font-size-header-2)` for section headings, modal titles, card titles, and important metric values.
   - `var(--font-size-sub-header)` for body text, button labels, primary row text, form values, and prominent status text.
   - `var(--font-size-info)` for helper text, compact labels, metadata, counters, badges, and secondary controls.
3. Replace raw pixel, rem, em, viewport, and `clamp()` font-size values with the closest semantic token.
4. Use weight, color, spacing, and layout for emphasis instead of adding new text sizes.
5. Treat browser default sizing as drift. Unstyled visible text must inherit from the tokenized app default, and semantic elements such as `h1`, `h2`, `small`, and `legend` must inherit from that default or receive an explicit token in CSS.
6. Keep top-level route headers visually consistent. `Programs`, `Templates`, and `Data Visualization` must all use `header-1`.

## Exceptions

Allow a non-token `font-size` only for a non-text technical behavior, such as hiding duplicate non-visible text while an icon remains visible. Add an inline CSS comment containing `Typography exception` and explain why the token cannot be used.

## Verification

Run these before handoff for typography or UI-affecting work:

```bash
rg "font-size:" src --glob "*.css"
npm run ux:check
npm run check
```

Run `npm run test:e2e` when route-level screens, layout, or visual snapshots change. Record the standards checked, browser/mobile visual QA, and any intentional typography exception in the handoff.
