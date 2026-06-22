import { ArrowLeft, ArrowRight } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { ConfirmationModal } from "../../../shared/ui/ConfirmationModal";
import { FlowActionBar } from "../../../shared/ui/FlowActionBar";
import { TemplateListPanel } from "../../templates/components/TemplateListPanel/TemplateListPanel";
import {
  EDIT_ACTIVE_TEMPLATE_BODY,
  EDIT_ACTIVE_TEMPLATE_TITLE,
  useTemplateListManagement,
} from "../../templates/hooks/useTemplateListManagement";
import { useStartProgramStore } from "../state/startProgramStore";
import "./SelectTemplatePage.css";

export function SelectTemplatePage() {
  const navigate = useNavigate();
  const selectedTemplateId = useStartProgramStore((state) => state.selectedTemplateId);
  const setSelectedTemplateId = useStartProgramStore((state) => state.setSelectedTemplateId);
  const resetProgramDraft = useStartProgramStore((state) => state.reset);
  const templateList = useTemplateListManagement({
    returnPath: "/start/select-template",
    onDeletedTemplate: (templateId) => {
      if (selectedTemplateId === templateId) {
        resetProgramDraft();
      }
    },
  });

  return (
    <main className="app-screen app-screen--scrollable select-template-screen" data-agent-id="select-template-page">
      <section className="app-flow select-template-flow" aria-labelledby="select-template-title">
        <div className="flow-header">
          <p>New program</p>
          <h1 id="select-template-title">Select template</h1>
        </div>

        <TemplateListPanel
          addAgentId="add-template"
          deleteAgentId={(template) => `delete-template-${template.id}`}
          editAgentId={(template) => `edit-template-${template.id}`}
          emptyAgentId="template-empty-state"
          errorMessage={templateList.loadErrorMessage}
          gridAgentId="template-grid"
          isLoading={templateList.isLoading}
          onAddTemplate={templateList.handleAddTemplate}
          onDeleteTemplate={(template) => {
            void templateList.handleDeleteTemplate(template);
          }}
          onEditTemplate={(template) => {
            void templateList.handleEditTemplate(template);
          }}
          onSelectTemplate={(template) => setSelectedTemplateId(template.id)}
          rowAgentId={(template) => `template-row-${template.id}`}
          selectedTemplateId={selectedTemplateId}
          templates={templateList.templates}
        />

        <FlowActionBar
          leftAction={{
            agentId: "select-template-back",
            label: "Back",
            leadingIcon: <ArrowLeft aria-hidden size={28} strokeWidth={2.4} />,
            onClick: () => {
              void navigate("/");
            },
          }}
          rightAction={{
            agentId: "select-template-next",
            disabled: !selectedTemplateId,
            label: "Next",
            onClick: () => {
              void navigate("/start/program-length");
            },
            trailingIcon: <ArrowRight aria-hidden size={28} strokeWidth={2.4} />,
          }}
        />
      </section>
      {templateList.blockedTemplateMessage ? (
        <ConfirmationModal
          agentId="template-in-use-dialog"
          onCancel={templateList.dismissBlockedTemplateMessage}
          title={templateList.blockedTemplateMessage}
        />
      ) : null}
      {templateList.editTarget ? (
        <ConfirmationModal
          agentId="template-active-edit-confirmation"
          body={EDIT_ACTIVE_TEMPLATE_BODY}
          confirmLabel="Confirm"
          destructive
          onCancel={templateList.cancelEditTemplate}
          onConfirm={() => {
            void templateList.confirmEditActiveTemplate();
          }}
          title={EDIT_ACTIVE_TEMPLATE_TITLE}
        />
      ) : null}
      {templateList.deleteTarget ? (
        <ConfirmationModal
          agentId="template-delete-confirmation"
          confirmAgentId="modal-delete"
          confirmLabel={templateList.isDeleting ? "Deleting" : "Delete"}
          destructive
          onCancel={templateList.cancelDeleteTemplate}
          onConfirm={() => {
            void templateList.confirmDeleteTemplate();
          }}
          title={`Confirm deleting template ${templateList.deleteTarget.name}`}
        />
      ) : null}
    </main>
  );
}
