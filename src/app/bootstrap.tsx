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

  let services: Awaited<ReturnType<typeof createAppServices>>;

  try {
    services = await createAppServices();
    await services.cache.hydrateLaunch();
  } catch (error) {
    console.error("PowerJack local storage is unavailable", error);
    const root = createRoot(rootElement);

    root.render(
      <StrictMode>
        <PersistenceUnavailableScreen />
      </StrictMode>,
    );
    dismissLaunchSplashAfterPaint();
    return;
  }

  window.__POWERJACK_AGENT__ = {
    reset: () => services.resetForAgent(),
    servicesMode: () => services.mode,
  };

  const root = createRoot(rootElement);

  root.render(
    <StrictMode>
      <AppProviders services={services}>
        <App router={createAppRouter()} />
      </AppProviders>
    </StrictMode>,
  );
  dismissLaunchSplashAfterPaint();
}

function dismissLaunchSplashAfterPaint(): void {
  waitForNextPaint(() => {
    const launchSplash = document.getElementById("powerjack-launch");

    if (!launchSplash) {
      return;
    }

    const prefersReducedMotion =
      typeof window.matchMedia === "function" &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    if (prefersReducedMotion) {
      launchSplash.remove();
      return;
    }

    launchSplash.dataset.state = "hidden";
    window.setTimeout(() => launchSplash.remove(), 220);
  });
}

function waitForNextPaint(callback: () => void): void {
  if (typeof window.requestAnimationFrame !== "function") {
    window.setTimeout(callback, 0);
    return;
  }

  window.requestAnimationFrame(() => {
    window.requestAnimationFrame(callback);
  });
}
