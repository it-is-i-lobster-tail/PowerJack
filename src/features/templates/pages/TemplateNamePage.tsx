import { ArrowLeft, ArrowRight } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { FlowActionBar } from "../../../shared/ui/FlowActionBar";
import { useTemplateDraftStore } from "../state/templateDraftStore";
import "../../start-program/pages/SetupChoicePage.css";
import "./TemplateNamePage.css";

export function TemplateNamePage() {
  const navigate = useNavigate();
  const name = useTemplateDraftStore((state) => state.name);
  const setName = useTemplateDraftStore((state) => state.setName);
  const nameLength = name.length;
  const isNameTooLong = nameLength > 64;
  const canContinue = nameLength > 0 && nameLength <= 64 && name.trim().length > 0;

  return (
    <main className="app-screen app-screen--centered" data-agent-id="template-name-page">
      <section className="setup-card app-flow" aria-labelledby="template-name-title">
        <h1 id="template-name-title">Name your template</h1>

        <label className="template-name-field">
          <span>Template name</span>
          <input
            autoFocus
            data-agent-id="template-name-input"
            onChange={(event) => setName(event.target.value)}
            placeholder="My new template"
            value={name}
          />
          {isNameTooLong ? (
            <strong className="template-name-count" data-agent-id="template-name-count">
              {nameLength}/64
            </strong>
          ) : null}
        </label>

        <FlowActionBar
          leftAction={{
            agentId: "template-name-back",
            label: "Back",
            leadingIcon: <ArrowLeft aria-hidden size={28} strokeWidth={2.4} />,
            onClick: () => {
              void navigate("/start/select-template");
            },
          }}
          rightAction={{
            agentId: "template-name-next",
            disabled: !canContinue,
            label: "Next",
            onClick: () => {
              void navigate("/templates/new/muscle-focus");
            },
            trailingIcon: <ArrowRight aria-hidden size={28} strokeWidth={2.4} />,
          }}
        />
      </section>
    </main>
  );
}
