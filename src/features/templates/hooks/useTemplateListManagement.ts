import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { listTemplates } from "../../../application/templates/listTemplates";
import { useServices } from "../../../app/useServices";
import type { TemplateSummary } from "../../../domain/templates/Template";
import type { TemplateFlowReturnPath } from "../state/templateDraftStore";
import { useTemplateDraftStore } from "../state/templateDraftStore";

export const EDIT_ACTIVE_TEMPLATE_TITLE =
  "Editing an active template will adjust progression of all remaining weeks of program.";
export const EDIT_ACTIVE_TEMPLATE_BODY = "Does not affect current week.";
export const DELETE_ACTIVE_TEMPLATE_MESSAGE = "Cannot delete templates in use by active program";

interface UseTemplateListManagementOptions {
  returnPath: TemplateFlowReturnPath;
  onDeletedTemplate?: (templateId: number) => void;
}

export function useTemplateListManagement({
  returnPath,
  onDeletedTemplate,
}: UseTemplateListManagementOptions) {
  const navigate = useNavigate();
  const services = useServices();
  const resetTemplateDraft = useTemplateDraftStore((state) => state.reset);
  const loadTemplateDraft = useTemplateDraftStore((state) => state.loadFromAggregate);
  const [templates, setTemplates] = useState<TemplateSummary[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadErrorMessage, setLoadErrorMessage] = useState<string | null>(null);
  const [blockedTemplateMessage, setBlockedTemplateMessage] = useState<string | null>(null);
  const [editTarget, setEditTarget] = useState<TemplateSummary | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<TemplateSummary | null>(null);
  const [isDeleting, setIsDeleting] = useState(false);

  useEffect(() => {
    let isMounted = true;

    void listTemplates(services.templates)
      .then((items) => {
        if (isMounted) {
          setTemplates(items);
        }
      })
      .catch((error: unknown) => {
        console.error("Failed to load templates", error);
        if (isMounted) {
          setLoadErrorMessage("Try again from the menu.");
        }
      })
      .finally(() => {
        if (isMounted) {
          setIsLoading(false);
        }
      });

    return () => {
      isMounted = false;
    };
  }, [services.templates]);

  async function reloadTemplates(): Promise<void> {
    setIsLoading(true);
    setLoadErrorMessage(null);

    try {
      setTemplates(await listTemplates(services.templates));
    } catch (error: unknown) {
      console.error("Failed to load templates", error);
      setLoadErrorMessage("Try again from the menu.");
    } finally {
      setIsLoading(false);
    }
  }

  function handleAddTemplate(): void {
    resetTemplateDraft(returnPath);
    void navigate("/templates/new/name");
  }

  async function openTemplateEditor(templateId: number): Promise<void> {
    const aggregate = await services.templates.loadAggregate(templateId);

    if (!aggregate) {
      await reloadTemplates();
      return;
    }

    loadTemplateDraft(aggregate, returnPath);
    void navigate("/templates/new/name");
  }

  async function handleEditTemplate(template: TemplateSummary): Promise<void> {
    if (template.usedByActiveProgram) {
      setEditTarget(template);
      return;
    }

    const isUsedByActiveProgram = await services.templates.isUsedByActiveProgram(template.id);

    if (isUsedByActiveProgram) {
      setEditTarget(template);
      return;
    }

    await openTemplateEditor(template.id);
  }

  async function confirmEditActiveTemplate(): Promise<void> {
    if (!editTarget) {
      return;
    }

    const templateId = editTarget.id;
    setEditTarget(null);
    await openTemplateEditor(templateId);
  }

  async function handleDeleteTemplate(template: TemplateSummary): Promise<void> {
    if (template.usedByActiveProgram) {
      setBlockedTemplateMessage(DELETE_ACTIVE_TEMPLATE_MESSAGE);
      return;
    }

    const isUsedByActiveProgram = await services.templates.isUsedByActiveProgram(template.id);

    if (isUsedByActiveProgram) {
      setBlockedTemplateMessage(DELETE_ACTIVE_TEMPLATE_MESSAGE);
      return;
    }

    setDeleteTarget(template);
  }

  async function confirmDeleteTemplate(): Promise<void> {
    if (!deleteTarget) {
      return;
    }

    setIsDeleting(true);

    try {
      await services.templates.softDelete(deleteTarget.id);
      onDeletedTemplate?.(deleteTarget.id);
      setDeleteTarget(null);
      await reloadTemplates();
    } catch (error: unknown) {
      console.error("Failed to delete template", error);
    } finally {
      setIsDeleting(false);
    }
  }

  return {
    templates,
    isLoading,
    loadErrorMessage,
    blockedTemplateMessage,
    editTarget,
    deleteTarget,
    isDeleting,
    handleAddTemplate,
    handleEditTemplate,
    handleDeleteTemplate,
    confirmEditActiveTemplate,
    confirmDeleteTemplate,
    dismissBlockedTemplateMessage: () => setBlockedTemplateMessage(null),
    cancelEditTemplate: () => setEditTarget(null),
    cancelDeleteTemplate: () => setDeleteTarget(null),
  };
}
