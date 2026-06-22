import {
  DndContext,
  KeyboardSensor,
  PointerSensor,
  closestCenter,
  type DragEndEvent,
  useSensor,
  useSensors,
} from "@dnd-kit/core";
import {
  SortableContext,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { ArrowLeft, GripVertical, Pencil, Plus, Save, Trash2, X } from "lucide-react";
import { useEffect, useMemo, useState, type CSSProperties } from "react";
import { Navigate, useNavigate } from "react-router-dom";
import { listExerciseSummariesByIds } from "../../../application/exercises/listExerciseSummariesByIds";
import { searchExercises } from "../../../application/exercises/searchExercises";
import { saveTemplate, updateTemplate } from "../../../application/templates/saveTemplate";
import { useServices } from "../../../app/useServices";
import type { ExerciseSummary } from "../../../domain/exercises/Exercise";
import { validateTemplateDraft } from "../../../domain/templates/rules/validateTemplateDraft";
import { Button } from "../../../shared/ui/Button";
import { FlowActionBar } from "../../../shared/ui/FlowActionBar";
import { useStartProgramStore } from "../../start-program/state/startProgramStore";
import { useTemplateDraftStore } from "../state/templateDraftStore";
import "./TemplateBuilderPage.css";

interface BuilderExerciseItem {
  exercise: ExerciseSummary;
  index: number;
  sortableId: string;
}

interface ExerciseSearchResultsProps {
  exercises: ExerciseSummary[];
  resultAgentId: (exerciseId: number) => string;
  onSelect: (exerciseId: number) => void;
}

export function TemplateBuilderPage() {
  const navigate = useNavigate();
  const services = useServices();
  const editingTemplateId = useTemplateDraftStore((state) => state.editingTemplateId);
  const returnPath = useTemplateDraftStore((state) => state.returnPath);
  const name = useTemplateDraftStore((state) => state.name);
  const focusMuscleIds = useTemplateDraftStore((state) => state.focusMuscleIds);
  const workoutsPerWeek = useTemplateDraftStore((state) => state.workoutsPerWeek);
  const activeDay = useTemplateDraftStore((state) => state.activeDay);
  const exerciseIdsByDay = useTemplateDraftStore((state) => state.exerciseIdsByDay);
  const setActiveDay = useTemplateDraftStore((state) => state.setActiveDay);
  const addExerciseToDay = useTemplateDraftStore((state) => state.addExerciseToDay);
  const reorderExerciseInDay = useTemplateDraftStore((state) => state.reorderExerciseInDay);
  const replaceExerciseInDay = useTemplateDraftStore((state) => state.replaceExerciseInDay);
  const removeExerciseFromDay = useTemplateDraftStore((state) => state.removeExerciseFromDay);
  const toDraft = useTemplateDraftStore((state) => state.toDraft);
  const setSelectedTemplateId = useStartProgramStore((state) => state.setSelectedTemplateId);
  const [allExercises, setAllExercises] = useState<ExerciseSummary[]>([]);
  const [query, setQuery] = useState("");
  const [editQuery, setEditQuery] = useState("");
  const [addSearchResults, setAddSearchResults] = useState<ExerciseSummary[]>([]);
  const [editSearchResults, setEditSearchResults] = useState<ExerciseSummary[]>([]);
  const [editingIndex, setEditingIndex] = useState<number | null>(null);
  const [isSearchOpen, setIsSearchOpen] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const sensors = useSensors(
    useSensor(PointerSensor, {
      activationConstraint: {
        distance: 8,
      },
    }),
    useSensor(KeyboardSensor, {
      coordinateGetter: sortableKeyboardCoordinates,
    }),
  );
  const dayTabsStyle = {
    "--template-day-count": workoutsPerWeek,
  } as CSSProperties & Record<"--template-day-count", number>;

  useEffect(() => {
    let isMounted = true;

    void searchExercises("", services.exercises)
      .then((items) => {
        if (isMounted) {
          setAllExercises(items);
        }
      })
      .catch((error: unknown) => {
        console.error("Failed to load exercise catalog", error);
      });

    return () => {
      isMounted = false;
    };
  }, [services.exercises]);

  useEffect(() => {
    let isMounted = true;
    const normalizedQuery = query.trim();

    if (!normalizedQuery) {
      return () => {
        isMounted = false;
      };
    }

    void searchExercises(normalizedQuery, services.exercises)
      .then((items) => {
        if (isMounted) {
          setAddSearchResults(items.slice(0, 8));
          setAllExercises((currentExercises) => mergeExercises(currentExercises, items));
        }
      })
      .catch((error: unknown) => {
        console.error("Failed to search exercises", error);
      });

    return () => {
      isMounted = false;
    };
  }, [query, services.exercises]);

  useEffect(() => {
    let isMounted = true;
    const normalizedQuery = editQuery.trim();

    if (!normalizedQuery) {
      return () => {
        isMounted = false;
      };
    }

    void searchExercises(normalizedQuery, services.exercises)
      .then((items) => {
        if (isMounted) {
          setEditSearchResults(items.slice(0, 8));
          setAllExercises((currentExercises) => mergeExercises(currentExercises, items));
        }
      })
      .catch((error: unknown) => {
        console.error("Failed to search exercises", error);
      });

    return () => {
      isMounted = false;
    };
  }, [editQuery, services.exercises]);

  const exercisesById = useMemo(
    () => new Map(allExercises.map((exercise) => [exercise.id, exercise])),
    [allExercises],
  );
  const currentExerciseIds = useMemo(() => exerciseIdsByDay[activeDay] ?? [], [activeDay, exerciseIdsByDay]);
  const missingCurrentExerciseIds = useMemo(
    () => currentExerciseIds.filter((exerciseId) => !exercisesById.has(exerciseId)),
    [currentExerciseIds, exercisesById],
  );

  useEffect(() => {
    const uniqueMissingExerciseIds = [...new Set(missingCurrentExerciseIds)];

    if (uniqueMissingExerciseIds.length === 0) {
      return;
    }

    let isMounted = true;

    void listExerciseSummariesByIds(uniqueMissingExerciseIds, services.exercises)
      .then((items) => {
        if (isMounted && items.length > 0) {
          setAllExercises((currentExercises) => mergeExercises(currentExercises, items));
        }
      })
      .catch((error: unknown) => {
        console.error("Failed to load selected exercises", error);
      });

    return () => {
      isMounted = false;
    };
  }, [missingCurrentExerciseIds, services.exercises]);

  const currentExerciseItems = currentExerciseIds.flatMap<BuilderExerciseItem>((exerciseId, index) => {
    const exercise = exercisesById.get(exerciseId);

    if (!exercise) {
      return [];
    }

    return [
      {
        exercise,
        index,
        sortableId: buildSortableId(activeDay, index),
      },
    ];
  });
  const sortableIds = currentExerciseItems.map((item) => item.sortableId);
  const isHydratingCurrentExercises =
    currentExerciseIds.length > 0 && currentExerciseItems.length < currentExerciseIds.length;
  const validation = validateTemplateDraft(toDraft());
  const canSave = validation.ok && !isSaving;

  if (!name.trim() || name.length > 64) {
    return <Navigate replace to="/templates/new/name" />;
  }

  if (focusMuscleIds.length === 0) {
    return <Navigate replace to="/templates/new/muscle-focus" />;
  }

  if (!workoutsPerWeek) {
    return <Navigate replace to="/templates/new/days-per-week" />;
  }

  async function handleSave() {
    if (!canSave) {
      return;
    }

    setIsSaving(true);
    setSaveError(null);

    try {
      const savedTemplate = editingTemplateId
        ? await updateTemplate(editingTemplateId, toDraft(), services.templates)
        : await saveTemplate(toDraft(), services.templates);
      if (returnPath === "/start/select-template") {
        setSelectedTemplateId(savedTemplate.id);
      }
      void navigate(returnPath);
    } catch (error: unknown) {
      console.error("Failed to save template", error);
      setSaveError("Template could not be saved. Try again.");
    } finally {
      setIsSaving(false);
    }
  }

  function handleDragEnd(event: DragEndEvent): void {
    const { active, over } = event;

    if (!over || active.id === over.id) {
      return;
    }

    const fromIndex = sortableIds.indexOf(String(active.id));
    const toIndex = sortableIds.indexOf(String(over.id));

    if (fromIndex >= 0 && toIndex >= 0) {
      reorderExerciseInDay(activeDay, fromIndex, toIndex);
      setEditingIndex(null);
      clearEditQuery();
    }
  }

  function handleOpenAddSearch(): void {
    setEditingIndex(null);
    clearEditQuery();
    setIsSearchOpen(true);
  }

  function handleOpenEdit(index: number): void {
    setIsSearchOpen(false);
    clearAddQuery();
    setEditingIndex(index);
    clearEditQuery();
  }

  function handleSetActiveDay(day: number): void {
    setEditingIndex(null);
    clearEditQuery();
    setIsSearchOpen(false);
    clearAddQuery();
    setActiveDay(day);
  }

  function handleAddQueryChange(value: string): void {
    setQuery(value);

    if (!value.trim()) {
      setAddSearchResults([]);
    }
  }

  function handleEditQueryChange(value: string): void {
    setEditQuery(value);

    if (!value.trim()) {
      setEditSearchResults([]);
    }
  }

  function clearAddQuery(): void {
    setQuery("");
    setAddSearchResults([]);
  }

  function clearEditQuery(): void {
    setEditQuery("");
    setEditSearchResults([]);
  }

  return (
    <main className="app-screen template-builder-screen" data-agent-id="template-builder-page">
      <section className="app-flow template-builder-flow" aria-labelledby="template-builder-title">
        <header className="template-builder-header">
          <p>{editingTemplateId ? "Edit template" : "New template"}</p>
          <h1 id="template-builder-title">{name.trim()}</h1>
          <span>{workoutsPerWeek} days per week</span>
        </header>

        <div className="day-tabs" role="tablist" aria-label="Template days" style={dayTabsStyle}>
          {Array.from({ length: workoutsPerWeek }, (_, index) => {
            const day = index + 1;

            return (
              <button
                aria-selected={activeDay === day}
                className={activeDay === day ? "day-tab day-tab--active" : "day-tab"}
                data-agent-id={`template-day-${day}`}
                key={day}
                onClick={() => handleSetActiveDay(day)}
                role="tab"
                type="button"
              >
                Day {day}
              </button>
            );
          })}
        </div>

        <section className="builder-panel" aria-labelledby="active-day-title">
          <div className="builder-panel__header">
            <h2 id="active-day-title">Day {activeDay}</h2>
            <span>
              {currentExerciseIds.length} {currentExerciseIds.length === 1 ? "exercise" : "exercises"}
            </span>
          </div>

          {currentExerciseIds.length === 0 ? (
            <p className="builder-panel__empty">No exercises yet.</p>
          ) : isHydratingCurrentExercises ? (
            <p className="builder-panel__empty" data-agent-id="template-exercises-loading">
              Loading exercises...
            </p>
          ) : (
            <DndContext collisionDetection={closestCenter} onDragEnd={handleDragEnd} sensors={sensors}>
              <SortableContext items={sortableIds} strategy={verticalListSortingStrategy}>
                <div className="builder-exercise-list">
                  {currentExerciseItems.map(({ exercise, index, sortableId }) => (
                    <SortableExerciseRow
                      editQuery={editQuery}
                      editResults={editSearchResults}
                      exercise={exercise}
                      index={index}
                      isEditing={editingIndex === index}
                      key={sortableId}
                      onCancelEdit={() => {
                        setEditingIndex(null);
                        clearEditQuery();
                      }}
                      onEdit={() => handleOpenEdit(index)}
                      onEditQueryChange={handleEditQueryChange}
                      onRemove={() => {
                        removeExerciseFromDay(activeDay, index);
                        setEditingIndex(null);
                        clearEditQuery();
                      }}
                      onReplace={(exerciseId) => {
                        replaceExerciseInDay(activeDay, index, exerciseId);
                        setEditingIndex(null);
                        clearEditQuery();
                      }}
                      sortableId={sortableId}
                    />
                  ))}
                </div>
              </SortableContext>
            </DndContext>
          )}

          {isHydratingCurrentExercises ? null : isSearchOpen ? (
            <div className="exercise-search" data-agent-id="exercise-search-panel">
              <div className="exercise-search__top">
                <h3>Add exercise</h3>
                <button
                  aria-label="Close exercise search"
                  className="builder-icon-button"
                  data-agent-id="close-exercise-search"
                  onClick={() => {
                    setIsSearchOpen(false);
                    clearAddQuery();
                  }}
                  type="button"
                >
                  <X aria-hidden size={24} strokeWidth={2.3} />
                </button>
              </div>
              <label className="exercise-search__field">
                <span>Exercise search</span>
                <input
                  autoFocus
                  data-agent-id="exercise-search-input"
                  onChange={(event) => handleAddQueryChange(event.target.value)}
                  placeholder="bench press"
                  value={query}
                />
              </label>
              <ExerciseSearchResults
                exercises={addSearchResults}
                onSelect={(exerciseId) => {
                  addExerciseToDay(activeDay, exerciseId);
                  clearAddQuery();
                  setIsSearchOpen(false);
                }}
                resultAgentId={(exerciseId) => `exercise-result-${exerciseId}`}
              />
            </div>
          ) : (
            <Button
              className="builder-panel__add"
              data-agent-id="add-exercise"
              leadingIcon={<Plus aria-hidden size={30} strokeWidth={2.6} />}
              onClick={handleOpenAddSearch}
              variant="outline"
            >
              Add exercise
            </Button>
          )}
        </section>

        <p className="template-builder-hint">{validation.ok ? "Ready to save." : validation.message}</p>
        {saveError ? (
          <p className="template-builder-error" data-agent-id="template-save-error" role="alert">
            {saveError}
          </p>
        ) : null}

        <FlowActionBar
          className="template-builder-actions"
          leftAction={{
            agentId: "template-builder-back",
            label: "Back",
            leadingIcon: <ArrowLeft aria-hidden size={28} strokeWidth={2.4} />,
            onClick: () => {
              void navigate("/templates/new/days-per-week");
            },
          }}
          rightAction={{
            agentId: "save-template",
            disabled: !canSave,
            label: "Save",
            leadingIcon: <Save aria-hidden size={24} strokeWidth={2.4} />,
            onClick: () => {
              void handleSave();
            },
          }}
        />
      </section>
    </main>
  );
}

function SortableExerciseRow({
  editQuery,
  editResults,
  exercise,
  index,
  isEditing,
  onCancelEdit,
  onEdit,
  onEditQueryChange,
  onRemove,
  onReplace,
  sortableId,
}: {
  editQuery: string;
  editResults: ExerciseSummary[];
  exercise: ExerciseSummary;
  index: number;
  isEditing: boolean;
  onCancelEdit: () => void;
  onEdit: () => void;
  onEditQueryChange: (value: string) => void;
  onRemove: () => void;
  onReplace: (exerciseId: number) => void;
  sortableId: string;
}) {
  const { attributes, isDragging, listeners, setNodeRef, transform, transition } = useSortable({ id: sortableId });
  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
  };
  const rowClassName = isDragging
    ? "builder-exercise-row-shell builder-exercise-row-shell--dragging"
    : "builder-exercise-row-shell";

  return (
    <div className={rowClassName} ref={setNodeRef} style={style}>
      <div className="builder-exercise-row" data-agent-id={`template-exercise-${index + 1}`}>
        <button
          aria-label={`Drag ${exercise.name}`}
          className="builder-exercise-row__order"
          data-agent-id={`template-exercise-drag-${index + 1}`}
          type="button"
          {...attributes}
          {...listeners}
        >
          <GripVertical aria-hidden size={18} strokeWidth={2.4} />
          <span>{index + 1}</span>
        </button>
        <span className="builder-exercise-row__text">
          <strong>{exercise.name}</strong>
          <small>
            {exercise.primaryMuscleName} - {exercise.equipmentName}
          </small>
        </span>
        <span className="builder-exercise-row__actions">
          <button
            aria-label={`Edit ${exercise.name}`}
            className="builder-icon-button"
            data-agent-id={`edit-template-exercise-${index + 1}`}
            onClick={onEdit}
            type="button"
          >
            <Pencil aria-hidden size={23} strokeWidth={2.2} />
          </button>
          <button
            aria-label={`Remove ${exercise.name}`}
            className="builder-icon-button"
            data-agent-id={`remove-template-exercise-${index + 1}`}
            onClick={onRemove}
            type="button"
          >
            <Trash2 aria-hidden size={24} strokeWidth={2.2} />
          </button>
        </span>
      </div>

      {isEditing ? (
        <div className="exercise-search exercise-search--inline" data-agent-id={`edit-exercise-panel-${index + 1}`}>
          <div className="exercise-search__top">
            <h3>Edit exercise</h3>
            <button
              aria-label="Close exercise edit"
              className="builder-icon-button"
              data-agent-id={`close-edit-exercise-${index + 1}`}
              onClick={onCancelEdit}
              type="button"
            >
              <X aria-hidden size={24} strokeWidth={2.3} />
            </button>
          </div>
          <label className="exercise-search__field">
            <span>Exercise search</span>
            <input
              autoFocus
              data-agent-id={`edit-exercise-search-input-${index + 1}`}
              onChange={(event) => onEditQueryChange(event.target.value)}
              placeholder="bench press"
              value={editQuery}
            />
          </label>
          <ExerciseSearchResults
            exercises={editResults}
            onSelect={onReplace}
            resultAgentId={(exerciseId) => `replace-exercise-result-${exerciseId}`}
          />
        </div>
      ) : null}
    </div>
  );
}

function ExerciseSearchResults({ exercises, onSelect, resultAgentId }: ExerciseSearchResultsProps) {
  if (exercises.length === 0) {
    return null;
  }

  return (
    <div className="exercise-search__results">
      {exercises.map((exercise) => (
        <button
          className="exercise-result"
          data-agent-id={resultAgentId(exercise.id)}
          key={exercise.id}
          onClick={() => onSelect(exercise.id)}
          type="button"
        >
          <strong>{exercise.name}</strong>
          <span>
            {exercise.primaryMuscleName} - {exercise.equipmentName}
          </span>
        </button>
      ))}
    </div>
  );
}

function buildSortableId(day: number, index: number): string {
  return `day-${day}-exercise-${index}`;
}

function mergeExercises(currentExercises: ExerciseSummary[], nextExercises: ExerciseSummary[]): ExerciseSummary[] {
  const exercisesById = new Map(currentExercises.map((exercise) => [exercise.id, exercise]));

  for (const exercise of nextExercises) {
    exercisesById.set(exercise.id, exercise);
  }

  return [...exercisesById.values()];
}
