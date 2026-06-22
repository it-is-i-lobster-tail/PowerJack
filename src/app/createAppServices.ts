import { Capacitor } from "@capacitor/core";
import type { AppServices } from "./AppServices";
import { createDatabaseBackedServices } from "../infrastructure/database/createDatabaseBackedServices";
import { createInMemoryAppServices } from "../infrastructure/database/repositories/InMemoryRepositories";

export async function createAppServices(): Promise<AppServices> {
  try {
    return await createDatabaseBackedServices();
  } catch (error) {
    if (Capacitor.getPlatform() === "web") {
      console.warn("SQLite unavailable, using deterministic in-memory services.", error);
      return createInMemoryAppServices();
    }

    console.error("SQLite unavailable on native platform.", error);
    throw error;
  }
}
