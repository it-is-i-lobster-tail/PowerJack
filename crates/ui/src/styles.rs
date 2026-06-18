pub const APP_CSS: &str = r#"
:root {
  color-scheme: dark;
  --color-bg: #0F1214;
  --color-surface: #1F2124;
  --color-surface-raised: #2A2E34;
  --color-text-primary: #F4F6F8;
  --color-text-muted: #A7ADB7;
  --color-border: #39404A;
  --color-accent: #22C55E;
  --color-accent-muted: rgba(34, 197, 94, 0.36);
  --color-error: #EF4444;
  --radius-structure: 6px;
  --radius-button: 12px;
  --space-2: 8px;
  --space-3: 12px;
  --space-4: 16px;
  --space-5: 20px;
  --space-6: 24px;
  --motion-fast: 100ms;

  font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  background: #0F1214;
  color: #F4F6F8;
}

* {
  box-sizing: border-box;
}

html,
body,
#main {
  min-width: 320px;
  min-height: 100vh;
  margin: 0;
  font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  background: #0F1214;
  color: #F4F6F8;
}

body,
button {
  font: inherit;
}

button {
  border: 0;
}

.app-root {
  min-height: 100vh;
  background: #0F1214;
  color: #F4F6F8;
}

.setup-root {
  display: flex;
  justify-content: center;
  padding: 32px 16px;
}

.setup-screen {
  width: min(100%, 960px);
  min-height: calc(100vh - 64px);
  display: flex;
  flex-direction: column;
  justify-content: flex-start;
}

.setup-screen-centered {
  justify-content: center;
}

.setup-panel,
.panel {
  width: 100%;
  border: 1px solid #39404A;
  border-radius: 6px;
  background: #1F2124;
  color: #F4F6F8;
  padding: clamp(24px, 4vw, 44px);
}

.select-template-panel,
.program-length-panel,
.complete-panel {
  max-width: 720px;
  margin: 0 auto;
}

.screen-title,
.step-title {
  margin: 0;
  color: #F4F6F8;
  font-size: clamp(2rem, 5vw, 3.25rem);
  font-weight: 800;
  line-height: 1.05;
  letter-spacing: 0;
}

.step-title {
  font-size: clamp(1.7rem, 4vw, 2.6rem);
}

.screen-subtitle,
.select-template p,
.lede,
.hint {
  margin: 14px 0 0;
  color: #A7ADB7;
  font-size: clamp(1rem, 2.4vw, 1.25rem);
  line-height: 1.35;
  letter-spacing: 0;
}

.eyebrow {
  margin: 0 0 12px;
  color: #22C55E;
  font-size: 0.95rem;
  font-weight: 800;
  letter-spacing: 0.06em;
  text-transform: uppercase;
}

.section-title {
  margin: 32px 0 16px;
  color: #F4F6F8;
  font-size: clamp(1.25rem, 3vw, 2rem);
  line-height: 1.15;
  letter-spacing: 0;
}

.template-list {
  display: grid;
  gap: 12px;
  margin-top: 28px;
}

.template-option,
.option-button,
.week-option {
  width: 100%;
  min-height: 58px;
  border: 1px solid #39404A;
  border-radius: 6px;
  color: #F4F6F8;
  background: #101416;
  cursor: pointer;
  transition:
    border-color 100ms ease,
    background 100ms ease,
    transform 100ms ease;
}

.muscle-choice {
  display: block;
}

.muscle-choice-input {
  position: absolute;
  width: 1px;
  height: 1px;
  opacity: 0;
  pointer-events: none;
}

.muscle-choice-body .check {
  opacity: 0;
}

.muscle-choice-input:checked + .muscle-choice-body {
  border-color: #22C55E;
  background: #2A2E34;
}

.muscle-choice-input:checked + .muscle-choice-body .check {
  opacity: 1;
}

.muscle-choice-input:disabled + .muscle-choice-body {
  cursor: not-allowed;
  color: rgba(244, 246, 248, 0.42);
  border-color: #39404A;
  background: transparent;
}

.template-option {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  align-items: center;
  gap: 16px;
  padding: 16px 18px;
  text-align: left;
}

.template-option:hover,
.option-button:hover,
.week-option:hover {
  border-color: #22C55E;
}

.template-option:active,
.option-button:active,
.week-option:active,
.nav-button:active,
.create-template-action:active {
  transform: scale(0.99);
}

.template-option.selected,
.option-button.selected {
  border-color: #22C55E;
  background: #2A2E34;
}

.template-option-name {
  min-width: 0;
  overflow-wrap: anywhere;
  color: #F4F6F8;
  font-size: 1.08rem;
  font-weight: 750;
}

.template-option-meta {
  color: #A7ADB7;
  font-size: 0.95rem;
  font-weight: 600;
}

.empty-state {
  min-height: 68px;
  display: flex;
  align-items: center;
  border: 1px solid #39404A;
  border-radius: 6px;
  padding: 0 18px;
  color: #A7ADB7;
  background: #101416;
}

.error-state,
.error-text {
  color: #EF4444;
}

.create-template-action {
  width: 100%;
  min-height: 58px;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 12px;
  margin-top: 16px;
  border: 1px solid #22C55E;
  border-radius: 12px;
  color: #22C55E;
  background: transparent;
  cursor: pointer;
  font-size: 1.05rem;
  font-weight: 800;
  text-decoration: none;
}

.button-icon {
  font-size: 1.6rem;
  line-height: 1;
}

.button-arrow {
  margin-left: 10px;
}

.panel-nav,
.bottom-nav {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  margin-top: 32px;
}

.nav-button,
.primary-action {
  min-width: 136px;
  min-height: 56px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border: 1px solid #22C55E;
  border-radius: 12px;
  padding: 0 24px;
  color: #22C55E;
  background: transparent;
  cursor: pointer;
  font-size: 1.05rem;
  font-weight: 800;
  letter-spacing: 0;
  text-decoration: none;
}

.secondary-action {
  border-color: #39404A;
  color: #F4F6F8;
  background: transparent;
}

.nav-button:disabled,
.nav-button.disabled,
.primary-action:disabled,
.option-button:disabled,
.option-button.disabled {
  cursor: not-allowed;
  border-color: rgba(34, 197, 94, 0.36);
  color: rgba(34, 197, 94, 0.36);
  background: transparent;
  opacity: 1;
  transform: none;
}

.secondary-action:disabled {
  border-color: #39404A;
  color: rgba(244, 246, 248, 0.42);
}

.week-grid {
  display: grid;
  grid-template-columns: repeat(5, minmax(0, 1fr));
  gap: 14px;
}

.week-option {
  min-height: 76px;
  font-size: clamp(1.5rem, 4vw, 2.1rem);
  font-weight: 800;
}

.week-option.selected {
  border-color: #22C55E;
  color: #07120B;
  background: #22C55E;
}

.option-grid {
  display: grid;
  gap: 10px;
  margin-top: 18px;
}

.option-button {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
  padding: 0 14px;
  text-align: left;
}

.check {
  color: #22C55E;
  font-weight: 800;
}

.day-group {
  margin-top: 16px;
}

.day-group h3 {
  margin: 0 0 10px;
  color: #F4F6F8;
  font-size: 1rem;
  font-weight: 750;
}

.summary-list {
  display: grid;
  gap: 12px;
  margin-top: 18px;
}

.summary-row {
  display: flex;
  justify-content: space-between;
  gap: 16px;
  border-bottom: 1px solid #39404A;
  padding-bottom: 12px;
}

.summary-row span:first-child {
  color: #A7ADB7;
}

.header,
.brand,
.select-template,
.flow-main {
  color: #F4F6F8;
}

.header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 12px 0 18px;
}

.brand {
  margin: 0;
  font-size: 1.35rem;
  font-weight: 800;
  line-height: 1.1;
  letter-spacing: 0;
}

.screen {
  width: min(100%, 760px);
  min-height: calc(100vh - 40px);
  margin: 0 auto;
  display: flex;
  flex-direction: column;
  padding: 20px;
}

.flow-main {
  flex: 1;
  display: flex;
  flex-direction: column;
}

.step-meta {
  margin-bottom: 14px;
  color: #A7ADB7;
  font-size: 0.85rem;
  font-weight: 650;
}

@media (max-width: 700px) {
  .setup-root {
    padding: 16px;
  }

  .setup-screen {
    min-height: calc(100vh - 32px);
  }

  .setup-screen-centered {
    justify-content: flex-start;
    padding-top: 8vh;
  }

  .setup-panel,
  .panel {
    padding: 24px 18px;
  }

  .template-option {
    grid-template-columns: 1fr;
    gap: 6px;
  }

  .week-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  .panel-nav,
  .bottom-nav {
    margin-top: 24px;
  }

  .nav-button {
    min-width: 0;
    flex: 1;
  }
}
"#;
