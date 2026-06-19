import type { TemplateDraft } from "../../domain/templates/Template";
import type { TemplateRepository } from "../../domain/templates/TemplateRepository";
import { validateTemplateDraft } from "../../domain/templates/rules/validateTemplateDraft";

export async function saveTemplate(draft: TemplateDraft, repository: TemplateRepository) {
  const validation = validateTemplateDraft(draft);

  if (!validation.ok || !validation.completedDraft) {
    throw new Error(validation.message ?? "Template is incomplete.");
  }

  return repository.save(validation.completedDraft);
}

export async function updateTemplate(
  templateId: number,
  draft: TemplateDraft,
  repository: TemplateRepository,
) {
  const validation = validateTemplateDraft(draft);

  if (!validation.ok || !validation.completedDraft) {
    throw new Error(validation.message ?? "Template is incomplete.");
  }

  return repository.update(templateId, validation.completedDraft);
}
