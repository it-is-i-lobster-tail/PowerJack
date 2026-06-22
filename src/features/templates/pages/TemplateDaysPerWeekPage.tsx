import { ArrowLeft, ArrowRight } from "lucide-react";
import { useState } from "react";
import { Navigate, useNavigate } from "react-router-dom";
import { ConfirmationModal } from "../../../shared/ui/ConfirmationModal";
import { FlowActionBar } from "../../../shared/ui/FlowActionBar";
import { useTemplateDraftStore, type WorkoutsPerWeekChangePlan } from "../state/templateDraftStore";
import "../../start-program/pages/SetupChoicePage.css";

const daysPerWeekOptions = [2, 3, 4, 5, 6];

export function TemplateDaysPerWeekPage() {
  const navigate = useNavigate();
  const name = useTemplateDraftStore((state) => state.name);
  const focusMuscleIds = useTemplateDraftStore((state) => state.focusMuscleIds);
  const workoutsPerWeek = useTemplateDraftStore((state) => state.workoutsPerWeek);
  const previewWorkoutsPerWeekChange = useTemplateDraftStore((state) => state.previewWorkoutsPerWeekChange);
  const setWorkoutsPerWeek = useTemplateDraftStore((state) => state.setWorkoutsPerWeek);
  const [selectedWorkoutsPerWeek, setSelectedWorkoutsPerWeek] = useState<number | null>(workoutsPerWeek);
  const [pendingReductionPlan, setPendingReductionPlan] = useState<WorkoutsPerWeekChangePlan | null>(null);

  if (!name.trim() || name.length > 64) {
    return <Navigate replace to="/templates/new/name" />;
  }

  if (focusMuscleIds.length === 0) {
    return <Navigate replace to="/templates/new/muscle-focus" />;
  }

  function handleNext(): void {
    if (!selectedWorkoutsPerWeek) {
      return;
    }

    const plan = previewWorkoutsPerWeekChange(selectedWorkoutsPerWeek);

    if (plan.requiresConfirmation) {
      setPendingReductionPlan(plan);
      return;
    }

    setWorkoutsPerWeek(selectedWorkoutsPerWeek);
    void navigate("/templates/new/builder");
  }

  function confirmPendingReduction(): void {
    if (!pendingReductionPlan) {
      return;
    }

    setWorkoutsPerWeek(pendingReductionPlan.workoutsPerWeek);
    setPendingReductionPlan(null);
    void navigate("/templates/new/builder");
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
              aria-checked={selectedWorkoutsPerWeek === days}
              className={selectedWorkoutsPerWeek === days ? "choice-button choice-button--selected" : "choice-button"}
              data-agent-id={`template-days-per-week-${days}`}
              key={days}
              onClick={() => setSelectedWorkoutsPerWeek(days)}
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
            disabled: !selectedWorkoutsPerWeek,
            label: "Next",
            onClick: handleNext,
            trailingIcon: <ArrowRight aria-hidden size={28} strokeWidth={2.4} />,
          }}
        />
      </section>
      {pendingReductionPlan ? (
        <ConfirmationModal
          agentId="template-days-reduction-confirmation"
          body={`The following Days will be removed: ${formatDayList(pendingReductionPlan.daysToRemove)}.`}
          confirmLabel="Confirm"
          destructive
          onCancel={() => setPendingReductionPlan(null)}
          onConfirm={confirmPendingReduction}
          title="Remove Workout Days?"
        />
      ) : null}
    </main>
  );
}

function formatDayList(days: number[]): string {
  const labels = days.map((day) => `Day ${day}`);

  if (labels.length <= 2) {
    return labels.join(" and ");
  }

  return `${labels.slice(0, -1).join(", ")}, and ${labels[labels.length - 1]}`;
}
