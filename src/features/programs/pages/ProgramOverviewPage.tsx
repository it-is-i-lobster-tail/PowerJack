import { Activity, BarChart3, CalendarDays, Clock3, Target } from "lucide-react";
import type { CSSProperties, ReactNode } from "react";
import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import {
  loadProgramOverview,
  type ProgramOverviewView,
} from "../../../application/programs/loadProgramOverview";
import { useServices } from "../../../app/useServices";
import {
  buildProgramOverviewSegments,
  type ActiveProgramOverviewScheduleCell,
  type ProgramOverviewSegment,
} from "../../../domain/programs/ProgramOverview";
import type { PowerJackStatus } from "../../../domain/status";
import "./ProgramOverviewPage.css";

type LoadState =
  | { status: "loading"; programId: number | null; view: null; error: null }
  | { status: "ready"; programId: number; view: ProgramOverviewView; error: null }
  | { status: "error"; programId: number; view: null; error: string };

const segmentClassNames: Record<ProgramOverviewSegment["status"], string> = {
  complete: "program-schedule-cell__segment--complete",
  skipped: "program-schedule-cell__segment--skipped",
  halted: "program-schedule-cell__segment--halted",
};

export function ProgramOverviewPage() {
  const services = useServices();
  const navigate = useNavigate();
  const params = useParams();
  const [loadState, setLoadState] = useState<LoadState>({
    status: "loading",
    programId: null,
    view: null,
    error: null,
  });
  const programId = Number(params.programId);

  useEffect(() => {
    let ignore = false;

    if (!Number.isInteger(programId)) {
      void navigate("/", { replace: true });
      return () => {
        ignore = true;
      };
    }

    void loadProgramOverview(programId, {
      appState: services.appState,
      programs: services.programs,
      analytics: services.analytics,
    })
      .then((view) => {
        if (ignore) {
          return;
        }

        if (!view) {
          void navigate("/", { replace: true });
          return;
        }

        setLoadState({ status: "ready", programId, view, error: null });
      })
      .catch((error: unknown) => {
        console.error("Failed to load program overview", error);

        if (!ignore) {
          setLoadState({
            status: "error",
            programId,
            view: null,
            error: error instanceof Error ? error.message : "Could not load program.",
          });
        }
      });

    return () => {
      ignore = true;
    };
  }, [navigate, programId, services.analytics, services.appState, services.programs]);

  return (
    <main className="app-screen program-overview-screen" data-agent-id="current-program-page">
      <section className="app-flow program-overview-flow" aria-labelledby="program-overview-title">
        {loadState.programId !== programId || loadState.status === "loading" ? (
          <p className="program-overview-status" data-agent-id="program-overview-loading">
            Loading program
          </p>
        ) : null}

        {loadState.programId === programId && loadState.status === "error" ? (
          <p className="program-overview-status program-overview-status--error" data-agent-id="program-overview-error" role="alert">
            {loadState.error}
          </p>
        ) : null}

        {loadState.programId === programId && loadState.view ? (
          <ProgramOverviewContent view={loadState.view} />
        ) : null}
      </section>
    </main>
  );
}

function ProgramOverviewContent({ view }: { view: ProgramOverviewView }) {
  return (
    <>
      <header className="program-overview-hero">
        <h1 id="program-overview-title">{view.program.name}</h1>
        <p className={view.program.status === "active" ? "program-status program-status--active" : "program-status"}>
          {formatStatus(view.program.status)}
        </p>
      </header>

      <ProgramSummary view={view} />
      <ProgramSchedule view={view} />
      <ProgramVolume view={view} />
    </>
  );
}

function ProgramSummary({ view }: { view: ProgramOverviewView }) {
  return (
    <section className="program-panel program-summary" data-agent-id="program-summary" aria-label="Program summary">
      <SummaryMetric
        icon={<CalendarDays aria-hidden size={28} strokeWidth={2.2} />}
        label="Template"
        value={view.program.templateName}
      />
      <SummaryMetric
        icon={<Clock3 aria-hidden size={28} strokeWidth={2.2} />}
        label="Length"
        value={`${view.program.programLengthWeeks} weeks`}
      />
      <div className="program-summary__metric">
        <Activity aria-hidden size={28} strokeWidth={2.2} />
        <div>
          <span>Progress</span>
          <strong data-agent-id="program-progress">{view.program.progressPercent}%</strong>
          <div className="program-progress-bar" aria-hidden>
            <span style={{ width: `${view.program.progressPercent}%` }} />
          </div>
        </div>
      </div>
      <div className="program-summary__metric">
        <Target aria-hidden size={28} strokeWidth={2.2} />
        <div>
          <span>Focus</span>
          <div className="program-focus-chip-list">
            {view.program.focusMuscles.map((muscle) => (
              <span className="program-focus-chip" data-agent-id={`program-focus-muscle-${muscle.id}`} key={muscle.id}>
                {muscle.name}
              </span>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}

function SummaryMetric({
  icon,
  label,
  value,
}: {
  icon: ReactNode;
  label: string;
  value: string;
}) {
  return (
    <div className="program-summary__metric">
      {icon}
      <div>
        <span>{label}</span>
        <strong>{value}</strong>
      </div>
    </div>
  );
}

function ProgramSchedule({ view }: { view: ProgramOverviewView }) {
  const scheduleStyle = {
    "--program-days": view.program.workoutsPerWeek.toString(),
  } as CSSProperties & Record<"--program-days", string>;
  const weeks = Array.from({ length: view.program.programLengthWeeks }, (_, index) => index + 1);
  const days = Array.from({ length: view.program.workoutsPerWeek }, (_, index) => index + 1);

  return (
    <section className="program-panel program-schedule" data-agent-id="program-schedule" aria-labelledby="program-schedule-title">
      <div className="program-panel__header">
        <CalendarDays aria-hidden size={22} strokeWidth={2.2} />
        <h2 id="program-schedule-title">Program schedule</h2>
      </div>

      <div className="program-schedule-grid" style={scheduleStyle}>
        <span className="program-schedule-grid__corner" aria-hidden />
        {days.map((day) => (
          <span className="program-schedule-grid__heading" key={day}>
            Day {day}
          </span>
        ))}
        {weeks.map((week) => (
          <ProgramScheduleWeek key={week} week={week} days={days} schedule={view.schedule} />
        ))}
      </div>

      <div className="program-schedule-legend" aria-label="Schedule legend">
        <LegendItem className="program-schedule-legend__dot--active" label="Active" />
        <LegendItem className="program-schedule-legend__dot--complete" label="Complete" />
        <LegendItem className="program-schedule-legend__dot--skipped" label="Skipped" />
        <LegendItem className="program-schedule-legend__dot--halted" label="Halted" />
      </div>
    </section>
  );
}

function ProgramScheduleWeek({
  days,
  schedule,
  week,
}: {
  days: number[];
  schedule: ActiveProgramOverviewScheduleCell[];
  week: number;
}) {
  return (
    <>
      <span className="program-schedule-grid__week">Wk {week}</span>
      {days.map((day) => {
        const cell = schedule.find((item) => item.week === week && item.day === day);

        return cell ? <ProgramScheduleCell cell={cell} key={`${week}-${day}`} /> : null;
      })}
    </>
  );
}

function ProgramScheduleCell({ cell }: { cell: ActiveProgramOverviewScheduleCell }) {
  const completePercent =
    cell.totalSets > 0 ? Math.round((cell.statusCounts.complete / cell.totalSets) * 100) : 0;
  const segments = buildProgramOverviewSegments(cell);
  let segmentOffset = 0;

  return (
    <div
      aria-label={scheduleCellLabel(cell)}
      className={cell.isActive ? "program-schedule-cell program-schedule-cell--active" : "program-schedule-cell"}
      data-agent-id={`program-schedule-cell-w${cell.week}-d${cell.day}`}
      role="img"
    >
      {!cell.isActive
        ? segments.map((segment) => {
            const style = {
              left: `${segmentOffset}%`,
              width: `${segment.widthPercent}%`,
            };
            segmentOffset += segment.widthPercent;

            return (
              <span
                aria-hidden
                className={`program-schedule-cell__segment ${segmentClassNames[segment.status]}`}
                key={segment.status}
                style={style}
              />
            );
          })
        : null}
      <span className="program-schedule-cell__label">
        {cell.isActive ? "Active" : completePercent > 0 ? `${completePercent}%` : "-"}
      </span>
    </div>
  );
}

function ProgramVolume({ view }: { view: ProgramOverviewView }) {
  const maxVolume = Math.max(...view.volumeRows.map((row) => row.averageSetsPerWeek), 1);

  return (
    <section className="program-panel program-volume" data-agent-id="program-volume" aria-labelledby="program-volume-title">
      <div className="program-panel__header program-volume__header">
        <BarChart3 aria-hidden size={22} strokeWidth={2.2} />
        <div>
          <h2 id="program-volume-title">Volume tracking</h2>
          <p>Avg weekly sets by muscle group</p>
        </div>
      </div>

      {view.volumeRows.length > 0 ? (
        <div className="program-volume-list">
          {view.volumeRows.map((row) => (
            <div className="program-volume-row" data-agent-id={`program-volume-row-${row.muscleId}`} key={row.muscleId}>
              <div className="program-volume-row__label">
                <strong>{row.muscleName}</strong>
                {row.isFocusMuscle ? <span>Focus</span> : null}
              </div>
              <div className="program-volume-row__track" aria-hidden>
                <span
                  className={row.isFocusMuscle ? "program-volume-row__bar program-volume-row__bar--focus" : "program-volume-row__bar"}
                  style={{ width: `${(row.averageSetsPerWeek / maxVolume) * 100}%` }}
                />
              </div>
              <div className="program-volume-row__value">
                <strong>{formatAverageSets(row.averageSetsPerWeek)}</strong>
                <span>sets/wk</span>
              </div>
            </div>
          ))}
        </div>
      ) : (
        <p className="program-volume-empty" data-agent-id="program-volume-empty">
          No completed sets yet.
        </p>
      )}
    </section>
  );
}

function LegendItem({ className, label }: { className: string; label: string }) {
  return (
    <span>
      <i className={className} aria-hidden />
      {label}
    </span>
  );
}

function scheduleCellLabel(cell: ActiveProgramOverviewScheduleCell): string {
  if (cell.isActive) {
    return `Week ${cell.week}, day ${cell.day}, active workout`;
  }

  return [
    `Week ${cell.week}, day ${cell.day}`,
    `${cell.statusCounts.complete} complete`,
    `${cell.statusCounts.skipped} skipped`,
    `${cell.statusCounts.halted} halted`,
    `${cell.statusCounts.planned + cell.statusCounts.active} planned`,
  ].join(", ");
}

function formatStatus(status: PowerJackStatus): string {
  return status.charAt(0).toUpperCase() + status.slice(1);
}

function formatAverageSets(value: number): string {
  return new Intl.NumberFormat("en-US", {
    maximumFractionDigits: 1,
    minimumFractionDigits: 1,
  }).format(value);
}
