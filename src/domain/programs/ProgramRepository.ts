import type { AppState } from "../app-state/AppState";
import type { TemplateAggregate } from "../templates/Template";
import type { ProgramListSummary } from "./ProgramList";
import type { ProgramOverviewSnapshot } from "./ProgramOverview";

export interface ProgramRepository {
  listSummaries(): Promise<ProgramListSummary[]>;
  loadOverview(programId: number): Promise<ProgramOverviewSnapshot | null>;
  startFromTemplate(input: {
    template: TemplateAggregate;
    programLengthWeeks: number;
    replaceActiveProgram?: boolean;
  }): Promise<AppState>;
}
