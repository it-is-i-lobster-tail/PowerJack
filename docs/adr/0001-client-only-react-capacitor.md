# ADR 0001: Client-Only React + Capacitor

## Decision

PowerJack is a client-only React, TypeScript, Vite, and Capacitor app. Vite builds static assets, and Capacitor packages those assets for native app targets.

## Consequences

- There is no runtime server, SSR, hydration layer, auth requirement, or HTTP API in the initial rebuild.
- SQLite is hidden behind repository interfaces so browser and native persistence can change without leaking into UI code.
- Browser testing is the first verification path; iOS simulator testing comes after the core flows are stable.
