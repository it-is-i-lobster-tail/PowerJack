import type { AppState } from "../app-state/AppState";
import type { TemplateAggregate } from "../templates/Template";

export interface ProgramRepository {
  startFromTemplate(input: {
    template: TemplateAggregate;
    programLengthWeeks: number;
    replaceActiveProgram?: boolean;
  }): Promise<AppState>;
}
