import type { AppState } from "../app-state/AppState";
import type { TemplateAggregate } from "../templates/Template";
import type { ProgramOverviewSnapshot } from "./ProgramOverview";

export interface ProgramRepository {
  loadOverview(programId: number): Promise<ProgramOverviewSnapshot | null>;
  startFromTemplate(input: {
    template: TemplateAggregate;
    programLengthWeeks: number;
    replaceActiveProgram?: boolean;
  }): Promise<AppState>;
}
