/// <reference types="vite/client" />

declare module "*.sql?raw" {
  const sql: string;
  export default sql;
}

interface PowerJackAgentHarness {
  reset(): Promise<void>;
  servicesMode(): "sqlite" | "memory";
}

interface Window {
  __POWERJACK_AGENT__?: PowerJackAgentHarness;
}
