import { ArrowLeft, ArrowRight } from "lucide-react";
import { useState } from "react";
import { Navigate, useNavigate } from "react-router-dom";
import { startProgramFromTemplate } from "../../../application/programs/startProgramFromTemplate";
import { useServices } from "../../../app/useServices";
import { validateProgramLengthWeeks } from "../../../domain/programs/rules/validateProgramLengthWeeks";
import { ConfirmationModal } from "../../../shared/ui/ConfirmationModal";
import { FlowActionBar } from "../../../shared/ui/FlowActionBar";
import { useStartProgramStore } from "../state/startProgramStore";
import "./SetupChoicePage.css";

const programLengthOptions = [4, 6, 8, 10, 12];

export function ProgramLengthPage() {
  const navigate = useNavigate();
  const services = useServices();
  const selectedTemplateId = useStartProgramStore((state) => state.selectedTemplateId);
  const selectedWeeks = useStartProgramStore((state) => state.programLengthWeeks);
  const setProgramLengthWeeks = useStartProgramStore((state) => state.setProgramLengthWeeks);
  const [isStarting, setIsStarting] = useState(false);
  const [showReplaceConfirmation, setShowReplaceConfirmation] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const canContinue = validateProgramLengthWeeks(selectedWeeks).ok;

  if (!selectedTemplateId) {
    return <Navigate replace to="/start/select-template" />;
  }

  async function handleStart(replaceActiveProgram = false): Promise<void> {
    if (!selectedTemplateId || !selectedWeeks) {
      return;
    }

    setIsStarting(true);
    setError(null);

    try {
      const appState = await services.appState.load();

      if (appState?.activeProgramId && !replaceActiveProgram) {
        setShowReplaceConfirmation(true);
        return;
      }

      const state = await startProgramFromTemplate(
        {
          templateId: selectedTemplateId,
          programLengthWeeks: selectedWeeks,
          replaceActiveProgram,
        },
        {
          appState: services.appState,
          templates: services.templates,
          programs: services.programs,
        },
      );

      if (!state.activeProgramId || !state.activeWorkoutId) {
        throw new Error("Program started without an active workout.");
      }

      setShowReplaceConfirmation(false);
      void navigate(`/programs/${state.activeProgramId}/workouts/${state.activeWorkoutId}`);
    } catch (error: unknown) {
      setError(error instanceof Error ? error.message : "Could not start program.");
    } finally {
      setIsStarting(false);
    }
  }

  return (
    <main className="app-screen app-screen--centered" data-agent-id="program-length-page">
      <section className="setup-card app-flow" aria-labelledby="program-length-title">
        <h1 id="program-length-title">How many weeks do you want to train?</h1>

        <div className="choice-grid" role="radiogroup" aria-label="Program length in weeks">
          {programLengthOptions.map((weeks) => (
            <button
              aria-checked={selectedWeeks === weeks}
              className={selectedWeeks === weeks ? "choice-button choice-button--selected" : "choice-button"}
              data-agent-id={`program-length-${weeks}`}
              key={weeks}
              onClick={() => setProgramLengthWeeks(weeks)}
              role="radio"
              type="button"
            >
              {weeks}
            </button>
          ))}
        </div>

        {error ? (
          <p className="setup-card__error" data-agent-id="program-length-error">
            {error}
          </p>
        ) : null}

        <FlowActionBar
          leftAction={{
            agentId: "program-length-back",
            label: "Back",
            leadingIcon: <ArrowLeft aria-hidden size={28} strokeWidth={2.4} />,
            onClick: () => {
              void navigate("/start/select-template");
            },
          }}
          rightAction={{
            agentId: "program-length-next",
            disabled: !canContinue || isStarting,
            label: isStarting ? "Starting" : "Start",
            onClick: () => {
              void handleStart();
            },
            trailingIcon: <ArrowRight aria-hidden size={28} strokeWidth={2.4} />,
          }}
        />
      </section>
      {showReplaceConfirmation ? (
        <ConfirmationModal
          agentId="program-replace-confirmation"
          body="Halted programs cannot be resumed."
          confirmLabel={isStarting ? "Confirming" : "Confirm"}
          destructive
          onCancel={() => setShowReplaceConfirmation(false)}
          onConfirm={() => {
            void handleStart(true);
          }}
          title="Halt current program and start new one"
        />
      ) : null}
    </main>
  );
}
