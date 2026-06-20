import { expect, test } from "@playwright/test";

async function openTemplateFocus(page: import("@playwright/test").Page, name = "Back In Action") {
  await page.goto("/start/select-template");
  await page.locator("[data-agent-id='add-template']").click();
  await page.locator("[data-agent-id='template-name-input']").fill(name);
  await page.locator("[data-agent-id='template-name-next']").click();
  await expect(page).toHaveURL(/\/templates\/new\/muscle-focus$/);
}

async function selectFocusAndOpenDays(page: import("@playwright/test").Page) {
  await page.locator(".muscle-focus-grid").getByRole("button", { name: "Back" }).click();
  await page.locator(".muscle-focus-grid").getByRole("button", { name: "Biceps" }).click();
  await page.locator("[data-agent-id='template-muscle-focus-next']").click();
}

async function createTwoDayTemplate(page: import("@playwright/test").Page, name = "Back In Action") {
  await openTemplateFocus(page, name);
  await selectFocusAndOpenDays(page);
  await page.locator("[data-agent-id='template-days-per-week-2']").click();
  await page.locator("[data-agent-id='template-days-per-week-next']").click();
  await page.locator("[data-agent-id='add-exercise']").click();
  await page.locator("[data-agent-id='exercise-search-input']").fill("bench");
  await page.getByRole("button", { name: /Barbell Bench Press/ }).click();
  await page.locator("[data-agent-id='template-day-2']").click();
  await page.locator("[data-agent-id='add-exercise']").click();
  await page.locator("[data-agent-id='exercise-search-input']").fill("squat");
  await page.getByRole("button", { name: /Barbell Back Squat/ }).click();
  await page.locator("[data-agent-id='save-template']").click();
  await expect(page).toHaveURL(/\/start\/select-template$/);
}

async function startSelectedProgram(page: import("@playwright/test").Page, weeks = 8) {
  await page.locator("[data-agent-id='select-template-next']").click();
  await expect(page).toHaveURL(/\/start\/program-length$/);
  await page.locator(`[data-agent-id='program-length-${weeks}']`).click();
  await page.locator("[data-agent-id='program-length-next']").click();
  await expect(page).toHaveURL(/\/programs\/\d+\/workouts\/\d+$/);
}

async function completeVisibleWorkout(page: import("@playwright/test").Page) {
  const firstRep = page.locator("[data-agent-id^='set-reps-']").nth(0);
  const firstWeight = page.locator("[data-agent-id^='set-weight-']").nth(0);
  const secondRep = page.locator("[data-agent-id^='set-reps-']").nth(1);
  const secondWeight = page.locator("[data-agent-id^='set-weight-']").nth(1);

  await firstRep.fill("12");
  await firstWeight.fill("220");
  await secondRep.fill("10");
  await secondWeight.fill("220");
  await expect(page.locator("[data-agent-id='workout-set-summary']")).toContainText("2 of 2 sets logged");
  await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toBeVisible();
  await page.locator("[data-agent-id='feedback-pain-option-1']").click();
  await page.locator("[data-agent-id='feedback-effort-option-3']").click();
  await page.locator("[data-agent-id='feedback-save']").click();
  await expect(page.locator("[data-agent-id='finish-workout']")).toBeVisible();
  await page.locator("[data-agent-id='finish-workout']").click();
  await expect(page.locator("[data-agent-id='workout-day-title']")).toContainText("Day 2");
}

async function expectResumeCenteredBeforeIcons(page: import("@playwright/test").Page) {
  const resume = page.locator("[data-agent-id='resume-workout']");
  const profile = page.locator("[data-agent-id='profile-placeholder']");
  const menu = page.locator("[data-agent-id='app-menu-toggle']");

  await expect(resume).toBeVisible();

  const viewport = page.viewportSize();
  const resumeBox = await resume.boundingBox();
  const profileBox = await profile.boundingBox();
  const menuBox = await menu.boundingBox();

  expect(viewport).not.toBeNull();
  expect(resumeBox).not.toBeNull();
  expect(profileBox).not.toBeNull();
  expect(menuBox).not.toBeNull();

  if (viewport && resumeBox && profileBox && menuBox) {
    const resumeCenter = resumeBox.x + resumeBox.width / 2;
    expect(Math.abs(resumeCenter - viewport.width / 2)).toBeLessThanOrEqual(12);
    expect(resumeBox.x + resumeBox.width).toBeLessThan(profileBox.x);
    expect(profileBox.x + profileBox.width).toBeLessThan(menuBox.x);
  }
}

async function pageHasHorizontalOverflow(page: import("@playwright/test").Page): Promise<boolean> {
  return page.evaluate(() => {
    const documentElement = document.documentElement;
    return (
      documentElement.scrollWidth > documentElement.clientWidth ||
      document.body.scrollWidth > document.body.clientWidth
    );
  });
}

test.describe("start program flow", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/");
    await page.evaluate(async () => {
      const harness = window as unknown as {
        __POWERJACK_AGENT__?: {
          reset(): Promise<void>;
        };
      };
      await harness.__POWERJACK_AGENT__?.reset();
    });
  });

  test("renders the New Program screen at /", async ({ page }) => {
    await page.goto("/");

    await expect(page.locator("[data-agent-id='app-top-bar']")).toBeVisible();
    await expect(page.locator("[data-agent-id='profile-placeholder']")).toBeVisible();
    await expect(page.locator("[data-agent-id='app-menu-toggle']")).toBeVisible();
    await expect(page.locator("[data-agent-id='resume-workout']")).toHaveCount(0);
    await expect(page.getByRole("heading", { name: "New Program" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Start new program" })).toBeVisible();
    await expect(page.locator("[data-agent-id='new-program-page']")).toBeVisible();
  });

  test("Start navigates to empty Select Template", async ({ page }) => {
    await page.goto("/");
    await page.getByRole("button", { name: "Start new program" }).click();

    await expect(page).toHaveURL(/\/start\/select-template$/);
    await expect(page.getByRole("heading", { name: "Select Template" })).toBeVisible();
    await expect(page.locator("[data-agent-id='template-empty-state']")).toBeVisible();
    await expect(page.locator("[data-agent-id='add-template']")).toBeVisible();
    await expect(page.locator("[data-agent-id='select-template-back']")).toBeVisible();
    await expect(page.locator("[data-agent-id='select-template-next']")).toBeVisible();
    await expect(page.locator("[data-agent-id='select-template-next']")).toBeDisabled();
  });

  test("Add Template opens the template naming flow", async ({ page }) => {
    await page.goto("/start/select-template");
    await page.locator("[data-agent-id='add-template']").click();

    await expect(page).toHaveURL(/\/templates\/new\/name$/);
    await expect(page.getByRole("heading", { name: "Name Template" })).toBeVisible();
    await expect(page.locator("[data-agent-id='template-name-input']")).toHaveAttribute(
      "placeholder",
      "My New Template",
    );
    await expect(page.locator("[data-agent-id='template-name-next']")).toBeDisabled();
  });

  test("Name Template enforces the 64 character limit", async ({ page }) => {
    await page.goto("/start/select-template");
    await page.locator("[data-agent-id='add-template']").click();
    await page.locator("[data-agent-id='template-name-input']").fill("A".repeat(65));

    await expect(page.locator("[data-agent-id='template-name-count']")).toContainText("65/64");
    await expect(page.locator("[data-agent-id='template-name-next']")).toBeDisabled();

    await page.locator("[data-agent-id='template-name-input']").fill("A".repeat(64));

    await expect(page.locator("[data-agent-id='template-name-count']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='template-name-next']")).toBeEnabled();
  });

  test("Muscle Group Focus requires one to four selected muscles", async ({ page }) => {
    await openTemplateFocus(page);

    await expect(page.getByRole("heading", { name: "Muscle Group Focus" })).toBeVisible();
    await expect(page.locator("[data-agent-id='template-focus-counter']")).toContainText("0/4");
    await expect(page.locator("[data-agent-id='template-muscle-focus-next']")).toBeDisabled();

    const muscleGrid = page.locator(".muscle-focus-grid");

    await muscleGrid.getByRole("button", { name: "Back" }).click();
    await expect(page.locator("[data-agent-id='template-focus-counter']")).toContainText("1/4");
    await expect(page.locator("[data-agent-id='template-muscle-focus-next']")).toBeEnabled();

    await muscleGrid.getByRole("button", { name: "Back" }).click();
    await expect(page.locator("[data-agent-id='template-focus-counter']")).toContainText("0/4");
    await expect(page.locator("[data-agent-id='template-muscle-focus-next']")).toBeDisabled();

    for (const muscle of ["Back", "Biceps", "Calves", "Chest"]) {
      await muscleGrid.getByRole("button", { name: muscle }).click();
    }

    await expect(page.locator("[data-agent-id='template-focus-counter']")).toContainText("4/4");
    await muscleGrid.getByRole("button", { name: "Core" }).click();
    await expect(page.locator("[data-agent-id='template-focus-counter']")).toContainText("4/4");
    await expect(muscleGrid.getByRole("button", { name: "Core" })).toHaveAttribute("aria-pressed", "false");
  });

  test("new template saves only after every day has an exercise", async ({ page }) => {
    await openTemplateFocus(page);
    await selectFocusAndOpenDays(page);
    await page.locator("[data-agent-id='template-days-per-week-2']").click();
    await page.locator("[data-agent-id='template-days-per-week-next']").click();

    await expect(page).toHaveURL(/\/templates\/new\/builder$/);
    await expect(page.locator("[data-agent-id='template-builder-back']")).toBeVisible();
    await expect(page.locator("[data-agent-id='save-template']")).toBeVisible();
    await expect(page.locator("[data-agent-id='save-template']")).toBeDisabled();

    await page.locator("[data-agent-id='add-exercise']").click();
    await expect(page.locator("[data-agent-id^='exercise-result-']")).toHaveCount(0);
    await page.locator("[data-agent-id='exercise-search-input']").fill("bench");
    await page.getByRole("button", { name: /Barbell Bench Press/ }).click();
    await expect(page.locator("[data-agent-id='save-template']")).toBeDisabled();

    await page.locator("[data-agent-id='template-day-2']").click();
    await page.locator("[data-agent-id='add-exercise']").click();
    await page.locator("[data-agent-id='exercise-search-input']").fill("squat");
    await page.getByRole("button", { name: /Barbell Back Squat/ }).click();
    await expect(page.locator("[data-agent-id='save-template']")).toBeEnabled();
    await page.locator("[data-agent-id='save-template']").click();

    await expect(page).toHaveURL(/\/start\/select-template$/);
    await expect(page.locator("[data-agent-id='template-row-1']")).toContainText("Back In Action");
    await expect(page.locator("[data-agent-id='template-focus-chip-1']")).toContainText("Back");
    await expect(page.locator("[data-agent-id='template-focus-chip-2']")).toContainText("Biceps");
    await expect(page.locator("[data-agent-id='template-row-1']")).toHaveAttribute("aria-selected", "true");
  });

  test("top chrome menu opens and navigates to new flows", async ({ page }) => {
    await page.goto("/");
    await page.locator("[data-agent-id='app-menu-toggle']").click();

    await expect(page.locator("[data-agent-id='app-menu']")).toBeVisible();
    await page.locator("[data-agent-id='menu-data-visualization']").click();
    await expect(page).toHaveURL(/\/visualization$/);
    await expect(page.locator("[data-agent-id='visualization-empty-state']")).toBeVisible();
    await expect(page.locator("[data-agent-id='visualization-chart-trigger']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='data-visualization-page']")).not.toContainText(/No change vs/i);

    await page.locator("[data-agent-id='app-menu-toggle']").click();
    await page.locator("[data-agent-id='menu-new-template']").click();
    await expect(page).toHaveURL(/\/templates\/new\/name$/);
    await expect(page.locator("[data-agent-id='app-top-bar']")).toBeVisible();

    await page.locator("[data-agent-id='app-menu-toggle']").click();
    await page.locator("[data-agent-id='menu-new-program']").click();
    await expect(page).toHaveURL(/\/start\/select-template$/);

    await page.locator("[data-agent-id='app-menu-toggle']").click();
    await expect(page.locator("[data-agent-id='app-menu']")).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(page.locator("[data-agent-id='app-menu']")).toHaveCount(0);
  });

  test("Data Visualization shows completed set volume and switches chart types", async ({ page }) => {
    await createTwoDayTemplate(page, "Chart Check");
    await startSelectedProgram(page);
    await completeVisibleWorkout(page);

    await page.locator("[data-agent-id='app-menu-toggle']").click();
    await page.locator("[data-agent-id='menu-data-visualization']").click();

    await expect(page).toHaveURL(/\/visualization/);
    await expect(page.locator("[data-agent-id='data-visualization-page']")).toBeVisible();
    await expect(page.getByRole("heading", { name: "Sets by muscle group" })).toBeVisible();
    await expect(page.locator("[data-agent-id='visualization-total']")).toContainText("2");
    await expect(page.locator("[data-agent-id^='visualization-bar-']")).toContainText("Chest");

    await page.locator("[data-agent-id='visualization-chart-trigger']").click();
    await page.locator("[data-agent-id='visualization-view-heatmap']").click();
    await expect(page.locator("[data-agent-id='visualization-heatmap']")).toContainText("Chest");

    await page.locator("[data-agent-id='visualization-chart-trigger']").click();
    await page.locator("[data-agent-id='visualization-view-sparklines']").click();
    await expect(page.locator("[data-agent-id^='visualization-sparkline-']")).toContainText("Chest");
    await expect(page.locator("[data-agent-id='visualization-chart-trigger']")).toContainText("Sparklines");

    await page.locator("[data-agent-id='visualization-chart-trigger']").click();
    await page.locator("[data-agent-id='visualization-view-compare']").click();
    await expect(page.locator("[data-agent-id^='visualization-compare-']")).toContainText("Chest");
    await expect(page.locator("[data-agent-id='visualization-summary-compare']")).toBeVisible();

    await page.locator("[data-agent-id='visualization-range-year']").click();
    await expect(page.locator("[data-agent-id='visualization-period-label']")).toContainText(
      new Date().getFullYear().toString(),
    );
    await expect(page.locator("[data-agent-id='visualization-chart-trigger']")).toContainText("Compare");
  });

  test("Current Program menu opens overview and keeps resume context", async ({ page }, testInfo) => {
    await createTwoDayTemplate(page, "Overview Check");
    await startSelectedProgram(page, 8);

    const dayOneUrl = page.url();

    await page.locator("[data-agent-id='app-menu-toggle']").click();
    await page.locator("[data-agent-id='menu-current-program']").click();

    await expect(page).toHaveURL(/\/programs\/\d+$/);
    await expect(page.locator("[data-agent-id='current-program-page']")).toBeVisible();
    await expect(page.getByRole("heading", { name: "Overview Check x1" })).toBeVisible();
    await expect(page.locator("[data-agent-id='program-progress']")).toContainText("0%");
    await expect(page.locator("[data-agent-id='program-schedule-cell-w1-d1']")).toContainText("Active");
    await expect(page.locator("[data-agent-id='program-schedule-cell-w8-d2']")).toContainText("-");
    await expect(page.locator("[data-agent-id='resume-workout']")).toBeVisible();
    expect(await pageHasHorizontalOverflow(page)).toBe(false);

    await page.locator("[data-agent-id='resume-workout']").click();
    await expect(page).toHaveURL(dayOneUrl);

    await completeVisibleWorkout(page);

    await page.locator("[data-agent-id='app-menu-toggle']").click();
    await page.locator("[data-agent-id='menu-current-program']").click();

    await expect(page).toHaveURL(/\/programs\/\d+$/);
    await expect(page.locator("[data-agent-id='program-progress']")).toContainText("6%");
    await expect(page.locator("[data-agent-id='program-schedule-cell-w1-d1']")).toContainText("100%");
    await expect(page.locator("[data-agent-id='program-schedule-cell-w1-d2']")).toContainText("Active");
    await expect(page.locator("[data-agent-id^='program-volume-row-']")).toContainText("Chest");
    expect(await pageHasHorizontalOverflow(page)).toBe(false);

    if (testInfo.project.name === "mobile-chrome") {
      await page.evaluate(() => window.scrollTo(0, 0));
      await expect(page).toHaveScreenshot("current-program-overview-mobile.png", {
        animations: "disabled",
        fullPage: true,
      });
    }
  });

  test("template edit pre-populates the flow and delete soft-removes unused templates", async ({ page }) => {
    await createTwoDayTemplate(page, "Manage Me");

    await page.locator("[data-agent-id='edit-template-1']").click();
    await expect(page).toHaveURL(/\/templates\/new\/name$/);
    await expect(page.locator("[data-agent-id='template-name-input']")).toHaveValue("Manage Me");
    await page.locator("[data-agent-id='template-name-input']").fill("Managed Template");
    await page.locator("[data-agent-id='template-name-next']").click();
    await expect(page.locator("[data-agent-id='template-focus-counter']")).toContainText("2/4");
    await page.locator("[data-agent-id='template-muscle-focus-next']").click();
    await expect(page.locator("[data-agent-id='template-days-per-week-2']")).toHaveAttribute("aria-checked", "true");
    await page.locator("[data-agent-id='template-days-per-week-next']").click();
    await expect(page.locator("[data-agent-id='template-exercise-1']")).toContainText("Barbell Bench Press");
    await page.locator("[data-agent-id='save-template']").click();

    await expect(page).toHaveURL(/\/start\/select-template$/);
    await expect(page.locator("[data-agent-id='template-row-1']")).toContainText("Managed Template");
    await expect(page.locator("[data-agent-id='template-row-2']")).toHaveCount(0);

    await page.locator("[data-agent-id='delete-template-1']").click();
    await expect(page.locator("[data-agent-id='template-delete-confirmation']")).toContainText(
      "Confirm Deleting Template Managed Template",
    );
    await page.locator("[data-agent-id='modal-delete']").click();
    await expect(page.locator("[data-agent-id='template-empty-state']")).toBeVisible();
    await expect(page.locator("[data-agent-id='template-row-1']")).toHaveCount(0);
  });

  test("saved template starts a program and opens the active workout", async ({ page }) => {
    await openTemplateFocus(page);
    await selectFocusAndOpenDays(page);
    await page.locator("[data-agent-id='template-days-per-week-2']").click();
    await page.locator("[data-agent-id='template-days-per-week-next']").click();
    await page.locator("[data-agent-id='add-exercise']").click();
    await page.locator("[data-agent-id='exercise-search-input']").fill("bench");
    await page.getByRole("button", { name: /Barbell Bench Press/ }).click();
    await page.locator("[data-agent-id='template-day-2']").click();
    await page.locator("[data-agent-id='add-exercise']").click();
    await page.locator("[data-agent-id='exercise-search-input']").fill("squat");
    await page.getByRole("button", { name: /Barbell Back Squat/ }).click();
    await page.locator("[data-agent-id='save-template']").click();
    await expect(page).toHaveURL(/\/start\/select-template$/);
    await expect(page.locator("[data-agent-id='select-template-next']")).toBeVisible();
    await page.locator("[data-agent-id='select-template-next']").click();

    await expect(page).toHaveURL(/\/start\/program-length$/);
    await expect(page.getByRole("heading", { name: "Program Length in Weeks" })).toBeVisible();
    await page.locator("[data-agent-id='program-length-8']").click();

    await expect(page.locator("[data-agent-id='program-length-next']")).toBeEnabled();
    await expect(page.locator("[data-agent-id='program-length-next']")).toContainText("Start");
    await page.locator("[data-agent-id='program-length-next']").click();

    await expect(page).toHaveURL(/\/programs\/\d+\/workouts\/\d+$/);
    await expect(page.locator("[data-agent-id='active-workout-page']")).toBeVisible();
    await expect(page.locator("[data-agent-id='workout-week-label']")).toContainText("Week 1/8");
    await expect(page.locator("[data-agent-id='workout-day-title']")).toContainText("Day 1");
    await expect(page.locator("[data-agent-id='workout-set-summary']")).toContainText("0 of 2 sets logged");
    await expect(page.getByRole("heading", { name: "Barbell Bench Press" })).toBeVisible();
    await expect(page.locator("[data-agent-id='resume-workout']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id^='set-reps-']")).toHaveCount(2);
    await expect(page.locator("[data-agent-id^='set-weight-']")).toHaveCount(2);

    const canonicalDayOneUrl = page.url();
    await page.evaluate(() => {
      window.history.pushState({}, "", "/workouts/active");
      window.dispatchEvent(new PopStateEvent("popstate"));
    });
    await expect(page).toHaveURL(canonicalDayOneUrl);

    await page.locator("[data-agent-id='workout-day-next']").click();
    await expect(page).toHaveURL(/\/programs\/\d+\/workouts\/\d+$/);
    expect(page.url()).not.toBe(canonicalDayOneUrl);
    await expect(page.locator("[data-agent-id='workout-day-title']")).toContainText("Day 2");
    await expect(page.locator("[data-agent-id='workout-set-summary']")).toContainText("Read-only");
    await expectResumeCenteredBeforeIcons(page);
    await page.locator("[data-agent-id='resume-workout']").click();
    await expect(page).toHaveURL(canonicalDayOneUrl);

    await expect(page.locator("[data-agent-id='workout-day-title']")).toContainText("Day 1");
    await expect(page.locator("[data-agent-id='resume-workout']")).toHaveCount(0);
  });

  test("active program shows resume and replacement confirmation blocks accidental starts", async ({ page }) => {
    await createTwoDayTemplate(page, "Replace Me");
    await startSelectedProgram(page, 8);

    const firstProgramUrl = page.url();
    await expect(page.locator("[data-agent-id='resume-workout']")).toHaveCount(0);

    await page.locator("[data-agent-id='app-menu-toggle']").click();
    await page.locator("[data-agent-id='menu-new-program']").click();
    await expect(page).toHaveURL(/\/start\/select-template$/);
    await expectResumeCenteredBeforeIcons(page);

    await page.locator("[data-agent-id='delete-template-1']").click();
    await expect(page.locator("[data-agent-id='template-in-use-dialog']")).toContainText(
      "Cannot Delete Templates In Use By Active Program",
    );
    await page.locator("[data-agent-id='modal-back']").click();
    await page.locator("[data-agent-id='edit-template-1']").click();
    await expect(page.locator("[data-agent-id='template-in-use-dialog']")).toContainText(
      "Cannot Edit Templates In Use By Active Program",
    );
    await page.locator("[data-agent-id='modal-back']").click();

    await page.locator("[data-agent-id='template-row-1'] .template-row__select").click();
    await page.locator("[data-agent-id='select-template-next']").click();
    await page.locator("[data-agent-id='program-length-4']").click();
    await page.locator("[data-agent-id='program-length-next']").click();
    await expect(page.locator("[data-agent-id='program-replace-confirmation']")).toContainText(
      "Halt Current Program and Start New One",
    );
    await page.locator("[data-agent-id='modal-back']").click();
    await expect(page).toHaveURL(/\/start\/program-length$/);

    await page.locator("[data-agent-id='program-length-next']").click();
    await page.locator("[data-agent-id='modal-confirm']").click();
    await expect(page).toHaveURL(/\/programs\/\d+\/workouts\/\d+$/);
    expect(page.url()).not.toBe(firstProgramUrl);
    await expect(page.locator("[data-agent-id='resume-workout']")).toHaveCount(0);

    await page.locator("[data-agent-id='app-menu-toggle']").click();
    await page.locator("[data-agent-id='menu-new-program']").click();
    await expect(page).toHaveURL(/\/start\/select-template$/);
    await expectResumeCenteredBeforeIcons(page);
    await page.locator("[data-agent-id='resume-workout']").click();
    await expect(page).toHaveURL(/\/programs\/\d+\/workouts\/\d+$/);
    await expect(page.locator("[data-agent-id='resume-workout']")).toHaveCount(0);
  });

  test("template builder reorders and replaces exercises before saving", async ({ page }) => {
    await openTemplateFocus(page, "Builder Control");
    await selectFocusAndOpenDays(page);
    await page.locator("[data-agent-id='template-days-per-week-2']").click();
    await page.locator("[data-agent-id='template-days-per-week-next']").click();

    await page.locator("[data-agent-id='add-exercise']").click();
    await expect(page.locator("[data-agent-id^='exercise-result-']")).toHaveCount(0);
    await page.locator("[data-agent-id='exercise-search-input']").fill("bench");
    await page.getByRole("button", { name: /Barbell Bench Press/ }).click();

    await page.locator("[data-agent-id='add-exercise']").click();
    await expect(page.locator("[data-agent-id^='exercise-result-']")).toHaveCount(0);
    await page.locator("[data-agent-id='exercise-search-input']").fill("squat");
    await page.getByRole("button", { name: /Barbell Back Squat/ }).click();

    await expect(page.locator("[data-agent-id='template-exercise-1']")).toContainText("Barbell Bench Press");
    await expect(page.locator("[data-agent-id='template-exercise-2']")).toContainText("Barbell Back Squat");

    await page.locator("[data-agent-id='edit-template-exercise-1']").click();
    await expect(page.locator("[data-agent-id='edit-exercise-search-input-1']")).toBeVisible();
    await expect(page.locator("[data-agent-id^='replace-exercise-result-']")).toHaveCount(0);
    await page.locator("[data-agent-id='edit-exercise-search-input-1']").fill("pull-up");
    await page.getByRole("button", { name: /^Pull-Up/ }).click();

    await expect(page.locator("[data-agent-id='template-exercise-1']")).toContainText("Pull-Up");
    await expect(page.locator("[data-agent-id='template-exercise-2']")).toContainText("Barbell Back Squat");

    const firstDragHandle = page.locator("[data-agent-id='template-exercise-drag-1']");
    const secondDragHandle = page.locator("[data-agent-id='template-exercise-drag-2']");
    const firstDragBox = await firstDragHandle.boundingBox();
    const secondDragBox = await secondDragHandle.boundingBox();

    expect(firstDragBox).not.toBeNull();
    expect(secondDragBox).not.toBeNull();

    if (firstDragBox && secondDragBox) {
      await page.mouse.move(secondDragBox.x + secondDragBox.width / 2, secondDragBox.y + secondDragBox.height / 2);
      await page.mouse.down();
      await page.mouse.move(secondDragBox.x + secondDragBox.width / 2, secondDragBox.y - 12);
      await page.mouse.move(firstDragBox.x + firstDragBox.width / 2, firstDragBox.y + firstDragBox.height / 2, {
        steps: 12,
      });
      await page.mouse.up();
    }

    await expect(page.locator("[data-agent-id='template-exercise-1']")).toContainText("Barbell Back Squat");
    await expect(page.locator("[data-agent-id='template-exercise-2']")).toContainText("Pull-Up");

    await page.waitForTimeout(200);
    await page.locator("[data-agent-id='template-day-2']").click();
    await expect(page.locator("[data-agent-id='template-day-2']")).toHaveAttribute("aria-selected", "true");
    await page.locator("[data-agent-id='add-exercise']").click();
    await page.locator("[data-agent-id='exercise-search-input']").fill("row");
    await page.getByRole("button", { name: /Barbell Bent-Over Row/ }).click();
    await expect(page.locator("[data-agent-id='template-exercise-1']")).toContainText("Barbell Bent-Over Row");
    await page.locator("[data-agent-id='template-day-1']").click();
    await expect(page.locator("[data-agent-id='template-day-1']")).toHaveAttribute("aria-selected", "true");

    await page.locator("[data-agent-id='save-template']").click();
    await expect(page).toHaveURL(/\/start\/select-template$/);
    await page.locator("[data-agent-id='select-template-next']").click();
    await page.locator("[data-agent-id='program-length-4']").click();
    await page.locator("[data-agent-id='program-length-next']").click();

    await expect(page).toHaveURL(/\/programs\/\d+\/workouts\/\d+$/);
    await expect(page.locator("[data-agent-id^='lift-card-']").nth(0)).toContainText("Barbell Back Squat");
    await expect(page.locator("[data-agent-id^='lift-card-']").nth(1)).toContainText("Pull-Up");
  });

  test("active workout autosaves set values and advances after Finish Workout", async ({ page }) => {
    await openTemplateFocus(page);
    await selectFocusAndOpenDays(page);
    await page.locator("[data-agent-id='template-days-per-week-2']").click();
    await page.locator("[data-agent-id='template-days-per-week-next']").click();
    await page.locator("[data-agent-id='add-exercise']").click();
    await page.locator("[data-agent-id='exercise-search-input']").fill("bench");
    await page.getByRole("button", { name: /Barbell Bench Press/ }).click();
    await page.locator("[data-agent-id='template-day-2']").click();
    await page.locator("[data-agent-id='add-exercise']").click();
    await page.locator("[data-agent-id='exercise-search-input']").fill("squat");
    await page.getByRole("button", { name: /Barbell Back Squat/ }).click();
    await page.locator("[data-agent-id='save-template']").click();
    await page.locator("[data-agent-id='select-template-next']").click();
    await page.locator("[data-agent-id='program-length-8']").click();
    await page.locator("[data-agent-id='program-length-next']").click();
    await expect(page).toHaveURL(/\/programs\/\d+\/workouts\/\d+$/);

    const firstRep = page.locator("[data-agent-id^='set-reps-']").nth(0);
    const firstWeight = page.locator("[data-agent-id^='set-weight-']").nth(0);
    const secondRep = page.locator("[data-agent-id^='set-reps-']").nth(1);
    const secondWeight = page.locator("[data-agent-id^='set-weight-']").nth(1);

    await firstRep.focus();
    await expect(firstRep).toBeFocused();
    const firstSetRow = page.locator("[data-agent-id^='set-row-']").nth(0);
    await expect(firstSetRow.getByText("Reps")).toBeVisible();
    await expect(firstSetRow.getByText("Weight")).toBeVisible();
    await expect(firstSetRow).toHaveCSS("display", "grid");

    const firstSetRowBox = await firstSetRow.boundingBox();
    const firstRepBox = await firstRep.boundingBox();
    const firstWeightBox = await firstWeight.boundingBox();
    expect(firstSetRowBox?.height).toBeLessThan(96);
    expect(firstRepBox?.width).toBeGreaterThan(40);
    expect(firstWeightBox?.width).toBeGreaterThan(40);

    await firstRep.fill("12");
    await firstWeight.fill("2");
    await expect(page.locator("[data-agent-id='workout-set-summary']")).toContainText("0 of 2 sets logged", {
      timeout: 500,
    });
    await firstWeight.fill("200");
    await expect(page.locator("[data-agent-id='workout-set-summary']")).toContainText("1 of 2 sets logged");
    await expect(firstSetRow.locator("[data-agent-id^='set-logged-']")).toBeVisible();
    await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toHaveCount(0);

    await firstRep.fill("");
    await expect(page.locator("[data-agent-id='workout-set-summary']")).toContainText("1 of 2 sets logged", {
      timeout: 100,
    });
    await page.waitForTimeout(450);
    await expect(page.locator("[data-agent-id='workout-set-summary']")).toContainText("0 of 2 sets logged");

    await firstRep.fill("12");
    await firstWeight.fill("220");
    await secondRep.fill("10");
    await secondWeight.fill("220");
    await page.waitForTimeout(450);

    await expect(page.locator("[data-agent-id='workout-set-summary']")).toContainText("2 of 2 sets logged");
    await expect(page.locator("[data-agent-id='finish-workout']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toBeVisible();
    await expect(page.locator("[data-agent-id='feedback-save']")).toBeDisabled();
    await page.locator("[data-agent-id='feedback-pain-option-1']").click();
    await expect(page.locator("[data-agent-id='feedback-save']")).toBeDisabled();
    await page.locator("[data-agent-id='feedback-effort-option-3']").click();
    await expect(page.locator("[data-agent-id='feedback-save']")).toBeEnabled();
    await page.locator("[data-agent-id='feedback-save']").click();
    await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='finish-workout']")).toBeVisible();

    await firstRep.fill("");
    await page.waitForTimeout(450);
    await expect(page.locator("[data-agent-id='workout-set-summary']")).toContainText("1 of 2 sets logged");
    await expect(page.locator("[data-agent-id='finish-workout']")).toHaveCount(0);

    await firstRep.fill("12");
    await page.waitForTimeout(450);
    await expect(page.locator("[data-agent-id='workout-set-summary']")).toContainText("2 of 2 sets logged");
    await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='finish-workout']")).toBeVisible();

    await page.locator("[data-agent-id='finish-workout']").click();

    await expect(page).toHaveURL(/\/programs\/\d+\/workouts\/\d+$/);
    await expect(page.locator("[data-agent-id='workout-day-title']")).toContainText("Day 2");
    await expect(page.locator("[data-agent-id='workout-set-summary']")).toContainText("0 of 2 sets logged");
    await expect(page.getByRole("heading", { name: "Barbell Back Squat" })).toBeVisible();
  });
});
