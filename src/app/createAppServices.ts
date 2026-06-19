import type { AppServices } from "./AppServices";
import { createDatabaseBackedServices } from "../infrastructure/database/createDatabaseBackedServices";
import { createInMemoryAppServices } from "../infrastructure/database/repositories/InMemoryRepositories";

export async function createAppServices(): Promise<AppServices> {
  try {
    return await createDatabaseBackedServices();
  } catch (error) {
    console.warn("SQLite unavailable, using deterministic in-memory services.", error);
    return createInMemoryAppServices();
  }
}
