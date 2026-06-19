import { createBrowserRouter } from "react-router-dom";
import { AppShell } from "./AppShell";
import { HomePage } from "../features/start-program/pages/HomePage";
import { SelectTemplatePage } from "../features/start-program/pages/SelectTemplatePage";
import { ProgramLengthPage } from "../features/start-program/pages/ProgramLengthPage";
import { DaysPerWeekPage } from "../features/start-program/pages/DaysPerWeekPage";
import { TemplateNamePage } from "../features/templates/pages/TemplateNamePage";
import { TemplateMuscleFocusPage } from "../features/templates/pages/TemplateMuscleFocusPage";
import { TemplateDaysPerWeekPage } from "../features/templates/pages/TemplateDaysPerWeekPage";
import { TemplateBuilderPage } from "../features/templates/pages/TemplateBuilderPage";
import { ActiveWorkoutRedirectPage } from "../features/workouts/pages/ActiveWorkoutRedirectPage";
import { WorkoutViewerPage } from "../features/workouts/pages/WorkoutViewerPage";

export function createAppRouter() {
  return createBrowserRouter([
    {
      path: "/",
      element: <AppShell />,
      children: [
        {
          index: true,
          element: <HomePage />,
        },
        {
          path: "start/select-template",
          element: <SelectTemplatePage />,
        },
        {
          path: "start/program-length",
          element: <ProgramLengthPage />,
        },
        {
          path: "start/days-per-week",
          element: <DaysPerWeekPage />,
        },
        {
          path: "templates/new/name",
          element: <TemplateNamePage />,
        },
        {
          path: "templates/new/muscle-focus",
          element: <TemplateMuscleFocusPage />,
        },
        {
          path: "templates/new/days-per-week",
          element: <TemplateDaysPerWeekPage />,
        },
        {
          path: "templates/new/builder",
          element: <TemplateBuilderPage />,
        },
        {
          path: "workouts/active",
          element: <ActiveWorkoutRedirectPage />,
        },
        {
          path: "programs/:programId/workouts/:workoutId",
          element: <WorkoutViewerPage />,
        },
      ],
    },
  ]);
}
