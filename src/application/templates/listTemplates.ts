import type { TemplateRepository } from "../../domain/templates/TemplateRepository";

export async function listTemplates(repository: TemplateRepository) {
  return repository.list();
}
