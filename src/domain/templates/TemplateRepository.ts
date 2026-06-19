import type { EntityId } from "../ids";
import type {
  CompletedTemplateDraft,
  Template,
  TemplateAggregate,
  TemplateSummary,
} from "./Template";

export interface TemplateRepository {
  list(): Promise<TemplateSummary[]>;
  findById(id: EntityId): Promise<Template | null>;
  loadAggregate(id: EntityId): Promise<TemplateAggregate | null>;
  save(draft: CompletedTemplateDraft): Promise<TemplateSummary>;
  update(id: EntityId, draft: CompletedTemplateDraft): Promise<TemplateSummary>;
  softDelete(id: EntityId): Promise<void>;
  isUsedByActiveProgram(id: EntityId): Promise<boolean>;
}
