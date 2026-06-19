import { useContext } from "react";
import { ServicesContext } from "./servicesContext";
import type { AppServices } from "./AppServices";

export function useServices(): AppServices {
  const services = useContext(ServicesContext);

  if (!services) {
    throw new Error("useServices must be used inside AppProviders");
  }

  return services;
}
