import { ArrowLeft, ArrowRight } from "lucide-react";
import { Navigate, useNavigate } from "react-router-dom";
import { Button } from "../../../shared/ui/Button";
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
        <h1 id="template-days-per-week-title">Days Per Week</h1>

        <div className="choice-grid" role="radiogroup" aria-label="Template training days per week">
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

        <div className="setup-card__actions">
          <Button
            data-agent-id="template-days-per-week-back"
            leadingIcon={<ArrowLeft aria-hidden size={28} strokeWidth={2.4} />}
            onClick={() => {
              void navigate("/templates/new/muscle-focus");
            }}
            variant="secondary"
          >
            Back
          </Button>
          <Button
            data-agent-id="template-days-per-week-next"
            disabled={!workoutsPerWeek}
            onClick={() => {
              void navigate("/templates/new/builder");
            }}
            trailingIcon={<ArrowRight aria-hidden size={28} strokeWidth={2.4} />}
            variant="outline"
          >
            Next
          </Button>
        </div>
      </section>
    </main>
  );
}
