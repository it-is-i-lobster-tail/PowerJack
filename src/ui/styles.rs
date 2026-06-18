pub const APP_CSS: &str = r#"
:root {
  color-scheme: dark;
  font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  background: #070911;
  color: #f5f7fb;
}

* {
  box-sizing: border-box;
}

body {
  margin: 0;
  min-width: 320px;
  min-height: 100vh;
  background:
    linear-gradient(180deg, rgba(46, 79, 255, 0.12), transparent 280px),
    #070911;
}

button {
  font: inherit;
}

.app-root {
  min-height: 100vh;
  padding: 20px;
}

.screen {
  width: min(100%, 520px);
  min-height: calc(100vh - 40px);
  margin: 0 auto;
  display: flex;
  flex-direction: column;
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
  line-height: 1.1;
  letter-spacing: 0;
}

.profile-button {
  width: 40px;
  height: 40px;
  border: 1px solid #2c3449;
  border-radius: 6px;
  color: #dbe4ff;
  background: #121725;
}

.panel {
  border: 1px solid #222a3e;
  border-radius: 6px;
  background: rgba(16, 21, 34, 0.96);
  padding: 18px;
}

.select-template {
  flex: 1;
  display: grid;
  align-content: center;
  gap: 16px;
}

.select-template p,
.lede,
.hint {
  margin: 0;
  color: #aab4cc;
  line-height: 1.5;
}

.primary-action,
.nav-button {
  border: 1px solid #5f6cff;
  border-radius: 6px;
  min-height: 46px;
  padding: 0 16px;
  color: #ffffff;
  background: linear-gradient(135deg, #6d5dfc, #2388ff);
  cursor: pointer;
}

.secondary-action {
  border-color: #303a55;
  color: #cbd6f5;
  background: #121725;
}

.nav-button:disabled {
  cursor: not-allowed;
  opacity: 0.42;
}

.flow-main {
  flex: 1;
  display: flex;
  flex-direction: column;
  padding-bottom: 88px;
}

.step-meta {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 14px;
  color: #8d99b8;
  font-size: 0.82rem;
}

.step-title {
  margin: 0 0 8px;
  font-size: 1.6rem;
  line-height: 1.1;
  letter-spacing: 0;
}

.option-grid {
  display: grid;
  gap: 10px;
  margin-top: 18px;
}

.option-button {
  width: 100%;
  min-height: 52px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
  border: 1px solid #283149;
  border-radius: 6px;
  padding: 0 14px;
  color: #edf2ff;
  background: #111827;
  cursor: pointer;
  text-align: left;
}

.option-button.selected {
  border-color: #6d5dfc;
  background: linear-gradient(135deg, rgba(109, 93, 252, 0.26), rgba(35, 136, 255, 0.18));
}

.option-button:disabled,
.option-button.disabled {
  cursor: not-allowed;
  opacity: 0.42;
}

.check {
  color: #86a5ff;
  font-weight: 700;
}

.day-group {
  margin-top: 16px;
}

.day-group h3 {
  margin: 0 0 10px;
  font-size: 0.95rem;
  color: #dbe4ff;
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
  border-bottom: 1px solid #222a3e;
  padding-bottom: 12px;
}

.summary-row span:first-child {
  color: #8d99b8;
}

.bottom-nav {
  position: sticky;
  bottom: 0;
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
  margin-top: auto;
  padding: 14px 0 max(14px, env(safe-area-inset-bottom));
  background: linear-gradient(180deg, rgba(7, 9, 17, 0), #070911 24%);
}

@media (max-width: 390px) {
  .app-root {
    padding: 14px;
  }

  .screen {
    min-height: calc(100vh - 28px);
  }

  .panel {
    padding: 14px;
  }

  .step-title {
    font-size: 1.35rem;
  }
}
"#;
