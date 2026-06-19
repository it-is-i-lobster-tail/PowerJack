import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { createAppServices } from "./createAppServices";
import { AppProviders } from "./providers";
import { createAppRouter } from "./router";

export async function bootstrap(): Promise<void> {
  const rootElement = document.getElementById("root");

  if (!rootElement) {
    throw new Error("Missing #root element");
  }

  const services = await createAppServices();

  window.__POWERJACK_AGENT__ = {
    reset: () => services.resetForAgent(),
    servicesMode: () => services.mode,
  };

  createRoot(rootElement).render(
    <StrictMode>
      <AppProviders services={services}>
        <App router={createAppRouter()} />
      </AppProviders>
    </StrictMode>,
  );
}
