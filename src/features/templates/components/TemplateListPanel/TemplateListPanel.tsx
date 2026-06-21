import { Pencil, Plus, Trash2 } from "lucide-react";
import type { ReactNode } from "react";
import type { TemplateSummary } from "../../../../domain/templates/Template";
import { Button } from "../../../../shared/ui/Button";
import "./TemplateListPanel.css";

interface TemplateListPanelProps {
  templates: TemplateSummary[];
  isLoading: boolean;
  errorMessage?: string | null;
  gridAgentId: string;
  emptyAgentId: string;
  addAgentId: string;
  rowAgentId: (template: TemplateSummary) => string;
  editAgentId: (template: TemplateSummary) => string;
  deleteAgentId: (template: TemplateSummary) => string;
  focusChipAgentId?: (muscleId: number) => string;
  selectedTemplateId?: number | null;
  onSelectTemplate?: (template: TemplateSummary) => void;
  onAddTemplate: () => void;
  onEditTemplate: (template: TemplateSummary) => void;
  onDeleteTemplate: (template: TemplateSummary) => void;
}

export function TemplateListPanel({
  templates,
  isLoading,
  errorMessage,
  gridAgentId,
  emptyAgentId,
  addAgentId,
  rowAgentId,
  editAgentId,
  deleteAgentId,
  focusChipAgentId = (muscleId) => `template-focus-chip-${muscleId}`,
  selectedTemplateId,
  onSelectTemplate,
  onAddTemplate,
  onEditTemplate,
  onDeleteTemplate,
}: TemplateListPanelProps) {
  const hasSelection = selectedTemplateId !== undefined;

  return (
    <div className="template-grid" role="grid" aria-label="Templates" data-agent-id={gridAgentId}>
      <div className="template-grid__content">
        {templates.length === 0 ? (
          <TemplateListEmptyState
            agentId={emptyAgentId}
            errorMessage={errorMessage}
            isLoading={isLoading}
          />
        ) : (
          templates.map((template) => {
            const isSelected = selectedTemplateId === template.id;
            const isLocked = template.usedByActiveProgram;
            const rowClassName = [
              "template-row",
              isSelected ? "template-row--selected" : "",
              isLocked ? "template-row--locked" : "",
            ]
              .filter(Boolean)
              .join(" ");

            return (
              <div
                aria-selected={hasSelection ? isSelected : undefined}
                className={rowClassName}
                data-agent-id={rowAgentId(template)}
                key={template.id}
                role="row"
              >
                {onSelectTemplate ? (
                  <button
                    aria-pressed={isSelected}
                    className="template-row__select"
                    onClick={() => onSelectTemplate(template)}
                    type="button"
                  >
                    <TemplateRowContent
                      focusChipAgentId={focusChipAgentId}
                      isLocked={isLocked}
                      template={template}
                    />
                  </button>
                ) : (
                  <div className="template-row__select template-row__select--static">
                    <TemplateRowContent
                      focusChipAgentId={focusChipAgentId}
                      isLocked={isLocked}
                      template={template}
                    />
                  </div>
                )}
                <span className="template-row__actions">
                  <span className="template-row__action-buttons">
                    <button
                      aria-label={`Edit ${template.name}`}
                      className="template-row__icon-button"
                      data-agent-id={editAgentId(template)}
                      onClick={() => onEditTemplate(template)}
                      type="button"
                    >
                      <Pencil aria-hidden size={22} strokeWidth={2.2} />
                    </button>
                    <button
                      aria-disabled={isLocked ? "true" : undefined}
                      aria-label={
                        isLocked ? `Delete ${template.name} locked while in use` : `Delete ${template.name}`
                      }
                      className="template-row__icon-button"
                      data-agent-id={deleteAgentId(template)}
                      onClick={() => onDeleteTemplate(template)}
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
        data-agent-id={addAgentId}
        leadingIcon={<Plus aria-hidden size={26} strokeWidth={2.6} />}
        onClick={onAddTemplate}
        variant="outline"
      >
        Add template
      </Button>
    </div>
  );
}

interface TemplateListEmptyStateProps {
  agentId: string;
  isLoading: boolean;
  errorMessage?: string | null;
}

function TemplateListEmptyState({ agentId, isLoading, errorMessage }: TemplateListEmptyStateProps) {
  let title = "No templates yet.";
  let body: ReactNode = "Add a template to choose exercises and training days.";

  if (isLoading) {
    title = "Loading templates";
  } else if (errorMessage) {
    title = "Templates could not load.";
    body = errorMessage;
  }

  return (
    <div className="template-grid__empty" data-agent-id={agentId}>
      <h2>{title}</h2>
      <p>{body}</p>
    </div>
  );
}

interface TemplateRowContentProps {
  template: TemplateSummary;
  isLocked: boolean;
  focusChipAgentId: (muscleId: number) => string;
}

function TemplateRowContent({ template, isLocked, focusChipAgentId }: TemplateRowContentProps) {
  return (
    <>
      <span className="template-row__text">
        {isLocked ? (
          <span className="template-row__status" data-agent-id={`active-template-label-${template.id}`}>
            Active program template
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
              data-agent-id={focusChipAgentId(muscle.id)}
              key={muscle.id}
            >
              {muscle.name}
            </span>
          ))}
        </span>
      ) : null}
    </>
  );
}
