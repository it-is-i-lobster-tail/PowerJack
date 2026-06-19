import type { AppStateRepository } from "../../domain/app-state/AppStateRepository";

export async function loadStartupState(appStateRepository: AppStateRepository) {
  return appStateRepository.load();
}
