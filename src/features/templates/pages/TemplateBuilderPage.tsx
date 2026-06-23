import {
  DndContext,
  KeyboardSensor,
  MouseSensor,
  TouchSensor,
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
import { ArrowLeft, Copy as CopyIcon, Pencil, Plus, Save, Trash2, X } from "lucide-react";
import { useEffect, useMemo, useState, type CSSProperties } from "react";
import { Navigate, useNavigate } from "react-router-dom";
import { listExerciseSummariesByIds } from "../../../application/exercises/listExerciseSummariesByIds";
import { searchExercises } from "../../../application/exercises/searchExercises";
import { saveTemplate, updateTemplate } from "../../../application/templates/saveTemplate";
import { useServices } from "../../../app/useServices";
import type { ExerciseSummary } from "../../../domain/exercises/Exercise";
import { validateTemplateDraft } from "../../../domain/templates/rules/validateTemplateDraft";
import { ExerciseSearchOverlay } from "../../exercises/components/ExerciseSearchOverlay";
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

type ReorderState = "idle" | "moving";
type DndIdentifier = string | number;
type DndAnnouncementEvent = {
  active: { id: DndIdentifier };
  over?: { id: DndIdentifier } | null;
};

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
  const exerciseRowIdsByDay = useTemplateDraftStore((state) => state.exerciseRowIdsByDay);
  const setActiveDay = useTemplateDraftStore((state) => state.setActiveDay);
  const addExerciseToDay = useTemplateDraftStore((state) => state.addExerciseToDay);
  const copyExercisesToDay = useTemplateDraftStore((state) => state.copyExercisesToDay);
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
  const [copySourceDay, setCopySourceDay] = useState<number | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const sensors = useSensors(
    useSensor(MouseSensor, {
      activationConstraint: {
        distance: 8,
      },
    }),
    useSensor(TouchSensor, {
      activationConstraint: {
        delay: 180,
        tolerance: 8,
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
  const currentExerciseRowIds = useMemo(
    () => exerciseRowIdsByDay[activeDay] ?? [],
    [activeDay, exerciseRowIdsByDay],
  );
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
    const sortableId = currentExerciseRowIds[index];

    if (!exercise || !sortableId) {
      return [];
    }

    return [
      {
        exercise,
        index,
        sortableId,
      },
    ];
  });
  const sortableIds = currentExerciseItems.map((item) => item.sortableId);
  const sortableItemsById = useMemo(
    () => new Map(currentExerciseItems.map((item) => [item.sortableId, item])),
    [currentExerciseItems],
  );
  const isHydratingCurrentExercises =
    currentExerciseIds.length > 0 && currentExerciseItems.length < currentExerciseIds.length;
  const validation = validateTemplateDraft(toDraft());
  const canSave = validation.ok && !isSaving;
  const dragAnnouncements = useMemo(
    () => ({
      onDragStart({ active }: DndAnnouncementEvent) {
        const activeId = String(active.id);
        return `${getExerciseAnnouncementName(activeId, sortableItemsById)} picked up at position ${getSortablePosition(
          activeId,
          sortableIds,
        )} of ${sortableIds.length}.`;
      },
      onDragOver({ active, over }: DndAnnouncementEvent) {
        if (!over || active.id === over.id) {
          return undefined;
        }

        const activeId = String(active.id);
        const overId = String(over.id);
        return `${getExerciseAnnouncementName(activeId, sortableItemsById)} moving to position ${getSortablePosition(
          overId,
          sortableIds,
        )} of ${sortableIds.length}.`;
      },
      onDragEnd({ active, over }: DndAnnouncementEvent) {
        const activeId = String(active.id);

        if (!over) {
          return `${getExerciseAnnouncementName(activeId, sortableItemsById)} dropped.`;
        }

        const overId = String(over.id);
        return `${getExerciseAnnouncementName(activeId, sortableItemsById)} moved to position ${getSortablePosition(
          overId,
          sortableIds,
        )} of ${sortableIds.length}.`;
      },
      onDragCancel({ active }: DndAnnouncementEvent) {
        return `${getExerciseAnnouncementName(String(active.id), sortableItemsById)} reorder cancelled.`;
      },
    }),
    [sortableIds, sortableItemsById],
  );

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
    const activeId = String(active.id);
    const overId = over ? String(over.id) : null;

    if (!overId || activeId === overId) {
      return;
    }

    const fromIndex = sortableIds.indexOf(activeId);
    const toIndex = sortableIds.indexOf(overId);

    if (fromIndex >= 0 && toIndex >= 0) {
      reorderExerciseInDay(activeDay, fromIndex, toIndex);
      setEditingIndex(null);
      clearEditQuery();
    }
  }

  function handleOpenAddSearch(): void {
    setEditingIndex(null);
    clearEditQuery();
    setCopySourceDay(null);
    setIsSearchOpen(true);
  }

  function handleOpenEdit(index: number): void {
    setIsSearchOpen(false);
    clearAddQuery();
    setCopySourceDay(null);
    setEditingIndex(index);
    clearEditQuery();
  }

  function handleSetActiveDay(day: number): void {
    setEditingIndex(null);
    clearEditQuery();
    setIsSearchOpen(false);
    clearAddQuery();
    setCopySourceDay(null);
    setActiveDay(day);
  }

  function handleOpenCopyDay(): void {
    if (currentExerciseIds.length === 0) {
      return;
    }

    setEditingIndex(null);
    clearEditQuery();
    setIsSearchOpen(false);
    clearAddQuery();
    setCopySourceDay(activeDay);
  }

  function handleCopyDay(targetDay: number): void {
    if (copySourceDay === null) {
      return;
    }

    copyExercisesToDay(copySourceDay, targetDay);
    setCopySourceDay(null);
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

  const isBuilderScrollable = isSearchOpen || currentExerciseIds.length > 0;
  const builderScreenClassName = isBuilderScrollable
    ? "app-screen app-screen--scrollable template-builder-screen"
    : "app-screen template-builder-screen";

  return (
    <main className={builderScreenClassName} data-agent-id="template-builder-page">
      <section className="app-flow template-builder-flow" aria-labelledby="template-builder-title">
        <header className="template-builder-header">
          <p>{editingTemplateId ? "Edit template" : "New template"}</p>
          <h1 data-agent-id="template-builder-title-text" id="template-builder-title">
            {name.trim()}
          </h1>
          <span>{workoutsPerWeek} days per week</span>
          {isHydratingCurrentExercises || isSearchOpen ? null : (
            <Button
              aria-label="Add exercise"
              className="template-builder-header__add"
              data-agent-id="add-exercise"
              leadingIcon={<Plus aria-hidden size={24} strokeWidth={2.8} />}
              onClick={handleOpenAddSearch}
              variant="outline"
            >
              exercise
            </Button>
          )}
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
            <div className="builder-panel__header-actions">
              {currentExerciseIds.length > 0 ? (
                <button
                  aria-label={`Copy Day ${activeDay} exercises`}
                  className="builder-panel__copy"
                  data-agent-id="template-day-copy"
                  onClick={handleOpenCopyDay}
                  type="button"
                >
                  <CopyIcon aria-hidden size={20} strokeWidth={2.2} />
                  <span>Copy exercises</span>
                </button>
              ) : null}
              <span>
                {currentExerciseIds.length} {currentExerciseIds.length === 1 ? "exercise" : "exercises"}
              </span>
            </div>
          </div>

          {currentExerciseIds.length === 0 ? (
            <p className="builder-panel__empty">No exercises yet.</p>
          ) : isHydratingCurrentExercises ? (
            <p className="builder-panel__empty" data-agent-id="template-exercises-loading">
              Loading exercises...
            </p>
          ) : (
            <DndContext
              accessibility={{
                announcements: dragAnnouncements,
                screenReaderInstructions: {
                  draggable:
                    "To reorder an exercise, press space or enter. Use the arrow keys to move it, then press space or enter again to drop it.",
                },
              }}
              collisionDetection={closestCenter}
              onDragEnd={handleDragEnd}
              sensors={sensors}
            >
              <SortableContext items={sortableIds} strategy={verticalListSortingStrategy}>
                <div className="builder-exercise-list">
                  {currentExerciseItems.map(({ exercise, index, sortableId }) => (
                    <SortableExerciseRow
                      exercise={exercise}
                      exerciseCount={currentExerciseItems.length}
                      index={index}
                      key={sortableId}
                      onEdit={() => handleOpenEdit(index)}
                      onRemove={() => {
                        removeExerciseFromDay(activeDay, index);
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

        </section>

        {copySourceDay !== null ? (
          <CopyDayModal
            dayCount={workoutsPerWeek}
            onCancel={() => setCopySourceDay(null)}
            onCopy={handleCopyDay}
            sourceDay={copySourceDay}
          />
        ) : null}

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

      {isSearchOpen ? (
        <ExerciseSearchOverlay
          closeAgentId="close-exercise-search"
          closeLabel="Close exercise search"
          inputAgentId="exercise-search-input"
          onClose={() => {
            setIsSearchOpen(false);
            clearAddQuery();
          }}
          onQueryChange={handleAddQueryChange}
          onSelectExercise={(exercise) => {
            addExerciseToDay(activeDay, exercise.id);
            clearAddQuery();
            setIsSearchOpen(false);
          }}
          query={query}
          resultAgentId={(exerciseId) => `exercise-result-${exerciseId}`}
          results={addSearchResults}
          title="Exercise search"
        />
      ) : null}

      {editingIndex !== null ? (
        <ExerciseSearchOverlay
          closeAgentId={`close-edit-exercise-${editingIndex + 1}`}
          closeLabel="Close exercise edit"
          inputAgentId={`edit-exercise-search-input-${editingIndex + 1}`}
          onClose={() => {
            setEditingIndex(null);
            clearEditQuery();
          }}
          onQueryChange={handleEditQueryChange}
          onSelectExercise={(exercise) => {
            replaceExerciseInDay(activeDay, editingIndex, exercise.id);
            setEditingIndex(null);
            clearEditQuery();
          }}
          query={editQuery}
          resultAgentId={(exerciseId) => `replace-exercise-result-${exerciseId}`}
          results={editSearchResults}
          title="Exercise search"
        />
      ) : null}
    </main>
  );
}

function CopyDayModal({
  dayCount,
  onCancel,
  onCopy,
  sourceDay,
}: {
  dayCount: number;
  onCancel: () => void;
  onCopy: (targetDay: number) => void;
  sourceDay: number;
}) {
  const targetDays = Array.from({ length: dayCount }, (_, index) => index + 1).filter((day) => day !== sourceDay);

  return (
    <div className="copy-day-modal-overlay" role="presentation">
      <section
        aria-describedby="copy-day-modal-description"
        aria-labelledby="copy-day-modal-title"
        aria-modal="true"
        className="copy-day-modal"
        data-agent-id="copy-day-modal"
        role="dialog"
      >
        <button
          aria-label="Cancel copy"
          className="copy-day-modal__close"
          data-agent-id="copy-day-cancel"
          onClick={onCancel}
          type="button"
        >
          <X aria-hidden size={20} strokeWidth={2.4} />
        </button>
        <div className="copy-day-modal__header">
          <h2 id="copy-day-modal-title">Copy exercises to what day?</h2>
          <p id="copy-day-modal-description">Replaces all exercise for selected day.</p>
        </div>
        <div className="copy-day-modal__targets" aria-label="Copy target days">
          {targetDays.map((day) => (
            <button
              className="copy-day-modal__target"
              data-agent-id={`copy-day-target-${day}`}
              key={day}
              onClick={() => onCopy(day)}
              type="button"
            >
              Day {day}
            </button>
          ))}
        </div>
      </section>
    </div>
  );
}

function SortableExerciseRow({
  exercise,
  exerciseCount,
  index,
  onEdit,
  onRemove,
  sortableId,
}: {
  exercise: ExerciseSummary;
  exerciseCount: number;
  index: number;
  onEdit: () => void;
  onRemove: () => void;
  sortableId: string;
}) {
  const { attributes, isDragging, listeners, setActivatorNodeRef, setNodeRef, transform, transition } = useSortable({
    id: sortableId,
    transition: {
      duration: 160,
      easing: "cubic-bezier(0.2, 0, 0, 1)",
    },
  });
  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
  };
  const reorderState: ReorderState = isDragging ? "moving" : "idle";
  const rowClassName = [
    "builder-exercise-row-shell",
    isDragging ? "builder-exercise-row-shell--dragging" : null,
    reorderState === "moving" ? "builder-exercise-row-shell--moving" : null,
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <div className={rowClassName} ref={setNodeRef} style={style}>
      <div
        className="builder-exercise-row"
        data-agent-id={`template-exercise-${index + 1}`}
        data-reorder-state={reorderState}
      >
        <button
          aria-label={`Reorder ${exercise.name}, position ${index + 1} of ${exerciseCount}`}
          className="builder-exercise-row__drag-zone"
          data-agent-id={`template-exercise-drag-${index + 1}`}
          ref={setActivatorNodeRef}
          type="button"
          {...attributes}
          {...listeners}
        >
          <span className="builder-exercise-row__order" aria-hidden="true">
            {index + 1}
          </span>
          <span className="builder-exercise-row__text">
            <strong>{exercise.name}</strong>
            <small>
              {exercise.primaryMuscleName} - {exercise.equipmentName}
            </small>
          </span>
        </button>
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

    </div>
  );
}

function mergeExercises(currentExercises: ExerciseSummary[], nextExercises: ExerciseSummary[]): ExerciseSummary[] {
  const exercisesById = new Map(currentExercises.map((exercise) => [exercise.id, exercise]));

  for (const exercise of nextExercises) {
    exercisesById.set(exercise.id, exercise);
  }

  return [...exercisesById.values()];
}

function getSortablePosition(sortableId: string, sortableIds: string[]): number {
  const index = sortableIds.indexOf(sortableId);
  return index >= 0 ? index + 1 : 1;
}

function getExerciseAnnouncementName(
  sortableId: string,
  sortableItemsById: Map<string, BuilderExerciseItem>,
): string {
  return sortableItemsById.get(sortableId)?.exercise.name ?? "Exercise";
}
