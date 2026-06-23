import type { PropsWithChildren } from "react";
import type { AppServices } from "./AppServices";
import { RestTimerProvider } from "./RestTimerProvider";
import { ServicesContext } from "./servicesContext";

interface AppProvidersProps extends PropsWithChildren {
  services: AppServices;
}

export function AppProviders({ children, services }: AppProvidersProps) {
  return (
    <ServicesContext.Provider value={services}>
      <RestTimerProvider>{children}</RestTimerProvider>
    </ServicesContext.Provider>
  );
}
