import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { createAppServices } from "./createAppServices";
import { PersistenceUnavailableScreen } from "./PersistenceUnavailableScreen";
import { AppProviders } from "./providers";
import { createAppRouter } from "./router";

export async function bootstrap(): Promise<void> {
  const rootElement = document.getElementById("root");

  if (!rootElement) {
    throw new Error("Missing #root element");
  }

  const root = createRoot(rootElement);
  let services: Awaited<ReturnType<typeof createAppServices>>;

  try {
    services = await createAppServices();
  } catch (error) {
    console.error("PowerJack local storage is unavailable", error);
    root.render(
      <StrictMode>
        <PersistenceUnavailableScreen />
      </StrictMode>,
    );
    return;
  }

  window.__POWERJACK_AGENT__ = {
    reset: () => services.resetForAgent(),
    servicesMode: () => services.mode,
  };

  root.render(
    <StrictMode>
      <AppProviders services={services}>
        <App router={createAppRouter()} />
      </AppProviders>
    </StrictMode>,
  );
}
