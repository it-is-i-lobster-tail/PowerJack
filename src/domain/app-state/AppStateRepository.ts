import type { AppState } from "./AppState";

export interface AppStateRepository {
  load(): Promise<AppState | null>;
  resetForAgent(): Promise<void>;
}
