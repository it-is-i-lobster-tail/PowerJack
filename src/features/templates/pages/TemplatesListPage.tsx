import { ConfirmationModal } from "../../../shared/ui/ConfirmationModal";
import { TemplateListPanel } from "../components/TemplateListPanel/TemplateListPanel";
import {
  EDIT_ACTIVE_TEMPLATE_BODY,
  EDIT_ACTIVE_TEMPLATE_TITLE,
  useTemplateListManagement,
} from "../hooks/useTemplateListManagement";
import "./TemplatesListPage.css";

export function TemplatesListPage() {
  const templateList = useTemplateListManagement({ returnPath: "/templates" });

  return (
    <main className="app-screen app-screen--scrollable templates-screen" data-agent-id="templates-page">
      <section className="templates-flow app-flow" aria-labelledby="templates-title">
        <div className="templates-header">
          <h1 id="templates-title">Templates</h1>
        </div>

        <TemplateListPanel
          addAgentId="templates-add-template"
          deleteAgentId={(template) => `templates-delete-template-${template.id}`}
          editAgentId={(template) => `templates-edit-template-${template.id}`}
          emptyAgentId="templates-empty-state"
          errorMessage={templateList.loadErrorMessage}
          gridAgentId="templates-grid"
          isLoading={templateList.isLoading}
          onAddTemplate={templateList.handleAddTemplate}
          onDeleteTemplate={(template) => {
            void templateList.handleDeleteTemplate(template);
          }}
          onEditTemplate={(template) => {
            void templateList.handleEditTemplate(template);
          }}
          rowAgentId={(template) => `templates-template-row-${template.id}`}
          templates={templateList.templates}
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
