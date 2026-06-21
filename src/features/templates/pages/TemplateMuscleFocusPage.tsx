import { ArrowLeft, ArrowRight } from "lucide-react";
import { useEffect, useState } from "react";
import { Navigate, useNavigate } from "react-router-dom";
import { listMuscles } from "../../../application/exercises/listMuscles";
import { useServices } from "../../../app/useServices";
import type { Muscle } from "../../../domain/exercises/Exercise";
import { FlowActionBar } from "../../../shared/ui/FlowActionBar";
import { useTemplateDraftStore } from "../state/templateDraftStore";
import "../../start-program/pages/SetupChoicePage.css";
import "./TemplateMuscleFocusPage.css";

export function TemplateMuscleFocusPage() {
  const navigate = useNavigate();
  const services = useServices();
  const name = useTemplateDraftStore((state) => state.name);
  const focusMuscleIds = useTemplateDraftStore((state) => state.focusMuscleIds);
  const toggleFocusMuscle = useTemplateDraftStore((state) => state.toggleFocusMuscle);
  const [muscles, setMuscles] = useState<Muscle[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    let isMounted = true;

    void listMuscles(services.exercises)
      .then((items) => {
        if (isMounted) {
          setMuscles(items);
        }
      })
      .catch((error: unknown) => {
        console.error("Failed to load muscles", error);
      })
      .finally(() => {
        if (isMounted) {
          setIsLoading(false);
        }
      });

    return () => {
      isMounted = false;
    };
  }, [services.exercises]);

  if (!name.trim() || name.length > 64) {
    return <Navigate replace to="/templates/new/name" />;
  }

  const canContinue = focusMuscleIds.length > 0;

  return (
    <main className="app-screen app-screen--centered" data-agent-id="template-muscle-focus-page">
      <section className="setup-card app-flow" aria-labelledby="template-muscle-focus-title">
        <div className="muscle-focus-header">
          <h1 id="template-muscle-focus-title">What would you like to focus on?</h1>
          <span data-agent-id="template-focus-counter">{focusMuscleIds.length}/4</span>
        </div>

        <div className="muscle-focus-grid" role="grid" aria-label="Muscle group focus">
          {isLoading ? (
            <p className="muscle-focus-empty">Loading muscles</p>
          ) : (
            muscles.map((muscle) => {
              const isSelected = focusMuscleIds.includes(muscle.id);

              return (
                <button
                  aria-pressed={isSelected}
                  className={
                    isSelected
                      ? "muscle-focus-option muscle-focus-option--selected"
                      : "muscle-focus-option"
                  }
                  data-agent-id={`template-focus-muscle-${muscle.id}`}
                  key={muscle.id}
                  onClick={() => toggleFocusMuscle(muscle.id)}
                  type="button"
                >
                  {muscle.name}
                </button>
              );
            })
          )}
        </div>

        <FlowActionBar
          leftAction={{
            agentId: "template-muscle-focus-back",
            label: "Back",
            leadingIcon: <ArrowLeft aria-hidden size={28} strokeWidth={2.4} />,
            onClick: () => {
              void navigate("/templates/new/name");
            },
          }}
          rightAction={{
            agentId: "template-muscle-focus-next",
            disabled: !canContinue,
            label: "Next",
            onClick: () => {
              void navigate("/templates/new/days-per-week");
            },
            trailingIcon: <ArrowRight aria-hidden size={28} strokeWidth={2.4} />,
          }}
        />
      </section>
    </main>
  );
}
