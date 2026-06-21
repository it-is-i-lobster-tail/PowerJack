import { ArrowLeft, ArrowRight } from "lucide-react";
import { Navigate, useNavigate } from "react-router-dom";
import { FlowActionBar } from "../../../shared/ui/FlowActionBar";
import { useTemplateDraftStore } from "../state/templateDraftStore";
import "../../start-program/pages/SetupChoicePage.css";

const daysPerWeekOptions = [2, 3, 4, 5, 6];

export function TemplateDaysPerWeekPage() {
  const navigate = useNavigate();
  const name = useTemplateDraftStore((state) => state.name);
  const focusMuscleIds = useTemplateDraftStore((state) => state.focusMuscleIds);
  const workoutsPerWeek = useTemplateDraftStore((state) => state.workoutsPerWeek);
  const setWorkoutsPerWeek = useTemplateDraftStore((state) => state.setWorkoutsPerWeek);

  if (!name.trim() || name.length > 64) {
    return <Navigate replace to="/templates/new/name" />;
  }

  if (focusMuscleIds.length === 0) {
    return <Navigate replace to="/templates/new/muscle-focus" />;
  }

  return (
    <main className="app-screen app-screen--centered" data-agent-id="template-days-per-week-page">
      <section className="setup-card app-flow" aria-labelledby="template-days-per-week-title">
        <h1 id="template-days-per-week-title">How many days do you want to train?</h1>

        <div
          className="choice-grid choice-grid--days-per-week"
          data-agent-id="template-days-per-week-options"
          role="radiogroup"
          aria-label="Template training days per week"
        >
          {daysPerWeekOptions.map((days) => (
            <button
              aria-checked={workoutsPerWeek === days}
              className={workoutsPerWeek === days ? "choice-button choice-button--selected" : "choice-button"}
              data-agent-id={`template-days-per-week-${days}`}
              key={days}
              onClick={() => setWorkoutsPerWeek(days)}
              role="radio"
              type="button"
            >
              {days}
            </button>
          ))}
        </div>

        <FlowActionBar
          leftAction={{
            agentId: "template-days-per-week-back",
            label: "Back",
            leadingIcon: <ArrowLeft aria-hidden size={28} strokeWidth={2.4} />,
            onClick: () => {
              void navigate("/templates/new/muscle-focus");
            },
          }}
          rightAction={{
            agentId: "template-days-per-week-next",
            disabled: !workoutsPerWeek,
            label: "Next",
            onClick: () => {
              void navigate("/templates/new/builder");
            },
            trailingIcon: <ArrowRight aria-hidden size={28} strokeWidth={2.4} />,
          }}
        />
      </section>
    </main>
  );
}
