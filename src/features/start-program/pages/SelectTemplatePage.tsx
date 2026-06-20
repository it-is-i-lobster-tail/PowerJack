import { ArrowLeft, ArrowRight, LockKeyhole, Pencil, Plus, Trash2 } from "lucide-react";
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { listTemplates } from "../../../application/templates/listTemplates";
import { useServices } from "../../../app/useServices";
import type { TemplateSummary } from "../../../domain/templates/Template";
import { Button } from "../../../shared/ui/Button";
import { ConfirmationModal } from "../../../shared/ui/ConfirmationModal";
import { useTemplateDraftStore } from "../../templates/state/templateDraftStore";
import { useStartProgramStore } from "../state/startProgramStore";
import "./SelectTemplatePage.css";

const EDIT_ACTIVE_TEMPLATE_MESSAGE = "Cannot Edit Templates In Use By Active Program";
const DELETE_ACTIVE_TEMPLATE_MESSAGE = "Cannot Delete Templates In Use By Active Program";
const LOCKED_ACTIVE_TEMPLATE_MESSAGE = "Cannot Edit Or Delete Templates In Use By Active Program";

export function SelectTemplatePage() {
  const navigate = useNavigate();
  const services = useServices();
  const selectedTemplateId = useStartProgramStore((state) => state.selectedTemplateId);
  const setSelectedTemplateId = useStartProgramStore((state) => state.setSelectedTemplateId);
  const resetProgramDraft = useStartProgramStore((state) => state.reset);
  const resetTemplateDraft = useTemplateDraftStore((state) => state.reset);
  const loadTemplateDraft = useTemplateDraftStore((state) => state.loadFromAggregate);
  const [templates, setTemplates] = useState<TemplateSummary[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [blockedTemplateMessage, setBlockedTemplateMessage] = useState<string | null>(null);
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
      .finally(() => {
        if (isMounted) {
          setIsLoading(false);
        }
      })
      .catch((error: unknown) => {
        console.error("Failed to load templates", error);
      });

    return () => {
      isMounted = false;
    };
  }, [services.templates]);

  async function reloadTemplates(): Promise<void> {
    setIsLoading(true);

    try {
      setTemplates(await listTemplates(services.templates));
    } catch (error: unknown) {
      console.error("Failed to load templates", error);
    } finally {
      setIsLoading(false);
    }
  }

  async function handleEditTemplate(template: TemplateSummary): Promise<void> {
    if (template.usedByActiveProgram) {
      setBlockedTemplateMessage(EDIT_ACTIVE_TEMPLATE_MESSAGE);
      return;
    }

    const isUsedByActiveProgram = await services.templates.isUsedByActiveProgram(template.id);

    if (isUsedByActiveProgram) {
      setBlockedTemplateMessage(EDIT_ACTIVE_TEMPLATE_MESSAGE);
      return;
    }

    const aggregate = await services.templates.loadAggregate(template.id);

    if (!aggregate) {
      await reloadTemplates();
      return;
    }

    loadTemplateDraft(aggregate);
    void navigate("/templates/new/name");
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

      if (selectedTemplateId === deleteTarget.id) {
        resetProgramDraft();
      }

      setDeleteTarget(null);
      await reloadTemplates();
    } catch (error: unknown) {
      console.error("Failed to delete template", error);
    } finally {
      setIsDeleting(false);
    }
  }

  return (
    <main className="app-screen select-template-screen" data-agent-id="select-template-page">
      <section className="app-flow select-template-flow" aria-labelledby="select-template-title">
        <div className="flow-header">
          <p>NEW PROGRAM</p>
          <h1 id="select-template-title">Select Template</h1>
        </div>

        <div className="template-grid" role="grid" aria-label="Templates" data-agent-id="template-grid">
          <div className="template-grid__content">
            {templates.length === 0 ? (
              <div className="template-grid__empty" data-agent-id="template-empty-state">
                <h2>{isLoading ? "Loading templates" : "No templates yet."}</h2>
                <p>Add a template to choose exercises and training days.</p>
              </div>
            ) : (
              templates.map((template) => {
                const isSelected = selectedTemplateId === template.id;
                const isLocked = template.usedByActiveProgram;
                const lockBadgeId = `template-lock-badge-${template.id}`;
                const rowClassName = [
                  "template-row",
                  isSelected ? "template-row--selected" : "",
                  isLocked ? "template-row--locked" : "",
                ]
                  .filter(Boolean)
                  .join(" ");

                return (
                  <div
                    aria-selected={isSelected}
                    className={rowClassName}
                    data-agent-id={`template-row-${template.id}`}
                    key={template.id}
                    role="row"
                  >
                    <button
                      aria-pressed={isSelected}
                      className="template-row__select"
                      onClick={() => setSelectedTemplateId(template.id)}
                      type="button"
                    >
                      <span className="template-row__text">
                        {isLocked ? (
                          <span
                            className="template-row__status"
                            data-agent-id={`active-template-label-${template.id}`}
                          >
                            Active Program Template
                          </span>
                        ) : null}
                        <span className="template-row__name">{template.name}</span>
                        <span className="template-row__meta">
                          {template.workoutsPerWeek} days per week · {template.exerciseCount} exercises
                        </span>
                      </span>
                      {template.focusMuscles.length > 0 ? (
                        <span className="template-row__focus" aria-label="Focus muscles">
                          {template.focusMuscles.map((muscle) => (
                            <span
                              className="template-row__chip"
                              data-agent-id={`template-focus-chip-${muscle.id}`}
                              key={muscle.id}
                            >
                              {muscle.name}
                            </span>
                          ))}
                        </span>
                      ) : null}
                    </button>
                    <span className="template-row__actions">
                      {isLocked ? (
                        <button
                          aria-label={`Template ${template.name} is locked while in use`}
                          className="template-row__lock-badge"
                          data-agent-id={lockBadgeId}
                          id={lockBadgeId}
                          onClick={() => setBlockedTemplateMessage(LOCKED_ACTIVE_TEMPLATE_MESSAGE)}
                          type="button"
                        >
                          <LockKeyhole aria-hidden size={14} strokeWidth={2.4} />
                          <span>Locked While In Use</span>
                        </button>
                      ) : null}
                      <span className="template-row__action-buttons">
                        <button
                          aria-describedby={isLocked ? lockBadgeId : undefined}
                          aria-disabled={isLocked ? "true" : undefined}
                          aria-label={
                            isLocked ? `Edit ${template.name} locked while in use` : `Edit ${template.name}`
                          }
                          className="template-row__icon-button"
                          data-agent-id={`edit-template-${template.id}`}
                          onClick={() => {
                            void handleEditTemplate(template);
                          }}
                          type="button"
                        >
                          <Pencil aria-hidden size={22} strokeWidth={2.2} />
                        </button>
                        <button
                          aria-describedby={isLocked ? lockBadgeId : undefined}
                          aria-disabled={isLocked ? "true" : undefined}
                          aria-label={
                            isLocked ? `Delete ${template.name} locked while in use` : `Delete ${template.name}`
                          }
                          className="template-row__icon-button"
                          data-agent-id={`delete-template-${template.id}`}
                          onClick={() => {
                            void handleDeleteTemplate(template);
                          }}
                          type="button"
                        >
                          <Trash2 aria-hidden size={23} strokeWidth={2.2} />
                        </button>
                      </span>
                    </span>
                  </div>
                );
              })
            )}
          </div>

          <Button
            className="template-grid__add"
            data-agent-id="add-template"
            leadingIcon={<Plus aria-hidden size={26} strokeWidth={2.6} />}
            onClick={() => {
              resetTemplateDraft();
              void navigate("/templates/new/name");
            }}
            variant="outline"
          >
            Add Template
          </Button>
        </div>

        <div className="flow-actions">
          <Button
            data-agent-id="select-template-back"
            leadingIcon={<ArrowLeft aria-hidden size={28} strokeWidth={2.4} />}
            onClick={() => {
              void navigate("/");
            }}
            variant="secondary"
          >
            Back
          </Button>
          <Button
            data-agent-id="select-template-next"
            disabled={!selectedTemplateId}
            onClick={() => {
              void navigate("/start/program-length");
            }}
            trailingIcon={<ArrowRight aria-hidden size={28} strokeWidth={2.4} />}
            variant="outline"
          >
            Next
          </Button>
        </div>
      </section>
      {blockedTemplateMessage ? (
        <ConfirmationModal
          agentId="template-in-use-dialog"
          onCancel={() => setBlockedTemplateMessage(null)}
          title={blockedTemplateMessage}
        />
      ) : null}
      {deleteTarget ? (
        <ConfirmationModal
          agentId="template-delete-confirmation"
          confirmAgentId="modal-delete"
          confirmLabel={isDeleting ? "Deleting" : "Delete"}
          destructive
          onCancel={() => setDeleteTarget(null)}
          onConfirm={() => {
            void confirmDeleteTemplate();
          }}
          title={`Confirm Deleting Template ${deleteTarget.name}`}
        />
      ) : null}
    </main>
  );
}
