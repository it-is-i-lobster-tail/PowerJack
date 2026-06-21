import type { AppStateRepository } from "../../domain/app-state/AppStateRepository";
import {
  buildProgramListItems,
  type ProgramListFilter,
  type ProgramListItem,
} from "../../domain/programs/ProgramList";
import type { ProgramRepository } from "../../domain/programs/ProgramRepository";

export interface ProgramListView {
  programs: ProgramListItem[];
}

export async function loadProgramList(
  filter: ProgramListFilter,
  repositories: {
    appState: AppStateRepository;
    programs: ProgramRepository;
  },
): Promise<ProgramListView> {
  const [appState, summaries] = await Promise.all([
    repositories.appState.load(),
    repositories.programs.listSummaries(),
  ]);

  return {
    programs: buildProgramListItems({
      summaries,
      activeProgramId: appState?.activeProgramId ?? null,
      filter,
    }),
  };
}
