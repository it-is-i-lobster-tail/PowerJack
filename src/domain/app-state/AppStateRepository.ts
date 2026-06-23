import type { AppState, RestTimer } from "./AppState";

export interface AppStateRepository {
  load(): Promise<AppState | null>;
  saveRestTimer(timer: RestTimer): Promise<AppState | null>;
  resetForAgent(): Promise<void>;
}
