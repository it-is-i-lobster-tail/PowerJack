import { ChevronRight, Plus } from "lucide-react";
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { loadProgramList } from "../../../application/programs/loadProgramList";
import { useServices } from "../../../app/useServices";
import {
  programListFilters,
  type ProgramListFilter,
  type ProgramListItem,
} from "../../../domain/programs/ProgramList";
import type { PowerJackStatus } from "../../../domain/status";
import { useStartProgramStore } from "../../start-program/state/startProgramStore";
import "./ProgramListPage.css";

type LoadState =
  | { status: "loading"; programs: ProgramListItem[]; error: null }
  | { status: "ready"; programs: ProgramListItem[]; error: null }
  | { status: "error"; programs: ProgramListItem[]; error: string };

const filterLabels: Record<ProgramListFilter, string> = {
  all: "All",
  completed: "Completed",
  halted: "Halted",
};

const statusLabels: Record<PowerJackStatus, string> = {
  planned: "Planned",
  active: "Active",
  completed: "Completed",
  halted: "Halted",
  skipped: "Skipped",
};

const monthLabels = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

export function ProgramListPage() {
  const services = useServices();
  const navigate = useNavigate();
  const resetProgramDraft = useStartProgramStore((state) => state.reset);
  const [filter, setFilter] = useState<ProgramListFilter>("all");
  const [loadState, setLoadState] = useState<LoadState>({
    status: "loading",
    programs: [],
    error: null,
  });

  useEffect(() => {
    let ignore = false;

    void loadProgramList(filter, {
      appState: services.appState,
      programs: services.programs,
    })
      .then((view) => {
        if (!ignore) {
          setLoadState({ status: "ready", programs: view.programs, error: null });
        }
      })
      .catch((error: unknown) => {
        console.error("Failed to load program list", error);

        if (!ignore) {
          setLoadState({
            status: "error",
            programs: [],
            error: error instanceof Error ? error.message : "Could not load programs.",
          });
        }
      });

    return () => {
      ignore = true;
    };
  }, [filter, services.appState, services.programs]);

  function handleStartProgram(): void {
    resetProgramDraft();
    void navigate("/start/select-template");
  }

  return (
    <main className="app-screen app-screen--scrollable program-list-screen" data-agent-id="program-list-page">
      <section className="app-flow program-list-flow" aria-labelledby="program-list-title">
        <header className="program-list-header">
          <div>
            <h1 id="program-list-title">Programs</h1>
            <p>{filter === "all" ? "All programs" : `${filterLabels[filter]} programs`} &middot; Newest first</p>
          </div>
          <button
            aria-label="Start new program"
            className="program-list-add-button"
            data-agent-id="program-list-new-program"
            onClick={handleStartProgram}
            type="button"
          >
            <Plus aria-hidden size={26} strokeWidth={2.3} />
          </button>
        </header>

        <div className="program-list-filters" aria-label="Program filters" role="group">
          {programListFilters.map((item) => (
            <button
              aria-pressed={filter === item}
              className={filter === item ? "program-list-filter program-list-filter--active" : "program-list-filter"}
              data-agent-id={`program-filter-${item}`}
              key={item}
              onClick={() => setFilter(item)}
              type="button"
            >
              {filterLabels[item]}
            </button>
          ))}
        </div>

        {loadState.status === "loading" ? (
          <p className="program-list-status" data-agent-id="program-list-loading">
            Loading programs
          </p>
        ) : null}

        {loadState.status === "error" ? (
          <p className="program-list-status program-list-status--error" data-agent-id="program-list-error" role="alert">
            {loadState.error}
          </p>
        ) : null}

        {loadState.status === "ready" && loadState.programs.length === 0 ? (
          <section className="program-list-empty" data-agent-id="program-list-empty-state">
            <h2>No programs yet</h2>
            <p>Start a program from a saved template.</p>
            <button onClick={handleStartProgram} type="button">
              Start
            </button>
          </section>
        ) : null}

        {loadState.programs.length > 0 ? (
          <div className="program-card-list" data-agent-id="program-card-list">
            {loadState.programs.map((program) => (
              <ProgramCard key={program.id} program={program} />
            ))}
          </div>
        ) : null}
      </section>
    </main>
  );
}

function ProgramCard({ program }: { program: ProgramListItem }) {
  const navigate = useNavigate();
  const visibleFocusMuscles = program.focusMuscles.slice(0, 3);
  const hiddenFocusCount = Math.max(program.focusMuscles.length - visibleFocusMuscles.length, 0);

  return (
    <article
      className={
        program.isCurrentProgram
          ? "program-card program-card--current"
          : `program-card program-card--${program.status}`
      }
      data-agent-id={`program-card-${program.id}`}
    >
      <div className="program-card__top">
        <div className="program-card__title-group">
          <h2>{program.name}</h2>
          <p>{formatProgramDateLine(program)}</p>
          {program.isCurrentProgram ? <strong>Current program</strong> : null}
        </div>
        <StatusBadge status={program.status} />
      </div>

      <div className="program-card__progress">
        <div className="program-card__progress-track" aria-hidden>
          <span
            className={`program-card__progress-bar program-card__progress-bar--${program.status}`}
            style={{ width: `${program.progressPercent}%` }}
          />
        </div>
        <span>{program.progressPercent}%</span>
      </div>

      <dl className="program-card__details">
        <div>
          <dt>Template</dt>
          <dd>{program.templateName}</dd>
        </div>
        <div>
          <dt>Focus</dt>
          <dd className="program-card__focus-list">
            {visibleFocusMuscles.map((muscle) => (
              <span className="program-card__focus-chip" key={muscle.id}>
                {muscle.name}
              </span>
            ))}
            {hiddenFocusCount > 0 ? <span className="program-card__focus-chip">+{hiddenFocusCount}</span> : null}
          </dd>
        </div>
      </dl>

      <button
        aria-label={`Open ${program.name}`}
        className="program-card__details-button"
        data-agent-id={`program-card-details-${program.id}`}
        onClick={() => {
          void navigate(`/programs/${program.id}`);
        }}
        type="button"
      >
        <ChevronRight aria-hidden size={24} strokeWidth={2.5} />
      </button>
    </article>
  );
}

function StatusBadge({ status }: { status: PowerJackStatus }) {
  return (
    <span className={`program-card-status program-card-status--${status}`}>
      <i aria-hidden />
      {statusLabels[status]}
    </span>
  );
}

function formatProgramDateLine(program: ProgramListItem): string {
  if (program.status === "active") {
    return `Started ${formatProgramDate(program.createdAt)}`;
  }

  if (program.status === "completed" || program.status === "halted") {
    return formatProgramDateRange(program.createdAt, program.updatedAt);
  }

  return formatProgramDate(program.createdAt);
}

function formatProgramDateRange(startValue: string, endValue: string): string {
  const start = readDateParts(startValue);
  const end = readDateParts(endValue);

  if (!start || !end) {
    return `${startValue} - ${endValue}`;
  }

  if (start.year === end.year && start.month === end.month) {
    return `${monthLabels[start.month - 1]} ${start.day} - ${end.day}, ${end.year}`;
  }

  if (start.year === end.year) {
    return `${monthLabels[start.month - 1]} ${start.day} - ${monthLabels[end.month - 1]} ${end.day}, ${end.year}`;
  }

  return `${formatProgramDate(startValue)} - ${formatProgramDate(endValue)}`;
}

function formatProgramDate(value: string): string {
  const parts = readDateParts(value);

  if (!parts) {
    return value;
  }

  return `${monthLabels[parts.month - 1]} ${parts.day}, ${parts.year}`;
}

function readDateParts(value: string): { year: number; month: number; day: number } | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);

  if (!match) {
    return null;
  }

  return {
    year: Number(match[1]),
    month: Number(match[2]),
    day: Number(match[3]),
  };
}
