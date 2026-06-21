import {
  BarChart3,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  Grid3X3,
} from "lucide-react";
import type { CSSProperties, ReactNode } from "react";
import { useEffect, useMemo, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { loadSetVolumeReport } from "../../../application/analytics/loadSetVolumeReport";
import { useServices } from "../../../app/useServices";
import {
  addRange,
  clampPeriodStart,
  classifyWeeklySetVolume,
  getDefaultPeriodStart,
  getPeriodNavigationBounds,
  isSetVisualizationRange,
  isSetVisualizationView,
  parsePeriodStart,
  serializePeriodStart,
  setVisualizationRanges,
  setVolumeBandLabels,
  setVolumeBandOrder,
  type SetVisualizationRange,
  type SetVisualizationView,
  type SetVolumeBand,
  type SetVolumeMuscleRow,
  type SetVolumeReport,
} from "../../../domain/analytics/TrainingAnalytics";
import "./DataVisualizationPage.css";

type LoadState =
  | { status: "loading"; requestKey: string; report: null; error: null }
  | { status: "ready"; requestKey: string; report: SetVolumeReport; error: null }
  | { status: "error"; requestKey: string; report: null; error: string };

const rangeLabels: Record<SetVisualizationRange, string> = {
  week: "Week",
  month: "Month",
  quarter: "Quarter",
  year: "Year",
};

const viewOptions: Array<{ value: SetVisualizationView; label: string; icon: ReactNode }> = [
  { value: "bars", label: "Bars", icon: <BarChart3 aria-hidden size={16} strokeWidth={2.4} /> },
  { value: "heatmap", label: "Heatmap", icon: <Grid3X3 aria-hidden size={16} strokeWidth={2.4} /> },
];

const volumeBandClassNames: Record<SetVolumeBand, string> = {
  "not-ideal": "visualization-volume-band--not-ideal",
  maintaining: "visualization-volume-band--maintaining",
  growth: "visualization-volume-band--growth",
  "max-growth": "visualization-volume-band--max-growth",
  overtraining: "visualization-volume-band--overtraining",
};

const storedViewKey = "powerjack.visualization.view";
const chartPickerCloseMs = 140;

export function DataVisualizationPage() {
  const services = useServices();
  const [searchParams, setSearchParams] = useSearchParams();
  const now = useMemo(() => new Date(), []);
  const range = parseRange(searchParams.get("range"));
  const view = parseView(searchParams.get("view"), getStoredVisualizationView());
  const periodStart = useMemo(
    () => parsePeriodStart(searchParams.get("start"), range, now),
    [now, range, searchParams],
  );
  const navigationBounds = useMemo(() => getPeriodNavigationBounds(range, now), [now, range]);
  const canShowPreviousPeriod = periodStart > navigationBounds.minStart;
  const canShowNextPeriod = periodStart < navigationBounds.maxStart;
  const periodStartKey = serializePeriodStart(periodStart);
  const requestKey = `${range}:${periodStartKey}`;
  const [loadState, setLoadState] = useState<LoadState>({
    status: "loading",
    requestKey: "",
    report: null,
    error: null,
  });
  const [isChartMenuOpen, setIsChartMenuOpen] = useState(false);
  const [shouldRenderChartPicker, setShouldRenderChartPicker] = useState(false);

  useEffect(() => {
    let isMounted = true;

    void loadSetVolumeReport(
      {
        periodStart: periodStartKey,
        range,
      },
      services.analytics,
    )
      .then((report) => {
        if (isMounted) {
          setLoadState({ status: "ready", requestKey, report, error: null });
        }
      })
      .catch((error: unknown) => {
        console.error("Failed to load training analytics", error);

        if (isMounted) {
          setLoadState({
            status: "error",
            requestKey,
            report: null,
            error: error instanceof Error ? error.message : "Training data could not be loaded.",
          });
        }
      });

    return () => {
      isMounted = false;
    };
  }, [periodStartKey, range, requestKey, services.analytics]);

  useEffect(() => {
    if (!isChartMenuOpen) {
      return undefined;
    }

    function handleKeyDown(event: KeyboardEvent): void {
      if (event.key === "Escape") {
        setIsChartMenuOpen(false);
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isChartMenuOpen]);

  function updateVisualizationParams(next: {
    range?: SetVisualizationRange;
    view?: SetVisualizationView;
    periodStart?: Date;
  }): void {
    if (next.view) {
      storeVisualizationView(next.view);
    }

    const nextRange = next.range ?? range;
    const nextPeriodStart =
      next.periodStart ?? (next.range && next.range !== range ? getDefaultPeriodStart(nextRange, now) : periodStart);
    const clampedPeriodStart = clampPeriodStart(nextRange, nextPeriodStart, now);
    const params = new URLSearchParams();
    params.set("range", nextRange);
    params.set("view", next.view ?? view);
    params.set("start", serializePeriodStart(clampedPeriodStart));
    setSearchParams(params);
  }

  const isCurrentLoad = loadState.requestKey === requestKey;
  const report = isCurrentLoad ? loadState.report : null;
  const status = isCurrentLoad ? loadState.status : "loading";
  const hasCurrentData = report ? report.totalCompletedSets > 0 : false;

  useEffect(() => {
    if (hasCurrentData) {
      const expandTimeout = window.setTimeout(() => {
        setShouldRenderChartPicker(true);
      }, 0);

      return () => window.clearTimeout(expandTimeout);
    }

    const closeMenuTimeout = window.setTimeout(() => {
      setIsChartMenuOpen(false);
    }, 0);
    const collapseTimeout = window.setTimeout(() => {
      setShouldRenderChartPicker(false);
    }, chartPickerCloseMs);

    return () => {
      window.clearTimeout(closeMenuTimeout);
      window.clearTimeout(collapseTimeout);
    };
  }, [hasCurrentData]);

  return (
    <main className="app-screen visualization-screen" data-agent-id="data-visualization-page">
      <section className="app-flow visualization-flow" aria-labelledby="data-visualization-title">
        <div className="visualization-header">
          <div>
            <p>Progress</p>
            <h1 id="data-visualization-title">Sets by muscle group</h1>
          </div>
        </div>

        <div className="visualization-control-stack" data-agent-id="visualization-controls">
          <SegmentedControl
            agentPrefix="visualization-range"
            label="Time range"
            onChange={(nextRange) => updateVisualizationParams({ range: nextRange })}
            options={setVisualizationRanges.map((item) => ({
              value: item,
              label: rangeLabels[item],
            }))}
            value={range}
          />

          <div className={hasCurrentData ? "visualization-toolbar visualization-toolbar--with-chart" : "visualization-toolbar"}>
            <div className="visualization-period-nav">
              {canShowPreviousPeriod ? (
                <button
                  aria-label={`Show previous ${range}`}
                  data-agent-id="visualization-previous-period"
                  onClick={() => updateVisualizationParams({ periodStart: addRange(periodStart, range, -1) })}
                  type="button"
                >
                  <ChevronLeft aria-hidden size={22} strokeWidth={2.4} />
                </button>
              ) : (
                <span className="visualization-period-nav__spacer" data-agent-id="visualization-previous-period-boundary" />
              )}
              <strong data-agent-id="visualization-period-label">
                {report?.periodLabel ?? rangeLabels[range]}
              </strong>
              {canShowNextPeriod ? (
                <button
                  aria-label={`Show next ${range}`}
                  data-agent-id="visualization-next-period"
                  onClick={() => updateVisualizationParams({ periodStart: addRange(periodStart, range, 1) })}
                  type="button"
                >
                  <ChevronRight aria-hidden size={22} strokeWidth={2.4} />
                </button>
              ) : (
                <span className="visualization-period-nav__spacer" data-agent-id="visualization-next-period-boundary" />
              )}
            </div>

            {shouldRenderChartPicker ? (
              <div
                aria-hidden={!hasCurrentData}
                className={
                  hasCurrentData
                    ? "visualization-chart-slot visualization-chart-slot--expanded"
                    : "visualization-chart-slot"
                }
              >
                <ChartTypePicker
                  isDisabled={!hasCurrentData}
                  isOpen={isChartMenuOpen}
                  onOpenChange={setIsChartMenuOpen}
                  onSelect={(nextView) => updateVisualizationParams({ view: nextView })}
                  value={view}
                />
              </div>
            ) : null}
          </div>
        </div>

        {status === "loading" ? (
          <div className="visualization-status" data-agent-id="visualization-loading">
            Loading training data
          </div>
        ) : null}

        {status === "error" ? (
          <div className="visualization-status visualization-status--error" data-agent-id="visualization-error" role="alert">
            {loadState.error}
          </div>
        ) : null}

        {report ? (
          <VisualizationContent report={report} view={view} />
        ) : null}
      </section>
    </main>
  );
}

function VisualizationContent({
  report,
  view,
}: {
  report: SetVolumeReport;
  view: SetVisualizationView;
}) {
  const hasData = report.totalCompletedSets > 0;

  return (
    <section className={hasData ? "visualization-panel" : "visualization-panel visualization-panel--empty"} data-agent-id={`visualization-${view}`}>
      {hasData ? (
        <>
          <ChartHeader report={report} />
          <ChartByView report={report} view={view} />
        </>
      ) : (
        <div className="visualization-empty" data-agent-id="visualization-empty-state">
          <h2>No completed sets in {report.periodLabel}</h2>
          <p>Complete a workout to see muscle volume.</p>
        </div>
      )}
    </section>
  );
}

function ChartByView({
  report,
  view,
}: {
  report: SetVolumeReport;
  view: SetVisualizationView;
}) {
  switch (view) {
    case "bars":
      return <BarsChart report={report} />;
    case "heatmap":
      return <HeatmapChart report={report} />;
  }
}

function BarsChart({ report }: { report: SetVolumeReport }) {
  const rows = getCurrentRows(report);
  const max = Math.max(...rows.map((row) => row.metricValue), 1);

  return (
    <>
      <div className="bars-list">
        {rows.map((row) => {
          const band = classifyWeeklySetVolume(row.metricValue);
          const bandLabel = setVolumeBandLabels[band];

          return (
            <div
              aria-label={`${row.muscleName}, ${formatMetricValue(row.metricValue)} ${report.metricUnitLabel}, ${bandLabel}`}
              className="bars-row"
              data-agent-id={`visualization-bar-${row.muscleId}`}
              data-volume-band={band}
              key={row.muscleId}
              role="group"
            >
              <span>{row.muscleName}</span>
              <div className="bars-row__track" aria-hidden>
                <span
                  className={volumeBandClassNames[band]}
                  style={{ width: `${(row.metricValue / max) * 100}%` }}
                />
              </div>
              <strong>{formatMetricValue(row.metricValue)}</strong>
            </div>
          );
        })}
      </div>
      <VolumeBandLegend agentPrefix="visualization-bar" />
      <p className="visualization-note">{formatMetricNote(report)}</p>
    </>
  );
}

function HeatmapChart({ report }: { report: SetVolumeReport }) {
  const rows = getCurrentRows(report);
  const gridStyle = {
    "--bucket-count": report.buckets.length.toString(),
  } as CSSProperties & Record<"--bucket-count", string>;

  return (
    <>
      <div className="heatmap-grid" style={gridStyle}>
        <span className="heatmap-grid__corner" />
        {report.buckets.map((bucket) => (
          <span className="heatmap-grid__label" key={bucket.key} title={bucket.label}>
            {bucket.shortLabel}
          </span>
        ))}
        <span className="heatmap-grid__label">All</span>
        {rows.map((row) => (
          <HeatmapRow key={row.muscleId} report={report} row={row} />
        ))}
      </div>
      <VolumeBandLegend agentPrefix="visualization-heatmap" />
      <p className="visualization-note">Cells use the volume guidance colors for each bucket.</p>
    </>
  );
}

function HeatmapRow({
  report,
  row,
}: {
  report: SetVolumeReport;
  row: SetVolumeMuscleRow;
}) {
  const totalBand = classifyWeeklySetVolume(row.metricValue);

  return (
    <>
      <span className="heatmap-grid__muscle">{row.muscleName}</span>
      {row.bucketValues.map((value, index) => {
        const bucket = report.buckets[index];
        const band = classifyWeeklySetVolume(value);

        return (
          <span
            aria-label={`${row.muscleName}, ${bucket?.label ?? "bucket"}: ${formatMetricValue(value)} ${report.metricUnitLabel}, ${setVolumeBandLabels[band]}`}
            className={`heatmap-cell ${volumeBandClassNames[band]}`}
            data-volume-band={band}
            key={`${row.muscleId}-${index}`}
          >
            {value > 0 ? formatMetricValue(value) : "-"}
          </span>
        );
      })}
      <span
        aria-label={`${row.muscleName} total: ${formatMetricValue(row.metricValue)} ${report.metricUnitLabel}, ${setVolumeBandLabels[totalBand]}`}
        className={`heatmap-cell heatmap-cell--total ${volumeBandClassNames[totalBand]}`}
        data-volume-band={totalBand}
      >
        {formatMetricValue(row.metricValue)}
      </span>
    </>
  );
}

function VolumeBandLegend({ agentPrefix }: { agentPrefix: string }) {
  return (
    <div className="visualization-volume-legend" data-agent-id={`${agentPrefix}-legend`} aria-label="Volume guidance legend">
      {setVolumeBandOrder.map((band) => (
        <span data-agent-id={`${agentPrefix}-legend-${band}`} key={band}>
          <i className={`visualization-volume-legend__swatch ${volumeBandClassNames[band]}`} aria-hidden />
          {setVolumeBandLabels[band]}
        </span>
      ))}
    </div>
  );
}

function getCurrentRows(report: SetVolumeReport): SetVolumeMuscleRow[] {
  return report.rows.filter((row) => row.metricValue > 0);
}

function ChartTypePicker({
  isDisabled,
  isOpen,
  onOpenChange,
  onSelect,
  value,
}: {
  isDisabled: boolean;
  isOpen: boolean;
  onOpenChange: (isOpen: boolean) => void;
  onSelect: (value: SetVisualizationView) => void;
  value: SetVisualizationView;
}) {
  const selectedOption = viewOptions.find((option) => option.value === value) ?? viewOptions[0];

  function selectView(nextView: SetVisualizationView): void {
    onSelect(nextView);
    onOpenChange(false);
  }

  return (
    <div className="visualization-chart-picker">
      <button
        aria-expanded={isOpen}
        aria-haspopup="menu"
        className="visualization-chart-trigger"
        data-agent-id="visualization-chart-trigger"
        disabled={isDisabled}
        onClick={() => onOpenChange(!isOpen)}
        type="button"
      >
        {selectedOption.icon}
        <span>{selectedOption.label}</span>
        <ChevronDown aria-hidden size={16} strokeWidth={2.4} />
      </button>

      {isOpen && !isDisabled ? (
        <>
          <button
            aria-label="Close chart type menu"
            className="visualization-chart-backdrop"
            data-agent-id="visualization-view-menu-backdrop"
            onClick={() => onOpenChange(false)}
            type="button"
          />
          <div className="visualization-chart-menu" data-agent-id="visualization-view-menu" role="menu">
            {viewOptions.map((option) => (
              <button
                aria-checked={value === option.value}
                className={value === option.value ? "visualization-chart-menu__item is-selected" : "visualization-chart-menu__item"}
                data-agent-id={`visualization-view-${option.value}`}
                key={option.value}
                onClick={() => selectView(option.value)}
                role="menuitemradio"
                type="button"
              >
                {option.icon}
                <span>{option.label}</span>
              </button>
            ))}
          </div>
        </>
      ) : null}
    </div>
  );
}

function SegmentedControl<TValue extends string>({
  agentPrefix,
  label,
  onChange,
  options,
  value,
}: {
  agentPrefix: string;
  label: string;
  onChange: (value: TValue) => void;
  options: Array<{ value: TValue; label: string; icon?: ReactNode }>;
  value: TValue;
}) {
  return (
    <fieldset className="visualization-segmented">
      <legend className="sr-only">{label}</legend>
      {options.map((option) => (
        <button
          aria-pressed={value === option.value}
          className={value === option.value ? "visualization-segmented__button is-selected" : "visualization-segmented__button"}
          data-agent-id={`${agentPrefix}-${option.value}`}
          key={option.value}
          onClick={() => onChange(option.value)}
          type="button"
        >
          {option.icon}
          {option.label}
        </button>
      ))}
    </fieldset>
  );
}

function ChartHeader({ report }: { report: SetVolumeReport }) {
  return (
    <div className="visualization-panel__header">
      <div>
        <span>{report.metricLabel}</span>
        <h2>{report.periodLabel}</h2>
      </div>
      <div className="visualization-panel__metric">
        <strong data-agent-id="visualization-total">{formatMetricValue(report.metricValue)}</strong>
        <small>{report.metricUnitLabel}</small>
      </div>
    </div>
  );
}

function parseRange(value: string | null): SetVisualizationRange {
  return isSetVisualizationRange(value) ? value : "week";
}

function parseView(value: string | null, fallback: SetVisualizationView): SetVisualizationView {
  return isSetVisualizationView(value) ? value : fallback;
}

function getStoredVisualizationView(): SetVisualizationView {
  if (typeof window === "undefined") {
    return "bars";
  }

  try {
    const storedValue = window.localStorage.getItem(storedViewKey);
    return isSetVisualizationView(storedValue) ? storedValue : "bars";
  } catch {
    return "bars";
  }
}

function storeVisualizationView(value: SetVisualizationView): void {
  try {
    window.localStorage.setItem(storedViewKey, value);
  } catch {
    // URL state remains the source of truth when storage is unavailable.
  }
}

function formatMetricValue(value: number): string {
  if (value > 0 && value < 0.1) {
    return "<0.1";
  }

  return new Intl.NumberFormat("en-US", {
    maximumFractionDigits: 1,
    minimumFractionDigits: 1,
  }).format(value);
}

function formatMetricNote(report: SetVolumeReport): string {
  if (report.range === "week") {
    return "Uses completed logged sets only.";
  }

  return "Values are normalized to average completed sets per week.";
}
