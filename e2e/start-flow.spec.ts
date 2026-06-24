import { expect, test, type Locator, type Page } from "@playwright/test";

const setAutosaveBeforeDelayMs = 400;
const setAutosaveStaleTimerProbeMs = 500;
const setAutosaveSettleMs = 950;
const interactionFeedbackAttribute = "data-interaction-feedback";
const interactionFeedbackPeakDelayMs = 75;
const interactionFeedbackSettleMs = 240;
const standardTypographyFontSizes = ["13px", "16px", "22px", "34px"];

type InteractionFeedbackWindow = Window & {
  __POWERJACK_INTERACTION_FEEDBACK_OBSERVER__?: MutationObserver;
  __POWERJACK_INTERACTION_FEEDBACK_SEEN__?: boolean;
};

type TestClockWindow = Window & {
  __POWERJACK_TEST_CLOCK__?: {
    advance(milliseconds: number): void;
  };
};

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

async function openTemplateBuilder(
  page: import("@playwright/test").Page,
  options: { dayCount: number; name?: string },
) {
  await openTemplateFocus(page, options.name ?? "Back In Action");
  await selectFocusAndOpenDays(page);
  await page.locator(`[data-agent-id='template-days-per-week-${options.dayCount}']`).click();
  await page.locator("[data-agent-id='template-days-per-week-next']").click();
  await expect(page).toHaveURL(/\/templates\/new\/builder$/);
}

async function expectActionsOnSingleRow(
  page: import("@playwright/test").Page,
  leftAgentId: string,
  rightAgentId: string,
) {
  const leftAction = page.locator(`[data-agent-id='${leftAgentId}']`);
  const rightAction = page.locator(`[data-agent-id='${rightAgentId}']`);

  await expect(leftAction).toBeVisible();
  await expect(rightAction).toBeVisible();

  const [leftBox, rightBox] = await Promise.all([leftAction.boundingBox(), rightAction.boundingBox()]);

  expect(leftBox, `${leftAgentId} should have a layout box`).not.toBeNull();
  expect(rightBox, `${rightAgentId} should have a layout box`).not.toBeNull();

  if (!leftBox || !rightBox) {
    return;
  }

  const leftCenterY = leftBox.y + leftBox.height / 2;
  const rightCenterY = rightBox.y + rightBox.height / 2;

  expect(Math.abs(leftCenterY - rightCenterY)).toBeLessThanOrEqual(2);
  expect(leftBox.x + leftBox.width).toBeLessThanOrEqual(rightBox.x);
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

async function createTwoDayTemplateFromTemplatesPage(
  page: import("@playwright/test").Page,
  name = "List Template",
) {
  await page.goto("/templates");
  await page.locator("[data-agent-id='templates-add-template']").click();
  await page.locator("[data-agent-id='template-name-input']").fill(name);
  await page.locator("[data-agent-id='template-name-next']").click();
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
  await expect(page).toHaveURL(/\/templates$/);
}

async function addExerciseToCurrentTemplateDay(
  page: import("@playwright/test").Page,
  searchTerm: string,
  exerciseName: RegExp,
) {
  await page.locator("[data-agent-id='add-exercise']").click();
  await page.locator("[data-agent-id='exercise-search-input']").fill(searchTerm);
  await page.getByRole("button", { name: exerciseName }).click();
}

async function createWeightedVolumeTemplate(page: import("@playwright/test").Page) {
  await openTemplateFocus(page, "Weighted Volume");
  await page.locator(".muscle-focus-grid").getByRole("button", { name: "Back" }).click();
  await page.locator(".muscle-focus-grid").getByRole("button", { name: "Biceps" }).click();
  await page.locator(".muscle-focus-grid").getByRole("button", { name: "Shoulders" }).click();
  await page.locator("[data-agent-id='template-muscle-focus-next']").click();
  await page.locator("[data-agent-id='template-days-per-week-2']").click();
  await page.locator("[data-agent-id='template-days-per-week-next']").click();
  await addExerciseToCurrentTemplateDay(page, "deadlift", /^Barbell Deadlift/);
  await addExerciseToCurrentTemplateDay(page, "pull-up", /^Pull Up/);
  await addExerciseToCurrentTemplateDay(page, "lat pulldown", /^Cable Lat Pulldown/);
  await addExerciseToCurrentTemplateDay(page, "rear delt fly", /^Cable Rear Delt Fly/);
  await page.locator("[data-agent-id='template-day-2']").click();
  await addExerciseToCurrentTemplateDay(page, "squat", /Barbell Back Squat/);
  await page.locator("[data-agent-id='save-template']").click();
  await expect(page).toHaveURL(/\/start\/select-template$/);
}

async function createTwoLiftFirstDayTemplate(page: import("@playwright/test").Page, name = "Two Lift Day") {
  await openTemplateFocus(page, name);
  await selectFocusAndOpenDays(page);
  await page.locator("[data-agent-id='template-days-per-week-2']").click();
  await page.locator("[data-agent-id='template-days-per-week-next']").click();
  await addExerciseToCurrentTemplateDay(page, "bench", /Barbell Bench Press/);
  await addExerciseToCurrentTemplateDay(page, "deadlift", /Barbell Deadlift/);
  await page.locator("[data-agent-id='template-day-2']").click();
  await addExerciseToCurrentTemplateDay(page, "squat", /Barbell Back Squat/);
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

async function completeActiveLiftWithFeedback(
  page: import("@playwright/test").Page,
  options: { pain: number; effort: number; reps?: [string, string]; weight?: string },
) {
  const reps = options.reps ?? ["10", "8"];
  const weight = options.weight ?? "100";
  const firstRep = page.locator("[data-agent-id^='set-reps-']").nth(0);
  const firstWeight = page.locator("[data-agent-id^='set-weight-']").nth(0);
  const secondRep = page.locator("[data-agent-id^='set-reps-']").nth(1);
  const secondWeight = page.locator("[data-agent-id^='set-weight-']").nth(1);

  await firstRep.fill(reps[0]);
  await firstWeight.fill(weight);
  await secondRep.fill(reps[1]);
  await secondWeight.fill(weight);
  await page.waitForTimeout(setAutosaveSettleMs);
  await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toBeVisible();
  await page.locator(`[data-agent-id='feedback-pain-option-${options.pain}']`).click();
  await page.locator(`[data-agent-id='feedback-effort-option-${options.effort}']`).click();
  await page.locator("[data-agent-id='feedback-save']").click();
  await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toHaveCount(0);
  await expect(page.locator("[data-agent-id='finish-workout']")).toBeVisible();
}

async function completeLiftWithFeedback(
  page: import("@playwright/test").Page,
  exerciseName: string,
  options: { effort?: number; pain?: number; reps?: string; weight?: string } = {},
) {
  const liftCard = page.locator("[data-agent-id^='lift-card-']").filter({ hasText: exerciseName });
  const repsInputs = liftCard.locator("[data-agent-id^='set-reps-']");
  const weightInputs = liftCard.locator("[data-agent-id^='set-weight-']");
  const reps = options.reps ?? "10";
  const weight = options.weight ?? "10";

  await expect(liftCard).toBeVisible();
  await expect(repsInputs.first()).toBeVisible();

  const setCount = await repsInputs.count();

  for (let index = 0; index < setCount; index += 1) {
    const repsInput = repsInputs.nth(index);
    const weightInput = weightInputs.nth(index);

    await repsInput.fill(reps);

    if (await weightInput.isEnabled()) {
      await weightInput.fill(weight);
    }

    await page.waitForTimeout(setAutosaveSettleMs);
  }

  await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toContainText(exerciseName);
  await page.locator(`[data-agent-id='feedback-pain-option-${options.pain ?? 1}']`).click();
  await page.locator(`[data-agent-id='feedback-effort-option-${options.effort ?? 3}']`).click();
  await page.locator("[data-agent-id='feedback-save']").click();
  await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toHaveCount(0);
}

async function openWeekTwoBenchManualCheckIn(
  page: import("@playwright/test").Page,
  options: { templateName: string; pain: number },
) {
  await createTwoDayTemplate(page, options.templateName);
  await startSelectedProgram(page, 4);
  await completeActiveLiftWithFeedback(page, { pain: options.pain, effort: 3 });
  await page.locator("[data-agent-id='finish-workout']").click();
  await expect(page.locator("[data-agent-id='workout-day-title']")).toContainText("Day 2");
  await completeActiveLiftWithFeedback(page, { pain: 1, effort: 3, reps: ["8", "8"], weight: "150" });
  await page.locator("[data-agent-id='finish-workout']").click();
  await expect(page.locator("[data-agent-id='workout-week-label']")).toContainText("Week 2/4");
  await expect(page.locator("[data-agent-id='workout-day-title']")).toContainText("Day 1");
  await expect(page.locator("[data-agent-id='manual-checkin-modal']")).toBeVisible();
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
  await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("100% done");
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
  const menu = page.locator("[data-agent-id='app-menu-toggle']");

  await expect(resume).toBeVisible();

  const viewport = page.viewportSize();
  const resumeBox = await resume.boundingBox();
  const menuBox = await menu.boundingBox();

  expect(viewport).not.toBeNull();
  expect(resumeBox).not.toBeNull();
  expect(menuBox).not.toBeNull();

  if (viewport && resumeBox && menuBox) {
    const resumeCenter = resumeBox.x + resumeBox.width / 2;
    expect(Math.abs(resumeCenter - viewport.width / 2)).toBeLessThanOrEqual(12);
    expect(resumeBox.x + resumeBox.width).toBeLessThan(menuBox.x);
  }
}

async function expectAppLogoOppositeMenu(page: import("@playwright/test").Page): Promise<void> {
  const logo = page.locator("[data-agent-id='app-logo']");
  const menu = page.locator("[data-agent-id='app-menu-toggle']");

  await expect(logo).toBeVisible();
  await expect(logo).toHaveAttribute("src", "/assets/power-jack-logo-favicon.png");
  await expect(menu).toBeVisible();

  const didLogoLoad = await logo.evaluate((element) => {
    const image = element as HTMLImageElement;
    return image.complete && image.naturalWidth > 0 && image.naturalHeight > 0;
  });
  const viewport = page.viewportSize();
  const logoBox = await logo.boundingBox();
  const menuBox = await menu.boundingBox();

  expect(didLogoLoad, "app logo image should load successfully").toBe(true);
  expect(viewport).not.toBeNull();
  expect(logoBox, "app logo should have a layout box").not.toBeNull();
  expect(menuBox, "app menu toggle should have a layout box").not.toBeNull();

  if (!viewport || !logoBox || !menuBox) {
    return;
  }

  const logoCenterY = logoBox.y + logoBox.height / 2;
  const menuCenterY = menuBox.y + menuBox.height / 2;

  expect(logoBox.x, "app logo should stay inside the left viewport edge").toBeGreaterThanOrEqual(0);
  expect(menuBox.x + menuBox.width, "menu should stay inside the right viewport edge").toBeLessThanOrEqual(
    viewport.width + 1,
  );
  expect(logoBox.x + logoBox.width, "app logo should sit left of the hamburger menu").toBeLessThan(menuBox.x);
  expect(Math.abs(logoCenterY - menuCenterY), "app logo should align vertically with the menu").toBeLessThanOrEqual(4);
  expect(await pageHasHorizontalOverflow(page)).toBe(false);
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

async function pageHasVerticalOverflow(page: import("@playwright/test").Page): Promise<boolean> {
  return page.evaluate(() => {
    const documentElement = document.documentElement;
    return (
      documentElement.scrollHeight > documentElement.clientHeight + 2 ||
      document.body.scrollHeight > document.body.clientHeight + 2
    );
  });
}

async function expectVisibleTextUsesStandardTypography(page: Page, contextLabel: string): Promise<void> {
  const findings = await page.evaluate((allowedFontSizes) => {
    const allowed = new Set(allowedFontSizes);
    const rejectedSelectors = "script, style, noscript, svg, .sr-only, [hidden], [aria-hidden='true']";
    const findings: Array<{ fontSize: string; target: string; text: string }> = [];

    function describeElement(element: Element): string {
      const agentTarget = element.closest("[data-agent-id]");
      const agentId = agentTarget?.getAttribute("data-agent-id");
      const id = element.id ? `#${element.id}` : "";
      const className =
        typeof element.className === "string" && element.className.trim()
          ? `.${element.className.trim().split(/\s+/).slice(0, 3).join(".")}`
          : "";
      const agent = agentId ? `[data-agent-id="${agentId}"]` : "";

      return `${element.tagName.toLowerCase()}${id}${className}${agent}`;
    }

    function textRangeHasVisibleArea(node: Text): boolean {
      const range = document.createRange();
      range.selectNodeContents(node);
      const hasArea = Array.from(range.getClientRects()).some((rect) => rect.width > 0 && rect.height > 0);
      range.detach();
      return hasArea;
    }

    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    let node = walker.nextNode();

    while (node) {
      const textNode = node as Text;
      const text = textNode.textContent?.replace(/\s+/g, " ").trim() ?? "";
      const parent = textNode.parentElement;

      if (text && parent && !parent.closest(rejectedSelectors) && textRangeHasVisibleArea(textNode)) {
        const style = window.getComputedStyle(parent);

        if (style.display !== "none" && style.visibility !== "hidden" && !allowed.has(style.fontSize)) {
          findings.push({
            fontSize: style.fontSize,
            target: describeElement(parent),
            text: text.slice(0, 80),
          });
        }
      }

      node = walker.nextNode();
    }

    return findings;
  }, standardTypographyFontSizes);

  expect(findings, `${contextLabel} visible text should use standard typography sizes`).toEqual([]);
}

async function expectElementsWithinViewport(
  page: import("@playwright/test").Page,
  agentIds: string[],
): Promise<void> {
  const viewport = page.viewportSize();

  expect(viewport).not.toBeNull();

  if (!viewport) {
    return;
  }

  for (const agentId of agentIds) {
    const element = page.locator(`[data-agent-id='${agentId}']`);
    const box = await element.boundingBox();

    expect(box, `${agentId} should have a layout box`).not.toBeNull();

    if (!box) {
      continue;
    }

    expect(box.x, `${agentId} should not overflow left`).toBeGreaterThanOrEqual(0);
    expect(box.y, `${agentId} should not overflow top`).toBeGreaterThanOrEqual(0);
    expect(box.x + box.width, `${agentId} should not overflow right`).toBeLessThanOrEqual(viewport.width + 1);
    expect(box.y + box.height, `${agentId} should not overflow bottom`).toBeLessThanOrEqual(viewport.height + 1);
  }
}

async function expectCopyDayModalCenteredInViewport(page: import("@playwright/test").Page): Promise<void> {
  const modal = page.locator("[data-agent-id='copy-day-modal']");
  const viewport = page.viewportSize();
  const modalBox = await modal.boundingBox();

  await expect(modal).toBeVisible();
  expect(viewport).not.toBeNull();
  expect(modalBox, "copy-day modal should have a layout box").not.toBeNull();

  if (!viewport || !modalBox) {
    return;
  }

  const modalCenterY = modalBox.y + modalBox.height / 2;

  expect(modalBox.y, "copy-day modal should not overflow top").toBeGreaterThanOrEqual(0);
  expect(modalBox.y + modalBox.height, "copy-day modal should not overflow bottom").toBeLessThanOrEqual(
    viewport.height + 1,
  );
  expect(
    Math.abs(modalCenterY - viewport.height / 2),
    "copy-day modal should be vertically centered",
  ).toBeLessThanOrEqual(16);

  await expectElementsWithinViewport(page, [
    "copy-day-target-2",
    "copy-day-target-3",
    "copy-day-target-4",
  ]);
}

async function expectStaticScreenFitsViewport(
  page: import("@playwright/test").Page,
  screenAgentId: string,
  importantAgentIds: string[],
): Promise<void> {
  const screen = page.locator(`[data-agent-id='${screenAgentId}']`);

  await expect(screen).toBeVisible();
  expect(await pageHasVerticalOverflow(page), `${screenAgentId} should not make the document scroll`).toBe(false);

  const screenMetrics = await screen.evaluate((element) => {
    const style = window.getComputedStyle(element);

    return {
      clientHeight: element.clientHeight,
      overflowY: style.overflowY,
      scrollHeight: element.scrollHeight,
    };
  });

  expect(screenMetrics.overflowY, `${screenAgentId} should not opt into scrolling`).toBe("hidden");
  expect(screenMetrics.scrollHeight, `${screenAgentId} content should fit its own viewport`).toBeLessThanOrEqual(
    screenMetrics.clientHeight + 2,
  );

  await expectElementsWithinViewport(page, importantAgentIds);
}

async function expectScreenAllowsIntentionalScroll(
  page: import("@playwright/test").Page,
  screenAgentId: string,
): Promise<void> {
  const screen = page.locator(`[data-agent-id='${screenAgentId}']`);

  await expect(screen).toBeVisible();
  await expect(screen, `${screenAgentId} should explicitly opt into scrolling`).toHaveClass(
    /app-screen--scrollable/,
  );

  const overflowY = await screen.evaluate((element) => window.getComputedStyle(element).overflowY);
  expect(overflowY, `${screenAgentId} should use a scrollable overflow mode`).toBe("auto");
}

async function scrollActiveWorkoutPageToBottom(page: import("@playwright/test").Page): Promise<void> {
  const screen = page.locator("[data-agent-id='active-workout-page']");

  await expect(screen).toBeVisible();

  const scrollTop = await screen.evaluate((element) => {
    element.scrollTo({ top: element.scrollHeight, left: 0, behavior: "auto" });
    return element.scrollTop;
  });

  expect(scrollTop, "active workout page should be scrolled before finishing").toBeGreaterThan(0);
}

async function expectElementWithinActiveWorkoutViewport(
  page: import("@playwright/test").Page,
  locator: Locator,
  name: string,
): Promise<void> {
  const screen = page.locator("[data-agent-id='active-workout-page']");
  const [screenBox, elementBox] = await Promise.all([screen.boundingBox(), locator.boundingBox()]);

  expect(screenBox, "active workout page should have a layout box").not.toBeNull();
  expect(elementBox, `${name} should have a layout box`).not.toBeNull();

  if (!screenBox || !elementBox) {
    return;
  }

  expect(elementBox.x, `${name} should not overflow the active workout left edge`).toBeGreaterThanOrEqual(
    screenBox.x,
  );
  expect(
    elementBox.x + elementBox.width,
    `${name} should not overflow the active workout right edge`,
  ).toBeLessThanOrEqual(screenBox.x + screenBox.width + 1);
  expect(elementBox.y, `${name} should not overflow the active workout top edge`).toBeGreaterThanOrEqual(
    screenBox.y,
  );
  expect(
    elementBox.y + elementBox.height,
    `${name} should not be clipped by the active workout bottom edge`,
  ).toBeLessThanOrEqual(screenBox.y + screenBox.height + 1);
}

async function captureElementBox(locator: Locator, name: string) {
  const box = await locator.boundingBox();

  expect(box, `${name} should have a layout box`).not.toBeNull();

  if (!box) {
    throw new Error(`${name} should have a layout box`);
  }

  return box;
}

async function expectElementBoxStable(
  locator: Locator,
  before: Awaited<ReturnType<typeof captureElementBox>>,
  name: string,
) {
  const after = await captureElementBox(locator, name);

  expect(Math.abs(after.x - before.x), `${name} x position should stay stable`).toBeLessThanOrEqual(1);
  expect(Math.abs(after.y - before.y), `${name} y position should stay stable`).toBeLessThanOrEqual(1);
  expect(Math.abs(after.width - before.width), `${name} width should stay stable`).toBeLessThanOrEqual(1);
}

async function expectActiveWorkoutPageScrolledToTop(page: import("@playwright/test").Page): Promise<void> {
  const screen = page.locator("[data-agent-id='active-workout-page']");

  await expect(screen).toBeVisible();
  await expect
    .poll(
      async () =>
        screen.evaluate((element) => {
          return element.scrollTop;
        }),
      { message: "active workout page should reset to the top after Finish workout" },
    )
    .toBe(0);
}

async function freezeBrowserDate(page: import("@playwright/test").Page, isoTimestamp: string): Promise<void> {
  await page.addInitScript((fixedIso) => {
    const fixedTime = new Date(fixedIso).getTime();
    const RealDate = Date;
    let offsetMs = 0;

    class MockDate extends RealDate {
      constructor(...args: ConstructorParameters<DateConstructor>) {
        if (args.length === 0) {
          super(fixedTime + offsetMs);
          return;
        }

        super(...args);
      }

      static now() {
        return fixedTime + offsetMs;
      }
    }

    MockDate.UTC = RealDate.UTC;
    MockDate.parse = RealDate.parse;
    window.Date = MockDate as DateConstructor;
    (window as TestClockWindow).__POWERJACK_TEST_CLOCK__ = {
      advance(milliseconds: number) {
        offsetMs += milliseconds;
      },
    };
  }, isoTimestamp);
}

async function expectTemplateDaysPerWeekOptionsInSingleRow(page: import("@playwright/test").Page): Promise<void> {
  const options = page.locator("[data-agent-id='template-days-per-week-options']").getByRole("radio");

  await expect(options).toHaveCount(5);

  const boxes = await options.evaluateAll((elements) =>
    elements.map((element) => {
      const rect = element.getBoundingClientRect();

      return {
        height: rect.height,
        left: rect.left,
        top: rect.top,
        width: rect.width,
      };
    }),
  );
  const firstTop = boxes[0]?.top ?? 0;

  for (const box of boxes) {
    expect(Math.abs(box.top - firstTop)).toBeLessThanOrEqual(1);
    expect(box.width).toBeGreaterThanOrEqual(44);
    expect(box.height).toBeGreaterThanOrEqual(44);
  }

  for (let index = 1; index < boxes.length; index += 1) {
    expect(boxes[index].left).toBeGreaterThan(boxes[index - 1].left);
  }

  expect(await pageHasHorizontalOverflow(page)).toBe(false);
}

async function expectTemplateBuilderDayTabsFit(page: import("@playwright/test").Page, dayCount: number): Promise<void> {
  const tabs = page.locator("[data-agent-id^='template-day-']");

  await expect(tabs).toHaveCount(dayCount);

  const viewport = page.viewportSize();
  const boxes = await tabs.evaluateAll((elements) =>
    elements.map((element) => {
      const rect = element.getBoundingClientRect();

      return {
        height: rect.height,
        left: rect.left,
        right: rect.right,
        top: rect.top,
        width: rect.width,
      };
    }),
  );
  const firstTop = boxes[0]?.top ?? 0;

  expect(viewport).not.toBeNull();

  for (const box of boxes) {
    expect(Math.abs(box.top - firstTop)).toBeLessThanOrEqual(1);
    expect(box.width).toBeGreaterThan(0);
    expect(box.height).toBeGreaterThanOrEqual(44);
    expect(box.height).toBeLessThanOrEqual(49);

    if (viewport) {
      expect(box.left).toBeGreaterThanOrEqual(0);
      expect(box.right).toBeLessThanOrEqual(viewport.width);
    }
  }

  for (let index = 1; index < boxes.length; index += 1) {
    expect(boxes[index].left).toBeGreaterThan(boxes[index - 1].left);
  }

  expect(await pageHasHorizontalOverflow(page)).toBe(false);
}

async function expectTemplateBuilderHeaderAddExercisePlacement(
  page: import("@playwright/test").Page,
  dayCount: number,
  options: {
    expectedModeLabel?: string;
    screenshotName?: string;
    testInfo?: import("@playwright/test").TestInfo;
  } = {},
): Promise<number> {
  const title = page.locator("[data-agent-id='template-builder-title-text']");
  const addExercise = page.locator("[data-agent-id='add-exercise']");
  const lastDayTab = page.locator(`[data-agent-id='template-day-${dayCount}']`);

  await expect(title).toBeVisible();
  await expect(addExercise).toBeVisible();
  await expect(addExercise).toHaveAccessibleName("Add exercise");
  await expect(addExercise).toHaveText("exercise");
  await expect(lastDayTab).toBeVisible();
  await expect(page.locator("[data-agent-id='template-builder-page']")).not.toContainText(/\d+ days per week/);
  await expectTemplateBuilderModeLabelBelowTitle(page, options.expectedModeLabel ?? "New template");

  const metrics = await page.evaluate(
    ({ dayCount: expectedDayCount }) => {
      const titleElement = document.querySelector<HTMLElement>("[data-agent-id='template-builder-title-text']");
      const addElement = document.querySelector<HTMLElement>("[data-agent-id='add-exercise']");
      const lastDayElement = document.querySelector<HTMLElement>(`[data-agent-id='template-day-${expectedDayCount}']`);

      if (!titleElement || !addElement || !lastDayElement) {
        throw new Error("Template builder header geometry targets are missing.");
      }

      const titleRect = titleElement.getBoundingClientRect();
      const addRect = addElement.getBoundingClientRect();
      const lastDayRect = lastDayElement.getBoundingClientRect();
      const titleStyle = window.getComputedStyle(titleElement);
      const context = document.createElement("canvas").getContext("2d");
      const titleText = titleElement.textContent?.trim() ?? "";
      let safeVisibleTitleCharsMobile = 0;

      if (context) {
        context.font = titleStyle.font;

        for (let index = 1; index <= titleText.length; index += 1) {
          if (context.measureText(titleText.slice(0, index)).width <= titleRect.width) {
            safeVisibleTitleCharsMobile = index;
          }
        }
      }

      return {
        addCenterY: addRect.top + addRect.height / 2,
        addLeft: addRect.left,
        addRight: addRect.right,
        addWidth: addRect.width,
        lastDayRight: lastDayRect.right,
        safeVisibleTitleCharsMobile,
        titleCenterY: titleRect.top + titleRect.height / 2,
        titleRight: titleRect.right,
        titleText,
        titleWidth: titleRect.width,
        viewportWidth: window.innerWidth,
      };
    },
    { dayCount },
  );

  expect(Math.abs(metrics.addCenterY - metrics.titleCenterY), "add exercise should align with the title row").toBeLessThanOrEqual(3);
  expect(Math.abs(metrics.addRight - metrics.lastDayRight), "add exercise right edge should align with the last day tab").toBeLessThanOrEqual(2);
  expect(metrics.titleRight, "title column should end before the add exercise control").toBeLessThanOrEqual(
    metrics.addLeft - 1,
  );
  expect(await pageHasHorizontalOverflow(page)).toBe(false);

  if (options.testInfo) {
    await options.testInfo.attach(`template-builder-header-${dayCount}-day-metrics.json`, {
      body: JSON.stringify(metrics, null, 2),
      contentType: "application/json",
    });
  }

  if (options.screenshotName && options.testInfo) {
    await expectMobileScreenshot(page, options.testInfo, options.screenshotName);
  }

  return metrics.safeVisibleTitleCharsMobile;
}

async function expectTemplateBuilderModeLabelBelowTitle(
  page: import("@playwright/test").Page,
  expectedLabel: string,
): Promise<void> {
  const title = page.locator("[data-agent-id='template-builder-title-text']");
  const modeLabel = page.locator("[data-agent-id='template-builder-mode-label']");

  await expect(title).toBeVisible();
  await expect(modeLabel).toBeVisible();
  await expect(modeLabel).toHaveText(expectedLabel);

  const metrics = await page.evaluate(() => {
    const titleElement = document.querySelector<HTMLElement>(
      "[data-agent-id='template-builder-title-text']",
    );
    const modeElement = document.querySelector<HTMLElement>(
      "[data-agent-id='template-builder-mode-label']",
    );

    if (!titleElement || !modeElement) {
      throw new Error("Template builder mode label geometry targets are missing.");
    }

    const titleRect = titleElement.getBoundingClientRect();
    const modeRect = modeElement.getBoundingClientRect();

    return {
      modeLeft: modeRect.left,
      modeTop: modeRect.top,
      titleBottom: titleRect.bottom,
      titleLeft: titleRect.left,
      titleTop: titleRect.top,
    };
  });

  expect(metrics.modeTop, "mode label should sit below the template title").toBeGreaterThanOrEqual(
    metrics.titleBottom - 1,
  );
  expect(metrics.modeTop, "mode label should not appear above the template title").toBeGreaterThan(
    metrics.titleTop,
  );
  expect(
    Math.abs(metrics.modeLeft - metrics.titleLeft),
    "mode label should align with the title",
  ).toBeLessThanOrEqual(2);
}

async function expectTemplateListHeaderAddPlacement(
  page: import("@playwright/test").Page,
  options: {
    addAgentId: string;
    gridAgentId: string;
    titleAgentId: string;
  },
): Promise<void> {
  const title = page.locator(`[data-agent-id='${options.titleAgentId}']`);
  const addTemplate = page.locator(`[data-agent-id='${options.addAgentId}']`);
  const grid = page.locator(`[data-agent-id='${options.gridAgentId}']`);

  await expect(title).toBeVisible();
  await expect(addTemplate).toBeVisible();
  await expect(addTemplate).toHaveAccessibleName("Add template");
  await expect(addTemplate).toHaveText("template");
  await expect(grid).toBeVisible();

  const metrics = await page.evaluate(
    ({ addAgentId, gridAgentId, titleAgentId }) => {
      const titleElement = document.querySelector<HTMLElement>(`[data-agent-id='${titleAgentId}']`);
      const addElement = document.querySelector<HTMLElement>(`[data-agent-id='${addAgentId}']`);
      const gridElement = document.querySelector<HTMLElement>(`[data-agent-id='${gridAgentId}']`);

      if (!titleElement || !addElement || !gridElement) {
        throw new Error("Template list header geometry targets are missing.");
      }

      const titleRect = titleElement.getBoundingClientRect();
      const addRect = addElement.getBoundingClientRect();
      const gridRect = gridElement.getBoundingClientRect();

      return {
        addCenterY: addRect.top + addRect.height / 2,
        addLeft: addRect.left,
        addRight: addRect.right,
        gridRight: gridRect.right,
        titleCenterY: titleRect.top + titleRect.height / 2,
        titleRight: titleRect.right,
      };
    },
    options,
  );

  expect(Math.abs(metrics.addCenterY - metrics.titleCenterY), "add template should align with the title row").toBeLessThanOrEqual(3);
  expect(Math.abs(metrics.addRight - metrics.gridRight), "add template right edge should align with the panel").toBeLessThanOrEqual(2);
  expect(metrics.titleRight, "title column should end before the add template control").toBeLessThanOrEqual(
    metrics.addLeft - 1,
  );
  expect(await pageHasHorizontalOverflow(page)).toBe(false);
}

async function expectExerciseSearchResultsInsideViewport(page: import("@playwright/test").Page): Promise<void> {
  const results = page.locator("[data-agent-id='exercise-search-results']");

  await expect(results).toBeVisible();

  const viewport = page.viewportSize();
  const resultsBox = await results.boundingBox();
  const overflowY = await results.evaluate((element) => window.getComputedStyle(element).overflowY);

  expect(viewport).not.toBeNull();
  expect(resultsBox).not.toBeNull();
  expect(overflowY).toBe("auto");

  if (viewport && resultsBox) {
    expect(resultsBox.y).toBeGreaterThanOrEqual(0);
    expect(resultsBox.y + resultsBox.height).toBeLessThanOrEqual(viewport.height + 1);
  }
}

async function expectExerciseSearchOverlayInsideViewport(
  page: import("@playwright/test").Page,
  inputAgentId: string,
  headingName: string,
): Promise<void> {
  const viewport = page.viewportSize();
  const topBar = page.locator("[data-agent-id='app-top-bar']");
  const panel = page.locator("[data-agent-id='exercise-search-overlay'] .exercise-search-overlay__panel");
  const heading = panel.getByRole("heading", { name: headingName });
  const input = page.locator(`[data-agent-id='${inputAgentId}']`);
  const results = page.locator("[data-agent-id='exercise-search-results']");

  expect(viewport).not.toBeNull();
  await expect(topBar).toBeVisible();
  await expect(panel).toBeVisible();
  await expect(heading).toBeVisible();
  await expect(input).toBeVisible();
  await expect(input).toHaveAttribute("placeholder", "Push Up");
  await expect(results).toBeVisible();

  if (!viewport) {
    return;
  }

  const [topBarBox, panelBox] = await Promise.all([topBar.boundingBox(), panel.boundingBox()]);

  expect(topBarBox, "app top bar should have a layout box").not.toBeNull();
  expect(panelBox, "exercise search panel should have a layout box").not.toBeNull();

  if (topBarBox && panelBox) {
    const panelGapBelowTopBar = panelBox.y - (topBarBox.y + topBarBox.height);

    expect(panelGapBelowTopBar, "exercise search panel should sit below the top bar").toBeGreaterThanOrEqual(7);
    expect(panelGapBelowTopBar, "exercise search panel gap should stay compact").toBeLessThanOrEqual(16);
  }

  const elements: Array<[string, Locator]> = [
    ["exercise search panel", panel],
    ["exercise search heading", heading],
    ["exercise search input", input],
    ["exercise search results", results],
  ];

  for (const [name, element] of elements) {
    const box = await element.boundingBox();

    expect(box, `${name} should have a layout box`).not.toBeNull();

    if (!box) {
      continue;
    }

    expect(box.x, `${name} should not overflow left`).toBeGreaterThanOrEqual(0);
    expect(box.y, `${name} should not overflow top`).toBeGreaterThanOrEqual(0);
    expect(box.x + box.width, `${name} should not overflow right`).toBeLessThanOrEqual(viewport.width + 1);
    expect(box.y + box.height, `${name} should not overflow bottom`).toBeLessThanOrEqual(viewport.height + 1);
  }

  const panelOverflowY = await panel.evaluate((element) => window.getComputedStyle(element).overflowY);
  const resultsOverflowY = await results.evaluate((element) => window.getComputedStyle(element).overflowY);

  expect(panelOverflowY, "exercise search panel should not become the scroll container").toBe("hidden");
  expect(resultsOverflowY, "exercise search results should be the scroll container").toBe("auto");
}

async function expectExerciseSearchScrollContained(page: import("@playwright/test").Page): Promise<void> {
  const panel = page.locator("[data-agent-id='exercise-search-overlay'] .exercise-search-overlay__panel");
  const results = page.locator("[data-agent-id='exercise-search-results']");

  await expect(panel).toBeVisible();
  await expect(results).toBeVisible();

  const beforePageScroll = await getExerciseSearchPageScrollMetrics(page);
  const panelBox = await panel.boundingBox();

  expect(panelBox, "exercise search panel should have a layout box").not.toBeNull();

  if (panelBox) {
    await page.mouse.move(panelBox.x + panelBox.width / 2, panelBox.y + 8);
    await page.mouse.wheel(0, 600);
  }

  const afterPageScroll = await getExerciseSearchPageScrollMetrics(page);

  expect(afterPageScroll.windowScrollY, "window should stay fixed while exercise search is open").toBe(
    beforePageScroll.windowScrollY,
  );
  expect(afterPageScroll.screenScrollTop, "app screen should stay fixed while exercise search is open").toBe(
    beforePageScroll.screenScrollTop,
  );

  if (afterPageScroll.screenClassName.includes("app-screen--scrollable")) {
    expect(afterPageScroll.screenOverflowY, "search should hide the app screen scrollbar").toBe("hidden");
  }

  const resultsScrollMetrics = await results.evaluate((element) => ({
    clientHeight: element.clientHeight,
    scrollHeight: element.scrollHeight,
    scrollTop: element.scrollTop,
  }));
  const beforeResultsScrollTop = resultsScrollMetrics.scrollTop;

  expect(
    resultsScrollMetrics.scrollHeight,
    "exercise search results should have enough content to scroll",
  ).toBeGreaterThan(resultsScrollMetrics.clientHeight + 1);
  const resultsBox = await results.boundingBox();

  expect(resultsBox, "exercise search results should have a layout box").not.toBeNull();

  if (resultsBox) {
    await page.mouse.move(resultsBox.x + resultsBox.width / 2, resultsBox.y + resultsBox.height / 2);
    await page.mouse.wheel(0, 600);
  }

  await expect
    .poll(() => results.evaluate((element) => element.scrollTop), {
      message: "exercise search results should be the only scroll area",
    })
    .toBeGreaterThan(beforeResultsScrollTop);
}

async function getExerciseSearchPageScrollMetrics(page: import("@playwright/test").Page) {
  return page.evaluate(() => {
    const overlay = document.querySelector("[data-agent-id='exercise-search-overlay']");
    const screen = overlay?.closest<HTMLElement>(".app-screen");

    return {
      screenClassName: screen?.className ?? "",
      screenOverflowY: screen ? window.getComputedStyle(screen).overflowY : "",
      screenScrollTop: screen?.scrollTop ?? 0,
      windowScrollY: window.scrollY,
    };
  });
}

async function expectExerciseSearchInputStableAfterBackspace(
  page: import("@playwright/test").Page,
  inputAgentId: string,
): Promise<void> {
  const input = page.locator(`[data-agent-id='${inputAgentId}']`);

  await expect(page.locator("[data-agent-id='exercise-search-overlay']")).toBeVisible();
  await expect(input).toBeVisible();
  await expect(input).toBeFocused();
  await expectExerciseSearchOverlayInsideViewport(page, inputAgentId, "Exercise search");
  await input.fill("bench press");
  await expect(input).toHaveValue("bench press");

  const beforeBox = await input.boundingBox();
  const beforeScrollY = await page.evaluate(() => window.scrollY);

  await input.press("Backspace");
  await expect(input).toHaveValue("bench pres");
  await expect(page.getByRole("button", { name: /Barbell Bench Press/ })).toBeVisible();

  const afterBox = await input.boundingBox();
  const afterScrollY = await page.evaluate(() => window.scrollY);

  expect(beforeBox).not.toBeNull();
  expect(afterBox).not.toBeNull();
  expect(afterScrollY).toBe(beforeScrollY);

  if (beforeBox && afterBox) {
    expect(Math.abs(afterBox.y - beforeBox.y)).toBeLessThanOrEqual(1);
    expect(Math.abs(afterBox.x - beforeBox.x)).toBeLessThanOrEqual(1);
    expect(Math.abs(afterBox.width - beforeBox.width)).toBeLessThanOrEqual(1);
  }

  await expectExerciseSearchOverlayInsideViewport(page, inputAgentId, "Exercise search");
  await expectExerciseSearchResultsInsideViewport(page);
}

async function expectFeedbackOptionsOnSingleRow(
  page: import("@playwright/test").Page,
  dataAgentPrefix: string,
) {
  const boxes = await page.locator(`[data-agent-id^='${dataAgentPrefix}-']`).evaluateAll((elements) =>
    elements.map((element) => {
      const rect = element.getBoundingClientRect();
      return { bottom: rect.bottom, top: rect.top };
    }),
  );

  expect(boxes).toHaveLength(5);
  const firstBox = boxes[0];

  expect(firstBox).toBeDefined();

  for (const box of boxes) {
    expect(Math.abs(box.top - firstBox.top)).toBeLessThanOrEqual(1);
    expect(Math.abs(box.bottom - firstBox.bottom)).toBeLessThanOrEqual(1);
  }
}

async function watchInteractionFeedback(
  page: import("@playwright/test").Page,
  selector: string,
): Promise<void> {
  await page.evaluate(
    ({ attribute, targetSelector }) => {
      const feedbackWindow = window as InteractionFeedbackWindow;
      const target = document.querySelector(targetSelector);

      feedbackWindow.__POWERJACK_INTERACTION_FEEDBACK_OBSERVER__?.disconnect();
      feedbackWindow.__POWERJACK_INTERACTION_FEEDBACK_SEEN__ = false;

      if (!target) {
        throw new Error(`Missing interaction feedback target: ${targetSelector}`);
      }

      const observer = new MutationObserver(() => {
        if (target.getAttribute(attribute) === "active") {
          feedbackWindow.__POWERJACK_INTERACTION_FEEDBACK_SEEN__ = true;
          observer.disconnect();
        }
      });

      observer.observe(target, { attributeFilter: [attribute], attributes: true });
      feedbackWindow.__POWERJACK_INTERACTION_FEEDBACK_OBSERVER__ = observer;
    },
    { attribute: interactionFeedbackAttribute, targetSelector: selector },
  );
}

async function expectObservedInteractionFeedback(page: import("@playwright/test").Page): Promise<void> {
  await expect
    .poll(
      async () =>
        page.evaluate(() =>
          Boolean((window as InteractionFeedbackWindow).__POWERJACK_INTERACTION_FEEDBACK_SEEN__),
        ),
      { timeout: 1_000 },
    )
    .toBe(true);
}

async function attachInteractionFeedbackScreenshot(
  page: import("@playwright/test").Page,
  testInfo: import("@playwright/test").TestInfo,
  name: string,
  selector: string,
): Promise<void> {
  if (testInfo.project.name !== "mobile-chrome") {
    return;
  }

  await page.locator(selector).first().evaluate((element, attribute) => {
    element.setAttribute(attribute, "active");
    window.setTimeout(() => element.removeAttribute(attribute), 210);
  }, interactionFeedbackAttribute);
  await page.waitForTimeout(interactionFeedbackPeakDelayMs);
  await testInfo.attach(name, {
    body: await page.screenshot({ fullPage: true }),
    contentType: "image/png",
  });
}

async function expectClickInteractionFeedback(
  page: import("@playwright/test").Page,
  selector: string,
  options: { expectClear?: boolean; screenshotName?: string; testInfo?: import("@playwright/test").TestInfo } = {},
): Promise<void> {
  const target = page.locator(selector).first();

  await expect(target).toBeVisible();
  await expect(target).toBeEnabled();
  await watchInteractionFeedback(page, selector);
  await target.click();
  await expectObservedInteractionFeedback(page);

  if (options.screenshotName && options.testInfo) {
    await attachInteractionFeedbackScreenshot(page, options.testInfo, options.screenshotName, selector);
  }

  if (options.expectClear !== false) {
    await expect(target).not.toHaveAttribute(interactionFeedbackAttribute, "active", {
      timeout: interactionFeedbackSettleMs,
    });
  }
}

async function expectFocusInteractionFeedback(
  page: import("@playwright/test").Page,
  selector: string,
  options: { screenshotName?: string; testInfo?: import("@playwright/test").TestInfo } = {},
): Promise<void> {
  const target = page.locator(selector).first();

  await expect(target).toBeVisible();
  await expect(target).toBeEditable();
  await watchInteractionFeedback(page, selector);
  await target.click();
  await expectObservedInteractionFeedback(page);

  if (options.screenshotName && options.testInfo) {
    await attachInteractionFeedbackScreenshot(page, options.testInfo, options.screenshotName, selector);
  }

  await expect(target).not.toHaveAttribute(interactionFeedbackAttribute, "active", {
    timeout: interactionFeedbackSettleMs,
  });
}

async function expectMobileScreenshot(
  page: import("@playwright/test").Page,
  testInfo: import("@playwright/test").TestInfo,
  name: string,
) {
  await expectVisibleTextUsesStandardTypography(page, name);

  if (testInfo.project.name !== "mobile-chrome") {
    return;
  }

  await page.evaluate(() => {
    window.scrollTo(0, 0);
    document.querySelectorAll(".app-screen--scrollable").forEach((element) => {
      element.scrollTo(0, 0);
    });
  });
  await expect(page).toHaveScreenshot(name, {
    animations: "disabled",
    fullPage: true,
  });
}

test.describe("start program flow", () => {
  test.describe.configure({ mode: "serial" });

  test.beforeEach(async ({ page }) => {
    await freezeBrowserDate(page, "2026-06-21T12:00:00-07:00");
    await page.goto("/");
    await page.waitForFunction(() => Boolean(window.__POWERJACK_AGENT__));
    await page.evaluate(async () => {
      const harness = window as unknown as {
        __POWERJACK_AGENT__?: {
          reset(): Promise<void>;
        };
      };
      await harness.__POWERJACK_AGENT__?.reset();
    });
    await page.goto("/");
  });

  test("renders the New program screen at /", async ({ page }, testInfo) => {
    await page.goto("/");

    await expect(page.locator("[data-agent-id='app-top-bar']")).toBeVisible();
    await expect(page.locator("[data-agent-id='profile-placeholder']")).toHaveCount(0);
    await expectAppLogoOppositeMenu(page);
    await expect(page.locator("[data-agent-id='app-menu-toggle']")).toBeVisible();
    await expect(page.locator("[data-agent-id='resume-workout']")).toHaveCount(0);
    await expect(page.getByRole("heading", { name: "New program" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Start new program" })).toBeVisible();
    await expect(page.locator("[data-agent-id='new-program-page']")).toBeVisible();

    const viewport = page.viewportSize();
    const homeCardBox = await page.locator("[data-agent-id='new-program-page'] .home-card").boundingBox();

    expect(viewport).not.toBeNull();
    expect(homeCardBox).not.toBeNull();

    if (viewport && homeCardBox) {
      const cardCenter = homeCardBox.x + homeCardBox.width / 2;
      expect(Math.abs(cardCenter - viewport.width / 2)).toBeLessThanOrEqual(4);
    }

    await expectMobileScreenshot(page, testInfo, "warm-stone-start-mobile.png");
  });

  test("primary routes use only standard typography sizes", async ({ page }) => {
    const routes = [
      { path: "/", screenAgentId: "new-program-page" },
      { path: "/start/select-template", screenAgentId: "select-template-page" },
      { path: "/templates", screenAgentId: "templates-page" },
      { path: "/visualization", screenAgentId: "data-visualization-page" },
      { path: "/programs", screenAgentId: "program-list-page" },
    ];

    for (const route of routes) {
      await page.goto(route.path);
      await expect(page.locator(`[data-agent-id='${route.screenAgentId}']`)).toBeVisible();
      await expectVisibleTextUsesStandardTypography(page, route.path);
    }
  });

  test("serves PowerJack favicon and install icons", async ({ request }) => {
    const favicon = await request.get("/favicon-32x32.png");
    const appleTouchIcon = await request.get("/apple-touch-icon.png");
    const manifest = await request.get("/site.webmanifest");

    expect(favicon.ok(), "favicon should be served").toBe(true);
    expect(appleTouchIcon.ok(), "Apple touch icon should be served").toBe(true);
    expect(manifest.ok(), "web app manifest should be served").toBe(true);

    const manifestJson = (await manifest.json()) as {
      icons?: Array<{ sizes?: string; src?: string; type?: string }>;
      name?: string;
      short_name?: string;
    };

    expect(manifestJson.name).toBe("PowerJack");
    expect(manifestJson.short_name).toBe("PowerJack");
    expect(manifestJson.icons).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ sizes: "192x192", src: "/icon-192.png", type: "image/png" }),
        expect.objectContaining({ sizes: "512x512", src: "/icon-512.png", type: "image/png" }),
      ]),
    );
  });

  test("Start navigates to empty Select Template", async ({ page }, testInfo) => {
    await page.goto("/");
    await page.getByRole("button", { name: "Start new program" }).click();

    await expect(page).toHaveURL(/\/start\/select-template$/);
    await expect(page.getByRole("heading", { name: "Select template" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Loading templates" })).toHaveCount(0);
    await expect(page.locator("[data-agent-id='template-empty-state']")).toBeVisible();
    await expect(page.locator("[data-agent-id='add-template']")).toBeVisible();
    await expectTemplateListHeaderAddPlacement(page, {
      addAgentId: "add-template",
      gridAgentId: "template-grid",
      titleAgentId: "select-template-title-text",
    });
    await expect(page.locator("[data-agent-id='select-template-back']")).toBeVisible();
    await expect(page.locator("[data-agent-id='select-template-next']")).toBeVisible();
    await expect(page.locator("[data-agent-id='select-template-next']")).toBeDisabled();
    await expectMobileScreenshot(page, testInfo, "warm-stone-select-template-empty-mobile.png");
  });

  test("interaction feedback flashes for buttons, selections, and text inputs", async ({
    page,
  }, testInfo) => {
    await page.goto("/");
    await expectClickInteractionFeedback(page, "[data-agent-id='app-menu-toggle']");
    await page.keyboard.press("Escape");
    await page.locator("[data-agent-id='start-new-program']").click();
    await expect(page).toHaveURL(/\/start\/select-template$/);

    await page.locator("[data-agent-id='add-template']").click();
    await page.locator("[data-agent-id='template-name-back']").focus();
    await expectFocusInteractionFeedback(page, "[data-agent-id='template-name-input']");
    await page.locator("[data-agent-id='template-name-input']").fill("Feedback Flash");
    await page.locator("[data-agent-id='template-name-next']").click();
    await selectFocusAndOpenDays(page);
    await page.locator("[data-agent-id='template-days-per-week-2']").click();
    await page.locator("[data-agent-id='template-days-per-week-next']").click();
    await addExerciseToCurrentTemplateDay(page, "bench", /Barbell Bench Press/);
    await page.locator("[data-agent-id='template-day-2']").click();
    await addExerciseToCurrentTemplateDay(page, "squat", /Barbell Back Squat/);
    await page.locator("[data-agent-id='save-template']").click();
    await expect(page).toHaveURL(/\/start\/select-template$/);
    await page.locator("[data-agent-id='select-template-next']").click();
    await expect(page).toHaveURL(/\/start\/program-length$/);

    await expectClickInteractionFeedback(page, "[data-agent-id='program-length-4']", {
      screenshotName: "interaction-feedback-program-length-mobile.png",
      testInfo,
    });
    await page.locator("[data-agent-id='program-length-next']").click();
    await expect(page).toHaveURL(/\/programs\/\d+\/workouts\/\d+$/);

    await expectFocusInteractionFeedback(page, "[data-agent-id^='set-reps-']", {
      screenshotName: "interaction-feedback-set-input-mobile.png",
      testInfo,
    });
  });

  test("Add template opens the template naming flow", async ({ page }) => {
    await page.goto("/start/select-template");
    await page.locator("[data-agent-id='add-template']").click();

    const templateNameInput = page.locator("[data-agent-id='template-name-input']");

    await expect(page).toHaveURL(/\/templates\/new\/name$/);
    await expect(page.getByRole("heading", { name: "Name your template" })).toBeVisible();
    await expect(templateNameInput).toHaveAttribute("placeholder", "My new template");
    await expect(templateNameInput).toHaveJSProperty("type", "text");
    await expect(templateNameInput).toHaveJSProperty("autocomplete", "off");
    await expect(templateNameInput).toHaveAttribute("autocorrect", "off");
    await expect(templateNameInput).toHaveAttribute("autocapitalize", "words");
    await expect(templateNameInput).toHaveJSProperty("enterKeyHint", "next");
    await expect(templateNameInput).toHaveJSProperty("spellcheck", false);
    await expect(page.locator("[data-agent-id='template-name-next']")).toBeDisabled();
  });

  test("setup navigation actions stay on one row at narrow mobile width", async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 740 });
    await page.goto("/start/select-template");

    await expectActionsOnSingleRow(page, "select-template-back", "select-template-next");

    await page.locator("[data-agent-id='add-template']").click();
    await expectActionsOnSingleRow(page, "template-name-back", "template-name-next");

    await page.locator("[data-agent-id='template-name-input']").fill("Mobile Buttons");
    await page.locator("[data-agent-id='template-name-next']").click();
    await expectActionsOnSingleRow(page, "template-muscle-focus-back", "template-muscle-focus-next");

    await page.locator(".muscle-focus-grid").getByRole("button", { name: "Back" }).click();
    await page.locator("[data-agent-id='template-muscle-focus-next']").click();
    await expectActionsOnSingleRow(page, "template-days-per-week-back", "template-days-per-week-next");
  });

  test("static setup screens fit narrow mobile height without vertical scrolling", async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 740 });
    await page.goto("/");
    await expectStaticScreenFitsViewport(page, "new-program-page", ["start-new-program"]);

    await page.goto("/start/select-template");
    await expectScreenAllowsIntentionalScroll(page, "select-template-page");

    await page.locator("[data-agent-id='add-template']").click();
    await expectStaticScreenFitsViewport(page, "template-name-page", [
      "template-name-input",
      "template-name-back",
      "template-name-next",
    ]);

    await page.locator("[data-agent-id='template-name-input']").fill("No Scroll Template");
    await page.locator("[data-agent-id='template-name-next']").click();
    await expectStaticScreenFitsViewport(page, "template-muscle-focus-page", [
      "template-focus-counter",
      "template-muscle-focus-back",
      "template-muscle-focus-next",
    ]);

    const muscleGrid = page.locator(".muscle-focus-grid");
    await muscleGrid.getByRole("button", { name: "Back" }).click();
    await muscleGrid.getByRole("button", { name: "Biceps" }).click();
    await page.locator("[data-agent-id='template-muscle-focus-next']").click();
    await expectStaticScreenFitsViewport(page, "template-days-per-week-page", [
      "template-days-per-week-options",
      "template-days-per-week-back",
      "template-days-per-week-next",
    ]);

    await page.locator("[data-agent-id='template-days-per-week-2']").click();
    await page.locator("[data-agent-id='template-days-per-week-next']").click();
    await expectStaticScreenFitsViewport(page, "template-builder-page", [
      "template-day-1",
      "template-day-2",
      "add-exercise",
      "template-builder-back",
      "save-template",
    ]);

    await addExerciseToCurrentTemplateDay(page, "bench", /Barbell Bench Press/);
    await expectScreenAllowsIntentionalScroll(page, "template-builder-page");

    await page.locator("[data-agent-id='template-day-2']").click();
    await addExerciseToCurrentTemplateDay(page, "squat", /Barbell Back Squat/);
    await page.locator("[data-agent-id='save-template']").click();
    await expect(page).toHaveURL(/\/start\/select-template$/);
    await expectScreenAllowsIntentionalScroll(page, "select-template-page");

    await page.locator("[data-agent-id='select-template-next']").click();
    await expect(page).toHaveURL(/\/start\/program-length$/);
    await expectStaticScreenFitsViewport(page, "program-length-page", [
      "program-length-4",
      "program-length-back",
      "program-length-next",
    ]);

    await page.locator("[data-agent-id='program-length-4']").click();
    await page.locator("[data-agent-id='program-length-next']").click();
    await expect(page).toHaveURL(/\/programs\/\d+\/workouts\/\d+$/);
    await expectScreenAllowsIntentionalScroll(page, "active-workout-page");
  });

  test("Name your template enforces the 24 character limit", async ({ page }, testInfo) => {
    await page.goto("/start/select-template");
    await page.locator("[data-agent-id='add-template']").click();
    await page.locator("[data-agent-id='template-name-input']").fill("A".repeat(25));

    await expect(page.locator("[data-agent-id='template-name-count']")).toContainText("25/24");
    await expect(page.locator("[data-agent-id='template-name-next']")).toBeDisabled();
    await expectMobileScreenshot(page, testInfo, "warm-stone-template-name-overflow-mobile.png");

    await page.locator("[data-agent-id='template-name-input']").fill("A".repeat(24));

    await expect(page.locator("[data-agent-id='template-name-count']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='template-name-next']")).toBeEnabled();
  });

  test("Muscle focus requires one to four selected muscles", async ({ page }, testInfo) => {
    await openTemplateFocus(page);

    await expect(page.getByRole("heading", { name: "What would you like to focus on?" })).toBeVisible();
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
    await expectMobileScreenshot(page, testInfo, "warm-stone-muscle-focus-selected-mobile.png");
    await muscleGrid.getByRole("button", { name: "Core" }).click();
    await expect(page.locator("[data-agent-id='template-focus-counter']")).toContainText("4/4");
    await expect(muscleGrid.getByRole("button", { name: "Core" })).toHaveAttribute("aria-pressed", "false");
  });

  test("Template days per week keeps all options in one row", async ({ page }, testInfo) => {
    await openTemplateFocus(page);
    await selectFocusAndOpenDays(page);

    await expect(page).toHaveURL(/\/templates\/new\/days-per-week$/);
    await expectTemplateDaysPerWeekOptionsInSingleRow(page);

    await page.locator("[data-agent-id='template-days-per-week-6']").click();
    await expect(page.locator("[data-agent-id='template-days-per-week-6']")).toHaveAttribute("aria-checked", "true");
    await expectTemplateDaysPerWeekOptionsInSingleRow(page);
    await expectMobileScreenshot(page, testInfo, "warm-stone-days-selected-mobile.png");
  });

  test("Template builder keeps every day visible without horizontal scrolling", async ({ page }) => {
    await openTemplateFocus(page);
    await selectFocusAndOpenDays(page);

    await page.locator("[data-agent-id='template-days-per-week-6']").click();
    await page.locator("[data-agent-id='template-days-per-week-next']").click();

    await expect(page).toHaveURL(/\/templates\/new\/builder$/);
    await expectTemplateBuilderDayTabsFit(page, 6);
    await page.locator("[data-agent-id='template-day-6']").click();
    await expect(page.locator("[data-agent-id='template-day-6']")).toHaveAttribute("aria-selected", "true");
    await expectTemplateBuilderDayTabsFit(page, 6);
  });

  test("Template builder keeps add exercise beside the title and aligned with day tabs", async ({
    page,
  }, testInfo) => {
    await page.setViewportSize({ width: 393, height: 852 });
    await openTemplateBuilder(page, { dayCount: 4 });

    await expectTemplateBuilderHeaderAddExercisePlacement(page, 4, {
      screenshotName: "warm-stone-builder-add-header-4-day-mobile.png",
      testInfo,
    });

    await page.locator("[data-agent-id='add-exercise']").click();
    await expect(page.locator("[data-agent-id='exercise-search-overlay']")).toBeVisible();
    await expect(page.locator("[data-agent-id='add-exercise']")).toHaveCount(0);
    await page.locator("[data-agent-id='close-exercise-search']").click();
    await expect(page.locator("[data-agent-id='add-exercise']")).toBeVisible();

    await openTemplateBuilder(page, { dayCount: 2 });
    await expectTemplateBuilderHeaderAddExercisePlacement(page, 2, {
      screenshotName: "warm-stone-builder-add-header-2-day-mobile.png",
      testInfo,
    });

    const longTitle = "Back In Action Build Day";
    await openTemplateBuilder(page, { dayCount: 4, name: longTitle });
    const safeVisibleTitleCharsMobile = await expectTemplateBuilderHeaderAddExercisePlacement(page, 4, {
      screenshotName: "warm-stone-builder-add-header-long-name-mobile.png",
      testInfo,
    });

    expect(safeVisibleTitleCharsMobile).toBeGreaterThan(0);
    expect(safeVisibleTitleCharsMobile).toBeLessThan(longTitle.length);
  });

  test("Exercise search stays below the top bar and keeps page scroll locked", async ({ page }) => {
    await openTemplateBuilder(page, { dayCount: 2 });
    await page.locator("[data-agent-id='add-exercise']").click();
    await page.setViewportSize({ width: 393, height: 520 });

    await expectExerciseSearchOverlayInsideViewport(page, "exercise-search-input", "Exercise search");

    const input = page.locator("[data-agent-id='exercise-search-input']");

    await input.fill("PUSH UP");
    await expect(page.getByRole("button", { name: /^Push Up\b/ })).toBeVisible();
    await page.getByRole("button", { name: /^Push Up\b/ }).click();
    await expect(page.locator("[data-agent-id='exercise-search-overlay']")).toHaveCount(0);

    await page.locator("[data-agent-id='add-exercise']").click();
    await expect(page.locator("[data-agent-id='template-builder-page']")).toHaveClass(
      /app-screen--scrollable/,
    );
    await expectExerciseSearchOverlayInsideViewport(page, "exercise-search-input", "Exercise search");
    await page.locator("[data-agent-id='exercise-search-input']").fill("press");
    await expect(page.locator("[data-agent-id^='exercise-result-']")).toHaveCount(8);
    await expectExerciseSearchScrollContained(page);
  });

  test("template builder limits each day to 20 exercises", async ({ page }, testInfo) => {
    test.setTimeout(60_000);
    await page.setViewportSize({ width: 393, height: 852 });
    await openTemplateBuilder(page, { dayCount: 2, name: "Twenty Lift Day" });

    for (let index = 1; index <= 20; index += 1) {
      await addExerciseToCurrentTemplateDay(page, "bench", /^Barbell Bench Press\b/);
    }

    await expect(page.locator("[data-agent-id='template-exercise-20']")).toContainText("Barbell Bench Press");
    await expect(page.locator("[data-agent-id='template-exercise-21']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='add-exercise']")).toHaveAttribute("aria-disabled", "true");

    await page.locator("[data-agent-id='add-exercise']").click({ force: true });
    await expect(page.locator("[data-agent-id='exercise-search-overlay']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='template-exercise-limit-modal']")).toContainText(
      "Workouts are limited to 20 exercises.",
    );
    await expectMobileScreenshot(page, testInfo, "warm-stone-builder-exercise-limit-modal-mobile.png");

    await page.getByRole("button", { name: "Okay" }).click();
    await expect(page.locator("[data-agent-id='template-exercise-limit-modal']")).toHaveCount(0);

    await page.locator("[data-agent-id='template-day-2']").click();
    await expect(page.locator("[data-agent-id='add-exercise']")).not.toHaveAttribute("aria-disabled", "true");
    await page.locator("[data-agent-id='add-exercise']").click();
    await expect(page.locator("[data-agent-id='exercise-search-overlay']")).toBeVisible();
  });

  test("new template saves only after every day has an exercise", async ({ page }, testInfo) => {
    await openTemplateFocus(page);
    await selectFocusAndOpenDays(page);
    await page.locator("[data-agent-id='template-days-per-week-2']").click();
    await page.locator("[data-agent-id='template-days-per-week-next']").click();

    await expect(page).toHaveURL(/\/templates\/new\/builder$/);
    await expect(page.locator("[data-agent-id='template-builder-back']")).toBeVisible();
    await expect(page.locator("[data-agent-id='save-template']")).toBeVisible();
    await expect(page.locator("[data-agent-id='save-template']")).toBeDisabled();

    await page.locator("[data-agent-id='add-exercise']").click();
    await expect(page.locator("[data-agent-id='exercise-search-overlay']")).toBeVisible();
    await expect(page.locator("[data-agent-id^='exercise-result-']")).toHaveCount(0);

    const viewportBeforeKeyboardProbe = page.viewportSize();
    await page.setViewportSize({ width: 393, height: 520 });
    await expectExerciseSearchInputStableAfterBackspace(page, "exercise-search-input");
    await expectMobileScreenshot(page, testInfo, "warm-stone-builder-search-mobile.png");
    if (viewportBeforeKeyboardProbe) {
      await page.setViewportSize(viewportBeforeKeyboardProbe);
    }

    await page.getByRole("button", { name: /Barbell Bench Press/ }).click();
    await expect(page.locator("[data-agent-id='exercise-search-overlay']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='save-template']")).toBeDisabled();
    await expectMobileScreenshot(page, testInfo, "warm-stone-builder-filled-mobile.png");

    await page.locator("[data-agent-id='template-day-2']").click();
    await page.locator("[data-agent-id='add-exercise']").click();
    await expect(page.locator("[data-agent-id='exercise-search-overlay']")).toBeVisible();
    await page.locator("[data-agent-id='exercise-search-input']").fill("squat");
    await expectExerciseSearchResultsInsideViewport(page);
    await page.getByRole("button", { name: /Barbell Back Squat/ }).click();
    await expect(page.locator("[data-agent-id='exercise-search-overlay']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='save-template']")).toBeEnabled();
    await page.locator("[data-agent-id='save-template']").click();

    await expect(page).toHaveURL(/\/start\/select-template$/);
    await expect(page.locator("[data-agent-id='template-row-1']")).toContainText("Back In Action");
    await expect(page.locator("[data-agent-id='template-focus-chip-1']")).toContainText("Back");
    await expect(page.locator("[data-agent-id='template-focus-chip-2']")).toContainText("Biceps");
    await expect(page.locator("[data-agent-id='template-row-1']")).toHaveAttribute("aria-selected", "true");
  });

  test("template builder copies one day to another without changing the active day", async ({
    page,
  }, testInfo) => {
    await openTemplateFocus(page, "Copy Builder");
    await selectFocusAndOpenDays(page);
    await page.locator("[data-agent-id='template-days-per-week-4']").click();
    await page.locator("[data-agent-id='template-days-per-week-next']").click();

    await expect(page.locator("[data-agent-id='template-day-copy']")).toHaveCount(0);
    await addExerciseToCurrentTemplateDay(page, "leg press", /^Leg Press Quads - Leg Press$/);
    await addExerciseToCurrentTemplateDay(page, "leg extension", /^Machine Leg Extension Quads - Machine$/);
    await expect(page.locator("[data-agent-id='template-day-copy']")).toBeVisible();
    await expect(page.locator("[data-agent-id='template-day-copy']")).toContainText("Copy exercises");

    await page.locator("[data-agent-id='template-day-copy']").click();
    await expect(page.locator("[data-agent-id='copy-day-modal']")).toContainText("Copy exercises to what day?");
    await expect(page.locator("[data-agent-id='copy-day-modal']")).toContainText(
      "Replaces all exercise for selected day.",
    );
    await expect(page.locator("[data-agent-id='copy-day-target-1']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='copy-day-target-2']")).toBeVisible();
    await expect(page.locator("[data-agent-id='copy-day-target-3']")).toBeVisible();
    await expect(page.locator("[data-agent-id='copy-day-target-4']")).toBeVisible();
    await expectCopyDayModalCenteredInViewport(page);
    await expectMobileScreenshot(page, testInfo, "warm-stone-copy-day-modal-mobile.png");

    await page.locator("[data-agent-id='copy-day-cancel']").click();
    await expect(page.locator("[data-agent-id='copy-day-modal']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='template-day-1']")).toHaveAttribute("aria-selected", "true");

    await page.locator("[data-agent-id='template-day-2']").click();
    await addExerciseToCurrentTemplateDay(page, "bench", /^Barbell Bench Press/);
    await page.locator("[data-agent-id='template-day-3']").click();
    await addExerciseToCurrentTemplateDay(page, "squat", /^Barbell Back Squat/);
    await page.locator("[data-agent-id='template-day-4']").click();
    await addExerciseToCurrentTemplateDay(page, "row", /^Barbell Bent Over Row/);

    await page.locator("[data-agent-id='template-day-1']").click();
    await page.locator("[data-agent-id='template-day-copy']").click();
    await page.locator("[data-agent-id='copy-day-target-3']").click();
    await expect(page.locator("[data-agent-id='copy-day-modal']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='template-day-1']")).toHaveAttribute("aria-selected", "true");
    await expect(page.locator("[data-agent-id='save-template']")).toBeEnabled();

    await page.locator("[data-agent-id='template-day-3']").click();
    await expect(page.locator("[data-agent-id='template-exercise-1']")).toContainText("Leg Press");
    await expect(page.locator("[data-agent-id='template-exercise-2']")).toContainText("Machine Leg Extension");
    await expect(page.locator("[data-agent-id='template-exercise-3']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='template-builder-page']")).not.toContainText("Barbell Back Squat");
  });

  test("top chrome menu opens and navigates to new flows", async ({ page }, testInfo) => {
    await page.goto("/");
    await page.locator("[data-agent-id='app-menu-toggle']").click();

    await expect(page.locator("[data-agent-id='app-menu']")).toBeVisible();
    await expect(page.locator("[data-agent-id='app-menu'] button")).toHaveText([
      "Current Program",
      "Data Visualization",
      "Programs",
      "Templates",
    ]);
    await expectMobileScreenshot(page, testInfo, "warm-stone-nav-menu-mobile.png");
    await page.locator("[data-agent-id='menu-data-visualization']").click();
    await expect(page).toHaveURL(/\/visualization$/);
    await expect(page.locator("[data-agent-id='visualization-empty-state']")).toBeVisible();
    await expect(page.locator("[data-agent-id='visualization-chart-trigger']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='data-visualization-page']")).not.toContainText(/No change vs/i);
    await expectScreenAllowsIntentionalScroll(page, "data-visualization-page");

    await page.locator("[data-agent-id='app-menu-toggle']").click();
    await page.locator("[data-agent-id='menu-templates']").click();
    await expect(page).toHaveURL(/\/templates$/);
    await expect(page.locator("[data-agent-id='templates-empty-state']")).toBeVisible();
    await expectScreenAllowsIntentionalScroll(page, "templates-page");
    await expect(page.locator("[data-agent-id='app-top-bar']")).toBeVisible();

    await page.locator("[data-agent-id='app-menu-toggle']").click();
    await page.locator("[data-agent-id='menu-programs']").click();
    await expect(page).toHaveURL(/\/programs$/);
    await expect(page.locator("[data-agent-id='program-list-empty-state']")).toBeVisible();
    await expectScreenAllowsIntentionalScroll(page, "program-list-page");
    await page.locator("[data-agent-id='program-list-new-program']").click();
    await expect(page).toHaveURL(/\/start\/select-template$/);

    await page.locator("[data-agent-id='app-menu-toggle']").click();
    await expect(page.locator("[data-agent-id='app-menu']")).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(page.locator("[data-agent-id='app-menu']")).toHaveCount(0);
  });

  test("Templates page lists and manages templates outside new-program selection", async ({
    page,
  }, testInfo) => {
    await page.goto("/templates");

    await expect(page.getByRole("heading", { name: "Templates", exact: true })).toBeVisible();
    await expect(page.locator("[data-agent-id='templates-empty-state']")).toBeVisible();
    await expect(page.locator("[data-agent-id='templates-add-template']")).toBeVisible();
    await expectTemplateListHeaderAddPlacement(page, {
      addAgentId: "templates-add-template",
      gridAgentId: "templates-grid",
      titleAgentId: "templates-title-text",
    });
    await expectMobileScreenshot(page, testInfo, "warm-stone-templates-empty-mobile.png");

    await createTwoDayTemplateFromTemplatesPage(page, "List Managed");

    await expect(page.locator("[data-agent-id='templates-template-row-1']")).toContainText("List Managed");
    await page.locator("[data-agent-id='templates-template-row-1'] .template-row__select--static").click();
    await expect(page).toHaveURL(/\/templates$/);

    await page.goto("/start/select-template");
    await expect(page.locator("[data-agent-id='template-row-1']")).toContainText("List Managed");
    await expect(page.locator("[data-agent-id='select-template-next']")).toBeDisabled();

    await page.goto("/templates");
    await page.locator("[data-agent-id='templates-edit-template-1']").click();
    await expect(page).toHaveURL(/\/templates\/new\/name$/);
    await expect(page.locator("[data-agent-id='template-name-input']")).toHaveValue("List Managed");
    await page.locator("[data-agent-id='template-name-input']").fill("List Updated");
    await page.locator("[data-agent-id='template-name-next']").click();
    await expect(page.locator("[data-agent-id='template-focus-counter']")).toContainText("2/4");
    await page.locator("[data-agent-id='template-muscle-focus-next']").click();
    await expect(page.locator("[data-agent-id='template-days-per-week-2']")).toHaveAttribute(
      "aria-checked",
      "true",
    );
    await page.locator("[data-agent-id='template-days-per-week-next']").click();
    await expect(page.locator("[data-agent-id='save-template']")).toBeEnabled();
    await page.locator("[data-agent-id='save-template']").click();
    await expect(page).toHaveURL(/\/templates$/);
    await expect(page.locator("[data-agent-id='templates-template-row-1']")).toContainText("List Updated");

    await page.locator("[data-agent-id='templates-delete-template-1']").click();
    await expect(page.locator("[data-agent-id='template-delete-confirmation']")).toContainText(
      "Confirm deleting template List Updated",
    );
    await page.locator("[data-agent-id='modal-delete']").click();
    await expect(page.locator("[data-agent-id='templates-empty-state']")).toBeVisible();
    await expect(page.locator("[data-agent-id='templates-template-row-1']")).toHaveCount(0);
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
    await expect(page.locator("[data-agent-id^='visualization-bar-']").filter({ hasText: "Chest" })).toContainText("Chest");

    await page.locator("[data-agent-id='visualization-chart-trigger']").click();
    await expect(page.locator("[data-agent-id='visualization-view-menu']").getByRole("menuitemradio")).toHaveCount(2);
    await expect(page.locator("[data-agent-id='visualization-view-sparklines']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='visualization-view-compare']")).toHaveCount(0);
    await page.locator("[data-agent-id='visualization-view-heatmap']").click();
    await expect(page.locator("[data-agent-id='visualization-heatmap']")).toContainText("Chest");
    await expect(page.locator("[data-agent-id='visualization-chart-trigger']")).toContainText("Heatmap");
    await expect(page.locator("[data-agent-id='visualization-heatmap-legend']")).toContainText("Growth");

    await page.locator("[data-agent-id='visualization-chart-trigger']").click();
    await page.locator("[data-agent-id='visualization-view-bars']").click();
    await expect(page.locator("[data-agent-id^='visualization-bar-']").filter({ hasText: "Chest" })).toHaveAttribute(
      "data-volume-band",
      "not-ideal",
    );
    await expect(page.locator("[data-agent-id='visualization-bar-legend']")).toContainText("Maintenance");

    await page.locator("[data-agent-id='visualization-range-year']").click();
    await expect(page.locator("[data-agent-id='visualization-period-label']")).toContainText(
      new Date().getFullYear().toString(),
    );
    await expect(page.locator("[data-agent-id='visualization-chart-trigger']")).toContainText("Bars");
  });

  test("Data Visualization keeps period navigation inside available dates", async ({ page }) => {
    await freezeBrowserDate(page, "2026-06-21T12:00:00-07:00");

    await page.goto("/visualization?range=month&start=2026-06-01&view=bars");
    await expect(page.locator("[data-agent-id='visualization-period-label']")).toContainText("June 2026");
    await expect(page.locator("[data-agent-id='visualization-next-period']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='visualization-previous-period']")).toBeVisible();

    await page.locator("[data-agent-id='visualization-previous-period']").click();
    await expect(page.locator("[data-agent-id='visualization-period-label']")).toContainText("May 2026");
    await expect(page.locator("[data-agent-id='visualization-next-period']")).toBeVisible();

    await page.goto("/visualization?range=month&start=2026-01-01&view=bars");
    await expect(page.locator("[data-agent-id='visualization-period-label']")).toContainText("January 2026");
    await expect(page.locator("[data-agent-id='visualization-previous-period']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='visualization-next-period']")).toBeVisible();

    await page.goto("/visualization?range=quarter&start=2026-07-01&view=bars");
    await expect(page.locator("[data-agent-id='visualization-period-label']")).toContainText("Q2 2026");
    await expect(page.locator("[data-agent-id='visualization-next-period']")).toHaveCount(0);

    await page.goto("/visualization?range=year&start=2027-01-01&view=bars");
    await expect(page.locator("[data-agent-id='visualization-period-label']")).toContainText("2026");
    await expect(page.locator("[data-agent-id='visualization-next-period']")).toHaveCount(0);

    await page.goto("/visualization?range=week&start=2026-01-01&view=bars");
    await expect(page.locator("[data-agent-id='visualization-period-label']")).toContainText("Jan 1-4, 2026");
    await expect(page.locator("[data-agent-id='visualization-previous-period']")).toHaveCount(0);
  });

  test("completed secondary muscles count as half sets in volume views", async ({ page }) => {
    await createWeightedVolumeTemplate(page);
    await startSelectedProgram(page, 4);
    await completeLiftWithFeedback(page, "Barbell Deadlift");
    await completeLiftWithFeedback(page, "Pull Up");
    await completeLiftWithFeedback(page, "Cable Lat Pulldown");
    await completeLiftWithFeedback(page, "Cable Rear Delt Fly");
    await expect(page.locator("[data-agent-id='finish-workout']")).toBeVisible();
    await page.locator("[data-agent-id='finish-workout']").click();
    await expect(page.locator("[data-agent-id='workout-day-title']")).toContainText("Day 2");

    await page.locator("[data-agent-id='app-menu-toggle']").click();
    await page.locator("[data-agent-id='menu-current-program']").click();
    await expect(page).toHaveURL(/\/programs\/\d+$/);

    const programVolumeRows = page.locator("[data-agent-id^='program-volume-row-']");
    const volumeLegend = page.locator("[data-agent-id='program-volume-legend']");

    await expect(programVolumeRows.filter({ hasText: "Back" })).toContainText("6.0");
    await expect(programVolumeRows.filter({ hasText: "Back" })).toHaveAttribute("data-volume-band", "growth");
    await expect(programVolumeRows.filter({ hasText: "Back" })).toHaveAttribute("aria-label", /Growth/);
    await expect(programVolumeRows.filter({ hasText: "Glutes" })).toContainText("2.0");
    await expect(programVolumeRows.filter({ hasText: "Glutes" })).toHaveAttribute("data-volume-band", "not-ideal");
    await expect(programVolumeRows.filter({ hasText: "Shoulders" })).toContainText("2.0");
    await expect(programVolumeRows.filter({ hasText: "Shoulders" })).toHaveAttribute("data-volume-band", "not-ideal");
    await expect(programVolumeRows.filter({ hasText: "Biceps" })).toContainText("2.0");
    await expect(programVolumeRows.filter({ hasText: "Biceps" })).toHaveAttribute("data-volume-band", "not-ideal");
    await expect(programVolumeRows.filter({ hasText: "Forearms" })).toContainText("3.0");
    await expect(programVolumeRows.filter({ hasText: "Forearms" })).toHaveAttribute("data-volume-band", "not-ideal");
    await expect(volumeLegend).toContainText("Not Ideal");
    await expect(volumeLegend).toContainText("Maintenance");
    await expect(volumeLegend).toContainText("Growth");
    await expect(volumeLegend).toContainText("Max Growth");
    await expect(volumeLegend).toContainText("Overtraining");
    expect(await pageHasHorizontalOverflow(page)).toBe(false);

    await page.locator("[data-agent-id='app-menu-toggle']").click();
    await page.locator("[data-agent-id='menu-data-visualization']").click();
    await expect(page).toHaveURL(/\/visualization/);
    await expect(page.locator("[data-agent-id='visualization-total']")).toContainText("8.0");

    const visualizationRows = page.locator("[data-agent-id^='visualization-bar-']");
    await expect(visualizationRows.filter({ hasText: "Back" })).toContainText("6.0");
    await expect(visualizationRows.filter({ hasText: "Back" })).toHaveAttribute("data-volume-band", "growth");
    await expect(visualizationRows.filter({ hasText: "Glutes" })).toContainText("2.0");
    await expect(visualizationRows.filter({ hasText: "Shoulders" })).toContainText("2.0");
    await expect(visualizationRows.filter({ hasText: "Biceps" })).toContainText("2.0");
    await expect(visualizationRows.filter({ hasText: "Forearms" })).toContainText("3.0");
    expect(await pageHasHorizontalOverflow(page)).toBe(false);
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
    await expect(page.locator("[data-agent-id^='program-volume-row-']").filter({ hasText: "Chest" })).toContainText("Chest");
    expect(await pageHasHorizontalOverflow(page)).toBe(false);

    if (testInfo.project.name === "mobile-chrome") {
      await page.evaluate(() => window.scrollTo(0, 0));
      await expect(page).toHaveScreenshot("current-program-overview-mobile.png", {
        animations: "disabled",
        fullPage: true,
      });
    }
  });

  test("Programs list pins active programs and filters history", async ({ page }, testInfo) => {
    await freezeBrowserDate(page, "2026-06-21T12:00:00-07:00");

    await createTwoDayTemplate(page, "List Check");
    await startSelectedProgram(page, 4);
    await completeVisibleWorkout(page);

    await page.locator("[data-agent-id='app-menu-toggle']").click();
    await page.locator("[data-agent-id='menu-programs']").click();
    await expect(page).toHaveURL(/\/programs$/);
    await expect(page.locator("[data-agent-id='program-card-1']")).toContainText("List Check x1");
    await expect(page.locator("[data-agent-id='program-card-1']")).toContainText("Current program");
    await expect(page.locator("[data-agent-id='program-card-1']")).toContainText("Active");

    await page.locator("[data-agent-id='program-filter-completed']").click();
    await expect(page.locator("[data-agent-id='program-list-empty-state']")).toBeVisible();

    await page.locator("[data-agent-id='program-filter-all']").click();
    await page.locator("[data-agent-id='program-list-new-program']").click();
    await page.locator("[data-agent-id='template-row-1'] .template-row__select").click();
    await page.locator("[data-agent-id='select-template-next']").click();
    await page.locator("[data-agent-id='program-length-4']").click();
    await page.locator("[data-agent-id='program-length-next']").click();
    await page.locator("[data-agent-id='modal-confirm']").click();
    await expect(page).toHaveURL(/\/programs\/\d+\/workouts\/\d+$/);

    await page.locator("[data-agent-id='app-menu-toggle']").click();
    await page.locator("[data-agent-id='menu-programs']").click();

    const cards = page.locator("[data-agent-id='program-card-list'] > [data-agent-id^='program-card-']");
    await expect(cards.nth(0)).toContainText("List Check x2");
    await expect(cards.nth(0)).toContainText("Current program");
    await expect(cards.nth(1)).toContainText("List Check x1");
    await expect(cards.nth(1)).toContainText("Halted");
    expect(await pageHasHorizontalOverflow(page)).toBe(false);

    if (testInfo.project.name === "mobile-chrome") {
      await page.evaluate(() => window.scrollTo(0, 0));
      await expect(page).toHaveScreenshot("program-list-mobile.png", {
        animations: "disabled",
        fullPage: true,
      });
    }

    await page.locator("[data-agent-id='program-filter-halted']").click();
    await expect(page.locator("[data-agent-id='program-card-1']")).toBeVisible();
    await expect(page.locator("[data-agent-id='program-card-list']")).not.toContainText("List Check x2");

    await page.locator("[data-agent-id='program-filter-completed']").click();
    await expect(page.locator("[data-agent-id='program-list-empty-state']")).toBeVisible();

    await page.locator("[data-agent-id='program-filter-halted']").click();
    await page.locator("[data-agent-id='program-card-details-1']").click();
    await expect(page).toHaveURL(/\/programs\/1$/);
    await expect(page.locator("[data-agent-id='current-program-page']")).toBeVisible();
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
    await expectTemplateBuilderModeLabelBelowTitle(page, "Edit template");
    await expect(page.locator("[data-agent-id='template-exercise-1']")).toContainText("Barbell Bench Press");
    await page.locator("[data-agent-id='save-template']").click();

    await expect(page).toHaveURL(/\/start\/select-template$/);
    await expect(page.locator("[data-agent-id='template-row-1']")).toContainText("Managed Template");
    await expect(page.locator("[data-agent-id='template-row-2']")).toHaveCount(0);

    await page.locator("[data-agent-id='delete-template-1']").click();
    await expect(page.locator("[data-agent-id='template-delete-confirmation']")).toContainText(
      "Confirm deleting template Managed Template",
    );
    await page.locator("[data-agent-id='modal-delete']").click();
    await expect(page.locator("[data-agent-id='template-empty-state']")).toBeVisible();
    await expect(page.locator("[data-agent-id='template-row-1']")).toHaveCount(0);
  });

  test("saved template starts a program and opens the active workout", async ({ page }, testInfo) => {
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
    await expect(page.getByRole("heading", { name: "How many weeks do you want to train?" })).toBeVisible();
    await page.locator("[data-agent-id='program-length-8']").click();

    await expect(page.locator("[data-agent-id='program-length-next']")).toBeEnabled();
    await expect(page.locator("[data-agent-id='program-length-next']")).toContainText("Start");
    await page.locator("[data-agent-id='program-length-next']").click();

    await expect(page).toHaveURL(/\/programs\/\d+\/workouts\/\d+$/);
    await expect(page.locator("[data-agent-id='active-workout-page']")).toBeVisible();
    await expect(page.locator("[data-agent-id='workout-week-label']")).toContainText("Week 1/8");
    await expect(page.locator("[data-agent-id='workout-day-title']")).toContainText("Day 1");
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("0% done");
    await expect(page.getByRole("heading", { name: "Barbell Bench Press" })).toBeVisible();
    await expect(page.locator("[data-agent-id='resume-workout']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id^='set-reps-']")).toHaveCount(2);
    await expect(page.locator("[data-agent-id^='set-weight-']")).toHaveCount(2);
    await expectMobileScreenshot(page, testInfo, "warm-stone-active-workout-empty-mobile.png");

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
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toHaveCount(0);
    await expect(page.locator(".workout-header__progress-separator")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='workout-state']")).toContainText("Read-only");
    await expectResumeCenteredBeforeIcons(page);
    await page.locator("[data-agent-id='resume-workout']").click();
    await expect(page).toHaveURL(canonicalDayOneUrl);

    await expect(page.locator("[data-agent-id='workout-day-title']")).toContainText("Day 1");
    await expect(page.locator("[data-agent-id='resume-workout']")).toHaveCount(0);
  });

  test("active program shows resume and replacement confirmation blocks accidental starts", async ({ page }, testInfo) => {
    await createTwoDayTemplate(page, "Replace Me");
    await startSelectedProgram(page, 8);

    const firstProgramUrl = page.url();
    await expect(page.locator("[data-agent-id='resume-workout']")).toHaveCount(0);

    await page.locator("[data-agent-id='app-menu-toggle']").click();
    await page.locator("[data-agent-id='menu-templates']").click();
    await expect(page).toHaveURL(/\/templates$/);
    await expect(page.locator("[data-agent-id='templates-template-row-1']")).toContainText(
      "Active program template",
    );
    await expect(page.locator("[data-agent-id='templates-delete-template-1']")).toHaveAttribute(
      "aria-disabled",
      "true",
    );

    await page.locator("[data-agent-id='templates-delete-template-1']").click({ force: true });
    await expect(page.locator("[data-agent-id='template-in-use-dialog']")).toContainText(
      "Cannot delete templates in use by active program",
    );
    await page.locator("[data-agent-id='modal-back']").click();

    await page.locator("[data-agent-id='templates-edit-template-1']").click();
    await expect(page.locator("[data-agent-id='template-active-edit-confirmation']")).toContainText(
      "Editing an active template will adjust progression of all remaining weeks of program.",
    );
    await page.locator("[data-agent-id='modal-back']").click();
    await expect(page).toHaveURL(/\/templates$/);

    await page.locator("[data-agent-id='templates-edit-template-1']").click();
    await page.locator("[data-agent-id='modal-confirm']").click();
    await expect(page).toHaveURL(/\/templates\/new\/name$/);
    await page.locator("[data-agent-id='template-name-back']").click();
    await expect(page).toHaveURL(/\/templates$/);

    await page.locator("[data-agent-id='app-menu-toggle']").click();
    await page.locator("[data-agent-id='menu-programs']").click();
    await expect(page).toHaveURL(/\/programs$/);
    await expect(page.locator("[data-agent-id='program-card-1']")).toContainText("Replace Me x1");
    await page.locator("[data-agent-id='program-list-new-program']").click();
    await expect(page).toHaveURL(/\/start\/select-template$/);
    await expectResumeCenteredBeforeIcons(page);

    await expect(page.locator("[data-agent-id='template-row-1']")).toContainText("Active program template");
    await expect(page.locator("[data-agent-id='template-row-1']")).not.toContainText("Locked");
    await expect(page.locator("[data-agent-id='edit-template-1']")).not.toHaveAttribute("aria-disabled", "true");
    await expect(page.locator("[data-agent-id='delete-template-1']")).toHaveAttribute(
      "aria-disabled",
      "true",
    );
    await expectMobileScreenshot(page, testInfo, "warm-stone-select-template-active-mobile.png");

    await page.locator("[data-agent-id='delete-template-1']").click({ force: true });
    await expect(page.locator("[data-agent-id='template-in-use-dialog']")).toContainText(
      "Cannot delete templates in use by active program",
    );
    await page.locator("[data-agent-id='modal-back']").click();

    await page.locator("[data-agent-id='edit-template-1']").click();
    await expect(page.locator("[data-agent-id='template-active-edit-confirmation']")).toContainText(
      "Editing an active template will adjust progression of all remaining weeks of program.",
    );
    await expect(page.locator("[data-agent-id='template-active-edit-confirmation']")).toContainText(
      "Does not affect current week.",
    );
    await page.locator("[data-agent-id='modal-back']").click();
    await expect(page).toHaveURL(/\/start\/select-template$/);

    await page.locator("[data-agent-id='edit-template-1']").click();
    await page.locator("[data-agent-id='modal-confirm']").click();
    await expect(page).toHaveURL(/\/templates\/new\/name$/);
    await expect(page.locator("[data-agent-id='template-name-input']")).toHaveValue("Replace Me");
    await page.locator("[data-agent-id='template-name-back']").click();
    await expect(page).toHaveURL(/\/start\/select-template$/);

    await page.locator("[data-agent-id='template-row-1'] .template-row__select").click();
    await page.locator("[data-agent-id='select-template-next']").click();
    await page.locator("[data-agent-id='program-length-4']").click();
    await expectMobileScreenshot(page, testInfo, "warm-stone-program-length-selected-mobile.png");
    await page.locator("[data-agent-id='program-length-next']").click();
    await expect(page.locator("[data-agent-id='program-replace-confirmation']")).toContainText(
      "Halt current program and start new one",
    );
    await expectMobileScreenshot(page, testInfo, "warm-stone-replace-program-dialog-mobile.png");
    await page.locator("[data-agent-id='modal-back']").click();
    await expect(page).toHaveURL(/\/start\/program-length$/);

    await page.locator("[data-agent-id='program-length-next']").click();
    await page.locator("[data-agent-id='modal-confirm']").click();
    await expect(page).toHaveURL(/\/programs\/\d+\/workouts\/\d+$/);
    expect(page.url()).not.toBe(firstProgramUrl);
    await expect(page.locator("[data-agent-id='resume-workout']")).toHaveCount(0);

    await page.locator("[data-agent-id='app-menu-toggle']").click();
    await page.locator("[data-agent-id='menu-programs']").click();
    await expect(page).toHaveURL(/\/programs$/);
    await page.locator("[data-agent-id='program-list-new-program']").click();
    await expect(page).toHaveURL(/\/start\/select-template$/);
    await expectResumeCenteredBeforeIcons(page);
    await page.locator("[data-agent-id='resume-workout']").click();
    await expect(page).toHaveURL(/\/programs\/\d+\/workouts\/\d+$/);
    await expect(page.locator("[data-agent-id='resume-workout']")).toHaveCount(0);
  });

  test("template builder reorders and replaces exercises before saving", async ({ page }, testInfo) => {
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

    await expect(page.locator("[data-agent-id='template-exercise-drag-1'] .builder-exercise-row__order")).toHaveText(
      "1",
    );
    await expect(page.locator("[data-agent-id='template-exercise-drag-1'] svg")).toHaveCount(0);

    await page.locator("[data-agent-id='remove-template-exercise-2']").click();
    await expect(page.locator("[data-agent-id='template-exercise-2']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='template-exercise-1']")).toContainText("Barbell Bench Press");

    await page.locator("[data-agent-id='add-exercise']").click();
    await expect(page.locator("[data-agent-id^='exercise-result-']")).toHaveCount(0);
    await page.locator("[data-agent-id='exercise-search-input']").fill("squat");
    await page.getByRole("button", { name: /Barbell Back Squat/ }).click();

    await expect(page.locator("[data-agent-id='template-exercise-1']")).toContainText("Barbell Bench Press");
    await expect(page.locator("[data-agent-id='template-exercise-2']")).toContainText("Barbell Back Squat");
    await expect(page.locator("[data-agent-id='template-exercise-drag-2'] .builder-exercise-row__order")).toHaveText(
      "2",
    );
    await expect(page.locator("[data-agent-id='template-exercise-drag-2'] svg")).toHaveCount(0);

    await page.locator("[data-agent-id='edit-template-exercise-1']").click();
    await expect(page.locator("[data-agent-id='exercise-search-overlay']")).toBeVisible();
    await expect(page.locator("[data-agent-id='edit-exercise-search-input-1']")).toBeVisible();
    await expect(page.locator("[data-agent-id^='replace-exercise-result-']")).toHaveCount(0);
    await page.locator("[data-agent-id='edit-exercise-search-input-1']").fill("pull-up");
    await expectExerciseSearchResultsInsideViewport(page);
    await page.getByRole("button", { name: /^Pull Up/ }).click();
    await expect(page.locator("[data-agent-id='exercise-search-overlay']")).toHaveCount(0);

    await expect(page.locator("[data-agent-id='template-exercise-1']")).toContainText("Pull Up");
    await expect(page.locator("[data-agent-id='template-exercise-2']")).toContainText("Barbell Back Squat");

    const firstDragZone = page.locator("[data-agent-id='template-exercise-drag-1']");
    const secondDragZone = page.locator("[data-agent-id='template-exercise-drag-2']");
    const firstDragBox = await firstDragZone.boundingBox();
    const secondDragBox = await secondDragZone.boundingBox();

    expect(firstDragBox).not.toBeNull();
    expect(secondDragBox).not.toBeNull();

    if (firstDragBox && secondDragBox) {
      await page.mouse.move(secondDragBox.x + secondDragBox.width * 0.6, secondDragBox.y + secondDragBox.height / 2);
      await page.mouse.down();
      await page.mouse.move(secondDragBox.x + secondDragBox.width * 0.6, secondDragBox.y - 12);
      await page.mouse.move(firstDragBox.x + firstDragBox.width * 0.6, firstDragBox.y + firstDragBox.height / 2, {
        steps: 12,
      });
      await expect(page.locator("[data-agent-id='template-exercise-2']")).toHaveAttribute(
        "data-reorder-state",
        "moving",
      );
      await expect(page.locator("[data-agent-id='template-exercise-1']")).toHaveAttribute(
        "data-reorder-state",
        "idle",
      );

      if (testInfo.project.name === "mobile-chrome") {
        await expect(page).toHaveScreenshot("warm-stone-builder-reorder-feedback-mobile.png", {
          animations: "disabled",
          fullPage: true,
        });
      }

      await page.mouse.up();
    }

    await expect(page.locator("[data-agent-id='template-exercise-1']")).toContainText("Barbell Back Squat");
    await expect(page.locator("[data-agent-id='template-exercise-2']")).toContainText("Pull Up");
    await expect(page.locator("[data-agent-id='template-exercise-1']")).toHaveAttribute(
      "data-reorder-state",
      "idle",
      { timeout: 500 },
    );
    await expect(page.locator("[data-agent-id='template-exercise-2']")).toHaveAttribute(
      "data-reorder-state",
      "idle",
      { timeout: 500 },
    );

    await page.waitForTimeout(200);

    const refreshedFirstDragZone = page.locator("[data-agent-id='template-exercise-drag-1']");
    const refreshedSecondDragZone = page.locator("[data-agent-id='template-exercise-drag-2']");
    const refreshedFirstDragBox = await refreshedFirstDragZone.boundingBox();
    const refreshedSecondDragBox = await refreshedSecondDragZone.boundingBox();

    expect(refreshedFirstDragBox).not.toBeNull();
    expect(refreshedSecondDragBox).not.toBeNull();

    if (refreshedFirstDragBox && refreshedSecondDragBox) {
      const refreshedFirstCenterX = refreshedFirstDragBox.x + refreshedFirstDragBox.width / 2;
      const refreshedFirstCenterY = refreshedFirstDragBox.y + refreshedFirstDragBox.height / 2;
      const refreshedSecondCenterX = refreshedSecondDragBox.x + refreshedSecondDragBox.width / 2;
      const refreshedSecondCenterY = refreshedSecondDragBox.y + refreshedSecondDragBox.height / 2;

      await page.mouse.move(refreshedFirstCenterX, refreshedFirstCenterY);
      await page.mouse.down();
      await page.mouse.move(refreshedFirstCenterX, refreshedFirstCenterY + 18, { steps: 4 });
      await expect(page.locator("[data-agent-id='template-exercise-1']")).toHaveAttribute(
        "data-reorder-state",
        "moving",
      );
      await expect(page.locator("[data-agent-id='template-exercise-2']")).toHaveAttribute(
        "data-reorder-state",
        "idle",
      );
      await page.mouse.move(refreshedSecondCenterX, refreshedSecondCenterY, {
        steps: 12,
      });
      await page.mouse.up();
    }

    await expect(page.locator("[data-agent-id='template-exercise-1']")).toContainText("Pull Up");
    await expect(page.locator("[data-agent-id='template-exercise-2']")).toContainText("Barbell Back Squat");
    await expect(page.locator("[data-agent-id='template-exercise-1']")).toHaveAttribute(
      "data-reorder-state",
      "idle",
      { timeout: 500 },
    );
    await expect(page.locator("[data-agent-id='template-exercise-2']")).toHaveAttribute(
      "data-reorder-state",
      "idle",
      { timeout: 500 },
    );

    await page.waitForTimeout(200);
    await page.locator("[data-agent-id='template-day-2']").click();
    await expect(page.locator("[data-agent-id='template-day-2']")).toHaveAttribute("aria-selected", "true");
    await page.locator("[data-agent-id='add-exercise']").click();
    await page.locator("[data-agent-id='exercise-search-input']").fill("row");
    await page.getByRole("button", { name: /Barbell Bent Over Row/ }).click();
    await expect(page.locator("[data-agent-id='template-exercise-1']")).toContainText("Barbell Bent Over Row");
    await page.locator("[data-agent-id='template-day-1']").click();
    await expect(page.locator("[data-agent-id='template-day-1']")).toHaveAttribute("aria-selected", "true");

    await page.locator("[data-agent-id='save-template']").click();
    await expect(page).toHaveURL(/\/start\/select-template$/);
    await page.locator("[data-agent-id='select-template-next']").click();
    await page.locator("[data-agent-id='program-length-4']").click();
    await page.locator("[data-agent-id='program-length-next']").click();

    await expect(page).toHaveURL(/\/programs\/\d+\/workouts\/\d+$/);
    await expect(page.locator("[data-agent-id^='lift-card-']").nth(0)).toContainText("Pull Up");
    await expect(page.locator("[data-agent-id^='lift-card-']").nth(1)).toContainText("Barbell Back Squat");
  });

  test("template builder confirms filled day removal and keeps retained exercises visible", async ({ page }) => {
    await openTemplateFocus(page, "Shrink Leg Day");
    await selectFocusAndOpenDays(page);
    await page.locator("[data-agent-id='template-days-per-week-4']").click();
    await page.locator("[data-agent-id='template-days-per-week-next']").click();

    await addExerciseToCurrentTemplateDay(page, "leg press", /^Leg Press Quads - Leg Press$/);
    await addExerciseToCurrentTemplateDay(page, "leg extension", /^Machine Leg Extension Quads - Machine$/);
    await addExerciseToCurrentTemplateDay(page, "seated leg curl", /^Machine Seated Leg Curl Hamstrings - Machine$/);
    await addExerciseToCurrentTemplateDay(page, "lying leg curl", /^Machine Lying Leg Curl Hamstrings - Machine$/);
    await expect(page.locator("[data-agent-id='template-exercise-4']")).toContainText("Machine Lying Leg Curl");

    await page.locator("[data-agent-id='template-day-2']").click();
    await addExerciseToCurrentTemplateDay(page, "bench", /^Barbell Bench Press/);
    await page.locator("[data-agent-id='template-day-3']").click();
    await addExerciseToCurrentTemplateDay(page, "row", /^Barbell Bent Over Row/);

    await page.locator("[data-agent-id='template-builder-back']").click();
    await expect(page).toHaveURL(/\/templates\/new\/days-per-week$/);
    await page.locator("[data-agent-id='template-days-per-week-2']").click();
    await page.locator("[data-agent-id='template-days-per-week-next']").click();
    await expect(page.locator("[data-agent-id='template-days-reduction-confirmation']")).toContainText(
      "The following Days will be removed: Day 3 and Day 4.",
    );

    await page.locator("[data-agent-id='modal-back']").click();
    await expect(page.locator("[data-agent-id='template-days-reduction-confirmation']")).toHaveCount(0);
    await expect(page).toHaveURL(/\/templates\/new\/days-per-week$/);

    await page.locator("[data-agent-id='template-days-per-week-next']").click();
    await page.locator("[data-agent-id='modal-confirm']").click();
    await expect(page).toHaveURL(/\/templates\/new\/builder$/);
    await expect(page.locator("[data-agent-id='template-day-3']")).toHaveCount(0);

    await page.locator("[data-agent-id='template-day-1']").click();
    await expect(page.locator("[data-agent-id='template-exercises-loading']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='template-exercise-1']")).toContainText("Leg Press");
    await expect(page.locator("[data-agent-id='template-exercise-2']")).toContainText("Machine Leg Extension");
    await expect(page.locator("[data-agent-id='template-exercise-3']")).toContainText("Machine Seated Leg Curl");
    await expect(page.locator("[data-agent-id='template-exercise-4']")).toContainText("Machine Lying Leg Curl");

    await addExerciseToCurrentTemplateDay(page, "squat", /^Barbell Back Squat/);
    await expect(page.locator("[data-agent-id='template-exercise-5']")).toContainText("Barbell Back Squat");

    await page.locator("[data-agent-id='save-template']").click();
    await expect(page).toHaveURL(/\/start\/select-template$/);
    await startSelectedProgram(page, 4);

    await expect(page.locator("[data-agent-id^='lift-card-']").nth(0)).toContainText("Leg Press");
    await expect(page.locator("[data-agent-id^='lift-card-']").nth(1)).toContainText("Machine Leg Extension");
    await expect(page.locator("[data-agent-id^='lift-card-']").nth(2)).toContainText("Machine Seated Leg Curl");
    await expect(page.locator("[data-agent-id^='lift-card-']").nth(3)).toContainText("Machine Lying Leg Curl");
    await expect(page.locator("[data-agent-id^='lift-card-']").nth(4)).toContainText("Barbell Back Squat");
  });

  test("active workout autosaves set values and advances after Finish workout", async ({ page }, testInfo) => {
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
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("0% done", {
      timeout: 500,
    });
    await firstWeight.fill("200");
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("50% done");
    await expect(firstSetRow.locator("[data-agent-id^='set-logged-']")).toBeVisible();
    const unloggedSetRowStyle = await page
      .locator("[data-agent-id^='set-row-']")
      .nth(1)
      .evaluate((element) => {
        const style = window.getComputedStyle(element);

        return {
          backgroundColor: style.backgroundColor,
          borderTopColor: style.borderTopColor,
        };
      });
    await expect(firstSetRow).toHaveCSS("background-color", unloggedSetRowStyle.backgroundColor);
    await expect(firstSetRow).toHaveCSS("border-top-color", unloggedSetRowStyle.borderTopColor);
    await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toHaveCount(0);
    await expectMobileScreenshot(page, testInfo, "warm-stone-active-workout-logged-mobile.png");

    await firstRep.fill("");
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("50% done", {
      timeout: 100,
    });
    await page.waitForTimeout(setAutosaveSettleMs);
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("0% done");

    await firstRep.fill("12");
    await firstWeight.fill("220");
    await secondRep.fill("10");
    await secondWeight.fill("220");
    await expect(secondWeight).toBeFocused();
    await page.waitForTimeout(setAutosaveSettleMs);

    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("100% done");
    await expect(page.locator("[data-agent-id='finish-workout']")).toBeVisible();
    await expect(page.locator("[data-agent-id='finish-workout']")).toHaveAttribute("aria-disabled", "true");
    await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toBeVisible();
    await expectMobileScreenshot(page, testInfo, "warm-stone-lift-feedback-modal-mobile.png");
    await expect(secondWeight).not.toBeFocused();
    await expect(secondWeight).toBeDisabled();
    await page.keyboard.press("Backspace");
    await expect(secondWeight).toHaveValue("220");
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("100% done");
    await expect(page.locator("[data-agent-id='feedback-save']")).toBeDisabled();
    await page.locator("[data-agent-id='feedback-close']").click();

    await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toHaveCount(0);
    const firstLiftCard = page.locator("[data-agent-id^='lift-card-']").nth(0);
    const firstLiftFeedbackNeeded = firstLiftCard.locator("[data-agent-id^='feedback-needed-lift-']");
    await expect(firstLiftFeedbackNeeded).toBeVisible();
    await expect(firstLiftCard).toContainText("Feedback needed");
    await expect(page.locator("[data-agent-id='feedback-needed']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='finish-workout']")).toBeVisible();
    await expect(page.locator("[data-agent-id='finish-workout']")).toHaveAttribute("aria-disabled", "true");
    await expectMobileScreenshot(page, testInfo, "warm-stone-finish-workout-feedback-blocked-mobile.png");
    await page.locator("[data-agent-id='finish-workout']").click({ force: true });
    const finishPanel = page.locator(".finish-workout-panel");
    await expect(finishPanel.locator("[data-agent-id='finish-feedback-hint']")).toContainText(
      "Complete lift feedback before finishing.",
    );
    await expect(page.locator("[data-agent-id='finish-workout']")).toHaveAttribute(
      "aria-describedby",
      "finish-feedback-hint",
    );

    await firstLiftFeedbackNeeded.click();
    await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toBeVisible();
    await page.locator("[data-agent-id='feedback-pain-option-1']").click();
    await expect(page.locator("[data-agent-id='feedback-save']")).toBeDisabled();
    await page.locator("[data-agent-id='feedback-effort-option-3']").click();
    await expect(page.locator("[data-agent-id='feedback-save']")).toBeEnabled();
    await page.locator("[data-agent-id='feedback-save']").click();
    await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id^='feedback-needed-lift-']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='finish-feedback-hint']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='finish-workout']")).toBeVisible();
    await expect(page.locator("[data-agent-id='finish-workout']")).not.toHaveAttribute("aria-disabled", "true");
    await expectMobileScreenshot(page, testInfo, "warm-stone-active-workout-completed-mobile.png");

    await firstRep.fill("");
    await page.waitForTimeout(setAutosaveSettleMs);
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("50% done");
    await expect(page.locator("[data-agent-id='finish-workout']")).toHaveCount(0);

    await firstRep.fill("12");
    await page.waitForTimeout(setAutosaveSettleMs);
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("100% done");
    await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='finish-workout']")).toBeVisible();

    await page.locator("[data-agent-id='finish-workout']").click({ force: true });

    await expect(page).toHaveURL(/\/programs\/\d+\/workouts\/\d+$/);
    await expect(page.locator("[data-agent-id='workout-day-title']")).toContainText("Day 2");
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("0% done");
    await expect(page.getByRole("heading", { name: "Barbell Back Squat" })).toBeVisible();

    await page.locator("[data-agent-id='workout-day-prev']").click();
    await expect(page.locator("[data-agent-id='workout-day-title']")).toContainText("Day 1");
    await expect(page.locator("[data-agent-id='workout-state']")).toContainText("Read-only");
    await expectMobileScreenshot(page, testInfo, "warm-stone-completed-workout-readonly-mobile.png");
  });

  test("active workout shows a persisted rest timer only after a completed set", async ({ page }) => {
    await createTwoLiftFirstDayTemplate(page, "Rest Timer");
    await startSelectedProgram(page, 4);

    const reps = page.locator("[data-agent-id^='set-reps-']");
    const weights = page.locator("[data-agent-id^='set-weight-']");
    const restPill = page.locator("[data-agent-id='app-top-bar'] [data-agent-id='rest-timer-pill']");
    const workoutFlowRestPill = page.locator(".active-workout-flow [data-agent-id='rest-timer-pill']");

    await expect(restPill).toHaveCount(0);
    await expect(page.locator("[data-agent-id='resume-workout-banner']")).toHaveCount(0);
    await reps.nth(0).fill("12");
    await weights.nth(0).fill("200");
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("25% done");
    await expect(restPill).toBeVisible();
    await expect(workoutFlowRestPill).toHaveCount(0);
    await expect(page.locator("[data-agent-id='rest-timer-status']")).toContainText("Rest");
    await expect(page.locator("[data-agent-id='rest-timer-next']")).toContainText("Next: Set 2");

    await page.locator("[data-agent-id='app-menu-toggle']").click();
    await page.locator("[data-agent-id='menu-current-program']").click();
    await expect(page.locator("[data-agent-id='resume-workout-banner']")).toBeVisible();
    await expect(page.locator("[data-agent-id='resume-workout']")).toContainText("Resume");
    await expect(page.locator("[data-agent-id='resume-workout']")).toContainText("Rest");
    await expect(page.locator("[data-agent-id='resume-workout']")).not.toContainText("Day");
    await expect(page.locator("[data-agent-id='rest-timer-next']")).toContainText("Next: Set 2");
    await page.locator("[data-agent-id='resume-workout']").click();
    await expect(page.locator("[data-agent-id='workout-day-title']")).toContainText("Day 1");
    await expect(restPill).toBeVisible();

    await page.evaluate(() => {
      (window as TestClockWindow).__POWERJACK_TEST_CLOCK__?.advance(121_000);
    });
    await page.waitForTimeout(1100);
    await expect(page.locator("[data-agent-id='rest-timer-status']")).toContainText("Ready");
    await expect(page.locator("[data-agent-id^='set-next-']")).toContainText("Go");
    await expect(page.locator("[aria-current='step']")).toContainText("Set 2");

    await page.locator("[data-agent-id='app-menu-toggle']").click();
    await page.locator("[data-agent-id='menu-current-program']").click();
    await expect(page.locator("[data-agent-id='resume-workout-banner']")).toBeVisible();
    await expect(page.locator("[data-agent-id='resume-workout']")).toContainText("Resume");
    await expect(page.locator("[data-agent-id='resume-workout']")).toContainText("Ready");
    await expect(page.locator("[data-agent-id='resume-workout']")).not.toContainText("Day");
    await expect(page.locator("[data-agent-id='resume-workout']")).toContainText("Set 2");

    await page.reload();
    await expect(page.locator("[data-agent-id='resume-workout-banner']")).toBeVisible();
    await expect(page.locator("[data-agent-id='resume-workout']")).toContainText("Ready");

    await page.locator("[data-agent-id='resume-workout']").click();
    await expect(page.locator("[data-agent-id='workout-day-title']")).toContainText("Day 1");
    await expect(page.locator("[data-agent-id='rest-timer-status']")).toContainText("Ready");

    await page.locator("[data-agent-id='rest-timer-dismiss']").click();
    await expect(restPill).toHaveCount(0);
    await page.locator("[data-agent-id='app-menu-toggle']").click();
    await page.locator("[data-agent-id='menu-current-program']").click();
    await expect(page.locator("[data-agent-id='resume-workout-banner']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='resume-workout']")).toContainText("Resume");
    await page.locator("[data-agent-id='resume-workout']").click();

    await reps.nth(1).fill("10");
    await weights.nth(1).fill("200");
    await page.waitForTimeout(setAutosaveSettleMs);
    await expect(restPill).toBeVisible();
    await expect(page.locator("[data-agent-id='rest-timer-status']")).toContainText("Rest");
    await expect(page.locator("[data-agent-id='rest-timer-next']")).toContainText("Next: Set 1");
  });

  test("active workout set rows keep input positions stable when logging on mobile", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await createTwoLiftFirstDayTemplate(page, "Stable Set Rows");
    await startSelectedProgram(page, 4);

    const reps = page.locator("[data-agent-id^='set-reps-']");
    const weights = page.locator("[data-agent-id^='set-weight-']");
    const benchSetOneReps = reps.nth(0);
    const benchSetOneWeight = weights.nth(0);
    const benchSetTwoReps = reps.nth(1);
    const benchSetTwoWeight = weights.nth(1);

    await expect(page.getByRole("heading", { name: "Barbell Bench Press" })).toBeVisible();
    await expect(reps).toHaveCount(4);
    await benchSetOneReps.fill("12");
    await benchSetOneWeight.fill("200");

    const setOneRepsBefore = await captureElementBox(benchSetOneReps, "set one reps input before logging");
    const setOneWeightBefore = await captureElementBox(benchSetOneWeight, "set one weight input before logging");
    const setTwoRepsBefore = await captureElementBox(benchSetTwoReps, "set two reps input before logging");
    const setTwoWeightBefore = await captureElementBox(benchSetTwoWeight, "set two weight input before logging");

    await page.waitForTimeout(setAutosaveSettleMs);
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("25% done");
    await expect(page.locator("[data-agent-id^='set-logged-']")).toContainText("Logged");

    await expectElementBoxStable(benchSetOneReps, setOneRepsBefore, "set one reps input after logging");
    await expectElementBoxStable(benchSetOneWeight, setOneWeightBefore, "set one weight input after logging");

    await page.evaluate(() => {
      (window as TestClockWindow).__POWERJACK_TEST_CLOCK__?.advance(121_000);
    });
    await page.waitForTimeout(1100);
    await expect(page.locator("[data-agent-id^='set-next-']")).toContainText("Go");
    await expectElementBoxStable(benchSetTwoReps, setTwoRepsBefore, "set two reps input after next badge");
    await expectElementBoxStable(benchSetTwoWeight, setTwoWeightBefore, "set two weight input after next badge");
  });

  test("Finish workout advances to the next workout at the top of the page", async ({ page }) => {
    await createWeightedVolumeTemplate(page);
    await startSelectedProgram(page, 4);

    await completeLiftWithFeedback(page, "Barbell Deadlift");
    await completeLiftWithFeedback(page, "Pull Up");
    await completeLiftWithFeedback(page, "Cable Lat Pulldown");
    await completeLiftWithFeedback(page, "Cable Rear Delt Fly");
    await expect(page.locator("[data-agent-id='finish-workout']")).toBeVisible();

    await scrollActiveWorkoutPageToBottom(page);
    await page.locator("[data-agent-id='finish-workout']").click();

    await expect(page.locator("[data-agent-id='workout-day-title']")).toContainText("Day 2");
    await expect(page.getByRole("heading", { name: "Barbell Back Squat" })).toBeVisible();
    await expectActiveWorkoutPageScrolledToTop(page);
  });

  test("active workout restarts set autosave debounce when reps or weight receive another character", async ({ page }) => {
    await createTwoLiftFirstDayTemplate(page, "Autosave Reset");
    await startSelectedProgram(page, 4);

    const reps = page.locator("[data-agent-id^='set-reps-']");
    const weights = page.locator("[data-agent-id^='set-weight-']");
    const benchSetOneWeight = weights.nth(0);
    const benchSetTwoReps = reps.nth(1);
    const benchSetTwoWeight = weights.nth(1);

    await expect(page.getByRole("heading", { name: "Barbell Bench Press" })).toBeVisible();
    await expect(weights).toHaveCount(4);

    await benchSetOneWeight.click();
    await page.keyboard.type("10", { delay: 40 });
    await page.waitForTimeout(setAutosaveBeforeDelayMs);
    await page.keyboard.type("0", { delay: 40 });
    await expect(benchSetOneWeight).toHaveValue("100");
    await page.waitForTimeout(setAutosaveStaleTimerProbeMs);
    await expect(benchSetTwoWeight).toHaveValue("", { timeout: 100 });

    await page.waitForTimeout(setAutosaveSettleMs);
    await expect(benchSetTwoWeight).toHaveValue("100");

    await benchSetTwoReps.click();
    await page.keyboard.type("1", { delay: 40 });
    await page.waitForTimeout(setAutosaveBeforeDelayMs);
    await page.keyboard.type("0", { delay: 40 });
    await expect(benchSetTwoReps).toHaveValue("10");
    await page.waitForTimeout(setAutosaveStaleTimerProbeMs);
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("0% done", {
      timeout: 100,
    });

    await page.waitForTimeout(setAutosaveSettleMs);
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("25% done");
  });

  test("active workout propagates final debounced weights and persists them", async ({ page }) => {
    await createTwoLiftFirstDayTemplate(page, "Weight Autofill");
    await startSelectedProgram(page, 4);

    const weights = page.locator("[data-agent-id^='set-weight-']");
    const benchSetOne = weights.nth(0);
    const benchSetTwo = weights.nth(1);
    const deadliftSetOne = weights.nth(2);
    const deadliftSetTwo = weights.nth(3);

    await expect(page.getByRole("heading", { name: "Barbell Bench Press" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Barbell Deadlift" })).toBeVisible();
    await expect(weights).toHaveCount(4);

    await benchSetOne.click();
    await page.keyboard.type("10", { delay: 40 });
    await page.waitForTimeout(setAutosaveBeforeDelayMs);
    await page.keyboard.type("0", { delay: 40 });
    await expect(benchSetOne).toHaveValue("100");
    await expect(benchSetTwo).toHaveValue("", { timeout: 100 });
    await expect(deadliftSetOne).toHaveValue("");
    await expect(deadliftSetTwo).toHaveValue("");

    await page.waitForTimeout(setAutosaveSettleMs);
    await expect(benchSetTwo).toHaveValue("100");
    await expect(deadliftSetOne).toHaveValue("");
    await expect(deadliftSetTwo).toHaveValue("");

    await benchSetTwo.fill("200");
    await page.waitForTimeout(setAutosaveSettleMs);
    await expect(benchSetOne).toHaveValue("100");
    await expect(benchSetTwo).toHaveValue("200");
    await expect(deadliftSetOne).toHaveValue("");
    await expect(deadliftSetTwo).toHaveValue("");

    await benchSetOne.fill("185");
    await expect(benchSetOne).toHaveValue("185");
    await expect(benchSetTwo).toHaveValue("200", { timeout: 100 });

    await page.waitForTimeout(setAutosaveSettleMs);
    await expect(benchSetTwo).toHaveValue("185");
    await expect(deadliftSetOne).toHaveValue("");
    await expect(deadliftSetTwo).toHaveValue("");

    await page.reload();
    await expect(page.getByRole("heading", { name: "Barbell Bench Press" })).toBeVisible();
    await expect(weights).toHaveCount(4);
    await expect(benchSetOne).toHaveValue("185");
    await expect(benchSetTwo).toHaveValue("185");
    await expect(deadliftSetOne).toHaveValue("");
    await expect(deadliftSetTwo).toHaveValue("");
  });

  test("active workout propagates final debounced weights on mobile", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await createTwoLiftFirstDayTemplate(page, "Mobile Weight Autofill");
    await startSelectedProgram(page, 4);

    const weights = page.locator("[data-agent-id^='set-weight-']");
    const benchSetOne = weights.nth(0);
    const benchSetTwo = weights.nth(1);
    const deadliftSetOne = weights.nth(2);

    await expect(weights).toHaveCount(4);
    await benchSetOne.click();
    await page.keyboard.type("135", { delay: 40 });
    await expect(benchSetOne).toHaveValue("135");
    await expect(benchSetTwo).toHaveValue("", { timeout: 100 });
    await page.waitForTimeout(setAutosaveSettleMs);
    await expect(benchSetTwo).toHaveValue("135");
    await expect(deadliftSetOne).toHaveValue("");
  });

  test("feedback scales stay in one row on mobile", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await createTwoDayTemplate(page, "Mobile Feedback Scale");
    await startSelectedProgram(page, 4);

    await page.locator("[data-agent-id^='set-reps-']").nth(0).fill("10");
    await page.locator("[data-agent-id^='set-weight-']").nth(0).fill("100");
    await page.locator("[data-agent-id^='set-reps-']").nth(1).fill("8");
    await page.locator("[data-agent-id^='set-weight-']").nth(1).fill("100");
    await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toBeVisible();
    await expect(page.locator("[data-agent-id='feedback-pain-option-1']")).toContainText("None");
    await expect(page.locator("[data-agent-id='feedback-pain-option-2']")).toContainText("Some");
    await expect(page.locator("[data-agent-id='feedback-pain-option-3']")).toContainText("Pinch");
    await expect(page.locator("[data-agent-id='feedback-pain-option-4']")).toContainText("High");
    await expect(page.locator("[data-agent-id='feedback-effort-option-2']")).toContainText("Tough");
    await expect(page.locator("[data-agent-id='feedback-effort-option-3']")).toContainText("Challenge");

    await expectFeedbackOptionsOnSingleRow(page, "feedback-pain-option");
    await expectFeedbackOptionsOnSingleRow(page, "feedback-effort-option");
    expect(await pageHasHorizontalOverflow(page)).toBe(false);
  });

  test("manual lift menu adds and removes sets on mobile", async ({ page }, testInfo) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await createTwoDayTemplate(page, "Manual Set Control");
    await startSelectedProgram(page, 4);

    const menuToggle = page.locator("[data-agent-id^='lift-menu-toggle-']").first();

    await menuToggle.click();
    await expect(menuToggle).toHaveAttribute("aria-expanded", "true");
    await expect(page.locator("[data-agent-id^='lift-actions-menu-']")).toBeVisible();
    await testInfo.attach("manual-lift-menu-mobile", {
      body: await page.screenshot({ fullPage: true }),
      contentType: "image/png",
    });

    await page.keyboard.press("Escape");
    await expect(page.locator("[data-agent-id^='lift-actions-menu-']")).toHaveCount(0);

    await menuToggle.click();
    await page.locator("[data-agent-id^='lift-add-set-']").click();
    await expect(page.locator("[data-agent-id^='set-reps-']")).toHaveCount(3);
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("0% done");

    await page.locator("[data-agent-id^='set-reps-']").nth(2).fill("7");
    await page.locator("[data-agent-id^='set-weight-']").nth(2).fill("100");
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("33% done");

    await menuToggle.click();
    await page.locator("[data-agent-id^='lift-remove-last-set-']").click();
    await expect(page.locator("[data-agent-id='remove-last-set-confirmation']")).toContainText("Remove last set");
    await page.locator("[data-agent-id='modal-delete']").click();

    await expect(page.locator("[data-agent-id='remove-last-set-confirmation']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id^='set-reps-']")).toHaveCount(2);
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("0% done");
  });

  test("last lift menu stays fully visible above reserved finish space on mobile", async ({ page }, testInfo) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await createWeightedVolumeTemplate(page);
    await startSelectedProgram(page, 4);

    await expect(page.locator("[data-agent-id='finish-workout']")).toHaveCount(0);

    await scrollActiveWorkoutPageToBottom(page);

    const lastMenuToggle = page.locator("[data-agent-id^='lift-menu-toggle-']").last();
    await expect(lastMenuToggle).toBeVisible();
    await lastMenuToggle.click();

    const actionsMenu = page.locator("[data-agent-id^='lift-actions-menu-']");
    await expect(actionsMenu).toBeVisible();
    await expect(actionsMenu.locator("[data-agent-id^='lift-remove-last-set-']")).toBeVisible();
    await expectElementWithinActiveWorkoutViewport(page, actionsMenu, "last lift actions menu");

    await testInfo.attach("last-lift-menu-reserved-finish-space-mobile", {
      body: await page.screenshot({ fullPage: true }),
      contentType: "image/png",
    });
  });

  test("changing a lift exercise resets the lift and carries into future weeks", async ({ page }, testInfo) => {
    await createTwoDayTemplate(page, "Exercise Swap");
    await startSelectedProgram(page, 4);

    await page.locator("[data-agent-id^='set-reps-']").nth(0).fill("12");
    await page.locator("[data-agent-id^='set-weight-']").nth(0).fill("100");
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("50% done");

    await page.locator("[data-agent-id^='lift-menu-toggle-']").first().click();
    await page.locator("[data-agent-id^='lift-change-exercise-']").click();
    await expect(page.locator("[data-agent-id='exercise-search-overlay']")).toBeVisible();
    await expect(page.locator("[data-agent-id='change-exercise-search-input']")).toBeFocused();
    await page.locator("[data-agent-id='change-exercise-search-input']").fill("pull-up");
    await expectExerciseSearchResultsInsideViewport(page);
    await expectMobileScreenshot(page, testInfo, "warm-stone-exercise-change-modal-mobile.png");
    await page.getByRole("button", { name: /^Pull Up/ }).click();
    await expect(page.locator("[data-agent-id='exercise-search-overlay']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='change-exercise-confirmation']")).toContainText(
      "Change exercise",
    );
    await page.locator("[data-agent-id='modal-confirm']").click();

    await expect(page.locator("[data-agent-id='exercise-search-overlay']")).toHaveCount(0);
    await expect(page.getByRole("heading", { name: "Pull Up" })).toBeVisible();
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("0% done");
    await expect(page.locator("[data-agent-id^='set-reps-']").nth(0)).toHaveValue("");
    await expect(page.locator("[data-agent-id^='set-weight-']").nth(0)).toBeDisabled();

    await page.locator("[data-agent-id^='set-reps-']").nth(0).fill("8");
    await page.locator("[data-agent-id^='set-reps-']").nth(1).fill("7");
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("100% done");
    await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toBeVisible();
    await page.locator("[data-agent-id='feedback-pain-option-1']").click();
    await page.locator("[data-agent-id='feedback-effort-option-3']").click();
    await page.locator("[data-agent-id='feedback-save']").click();
    await expect(page.locator("[data-agent-id='finish-workout']")).toBeVisible();
    await page.locator("[data-agent-id='finish-workout']").click();

    await expect(page.locator("[data-agent-id='workout-day-title']")).toContainText("Day 2");
    await completeActiveLiftWithFeedback(page, { pain: 1, effort: 3, reps: ["8", "8"], weight: "150" });
    await page.locator("[data-agent-id='finish-workout']").click();

    await expect(page.locator("[data-agent-id='workout-week-label']")).toContainText("Week 2/4");
    await expect(page.locator("[data-agent-id='workout-day-title']")).toContainText("Day 1");
    await expect(page.getByRole("heading", { name: "Pull Up" })).toBeVisible();
  });

  test("multiple completed lifts keep their own feedback-needed warnings", async ({ page }) => {
    await openTemplateFocus(page, "Two Lift Feedback");
    await selectFocusAndOpenDays(page);
    await page.locator("[data-agent-id='template-days-per-week-2']").click();
    await page.locator("[data-agent-id='template-days-per-week-next']").click();
    await page.locator("[data-agent-id='add-exercise']").click();
    await page.locator("[data-agent-id='exercise-search-input']").fill("bench");
    await page.getByRole("button", { name: /Barbell Bench Press/ }).click();
    await page.locator("[data-agent-id='add-exercise']").click();
    await page.locator("[data-agent-id='exercise-search-input']").fill("deadlift");
    await page.getByRole("button", { name: /Barbell Deadlift/ }).click();
    await page.locator("[data-agent-id='template-day-2']").click();
    await page.locator("[data-agent-id='add-exercise']").click();
    await page.locator("[data-agent-id='exercise-search-input']").fill("squat");
    await page.getByRole("button", { name: /Barbell Back Squat/ }).click();
    await page.locator("[data-agent-id='save-template']").click();
    await page.locator("[data-agent-id='select-template-next']").click();
    await page.locator("[data-agent-id='program-length-4']").click();
    await page.locator("[data-agent-id='program-length-next']").click();

    const reps = page.locator("[data-agent-id^='set-reps-']");
    const weights = page.locator("[data-agent-id^='set-weight-']");
    const liftCards = page.locator("[data-agent-id^='lift-card-']");
    const firstLiftCard = liftCards.nth(0);
    const secondLiftCard = liftCards.nth(1);

    await expect(firstLiftCard).toContainText("Barbell Bench Press");
    await expect(secondLiftCard).toContainText("Barbell Deadlift");

    await reps.nth(0).fill("10");
    await weights.nth(0).fill("100");
    await reps.nth(1).fill("8");
    await weights.nth(1).fill("100");
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("50% done");
    await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toBeVisible();
    await page.locator("[data-agent-id='feedback-close']").click();

    await reps.nth(2).fill("5");
    await weights.nth(2).fill("225");
    await reps.nth(3).fill("5");
    await weights.nth(3).fill("225");
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("100% done");
    await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toBeVisible();
    await page.locator("[data-agent-id='feedback-close']").click();

    const firstFeedbackNeeded = firstLiftCard.locator("[data-agent-id^='feedback-needed-lift-']");
    const secondFeedbackNeeded = secondLiftCard.locator("[data-agent-id^='feedback-needed-lift-']");

    await expect(page.locator("[data-agent-id^='feedback-needed-lift-']")).toHaveCount(2);
    await expect(firstFeedbackNeeded).toBeVisible();
    await expect(secondFeedbackNeeded).toBeVisible();
    await expect(page.locator("[data-agent-id='feedback-needed']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='finish-workout']")).toHaveAttribute("aria-disabled", "true");

    await page.locator("[data-agent-id='finish-workout']").click({ force: true });
    await expect(page.locator(".finish-workout-panel [data-agent-id='finish-feedback-hint']")).toContainText(
      "Complete lift feedback before finishing.",
    );

    await firstFeedbackNeeded.click();
    await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toContainText("Barbell Bench Press");
    await page.locator("[data-agent-id='feedback-pain-option-1']").click();
    await page.locator("[data-agent-id='feedback-effort-option-3']").click();
    await page.locator("[data-agent-id='feedback-save']").click();

    await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toHaveCount(0);
    await expect(firstLiftCard.locator("[data-agent-id^='feedback-needed-lift-']")).toHaveCount(0);
    await expect(secondFeedbackNeeded).toBeVisible();
    await expect(page.locator("[data-agent-id='finish-workout']")).toHaveAttribute("aria-disabled", "true");
    await expect(page.locator("[data-agent-id='finish-feedback-hint']")).toBeVisible();

    await secondFeedbackNeeded.click();
    await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toContainText(
      "Barbell Deadlift",
    );
    await page.locator("[data-agent-id='feedback-pain-option-1']").click();
    await page.locator("[data-agent-id='feedback-effort-option-3']").click();
    await page.locator("[data-agent-id='feedback-save']").click();

    await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id^='feedback-needed-lift-']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='finish-feedback-hint']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='finish-workout']")).not.toHaveAttribute("aria-disabled", "true");
  });

  test("high-pain manual check-in can skip and carries forward", async ({ page }, testInfo) => {
    await openWeekTwoBenchManualCheckIn(page, { templateName: "Bench Check", pain: 4 });

    await expect(page.locator("[data-agent-id='manual-checkin-modal']")).toContainText(
      "Last week Barbell Bench Press caused a pain of 4/5",
    );
    await expectMobileScreenshot(page, testInfo, "warm-stone-manual-checkin-modal-mobile.png");
    await expect(page.locator("[data-agent-id^='set-reps-']").nth(0)).toBeDisabled();
    await page.locator("[data-agent-id='manual-checkin-skip-yes']").click();

    await expect(page.locator("[data-agent-id='manual-checkin-modal']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("0% done");
    await expect(page.locator("[data-agent-id^='set-skipped-']")).toHaveCount(2);
    await expect(page.locator("[data-agent-id='finish-workout']")).toBeVisible();

    await page.locator("[data-agent-id='finish-workout']").click();
    await expect(page.locator("[data-agent-id='workout-day-title']")).toContainText("Day 2");
    await completeActiveLiftWithFeedback(page, { pain: 1, effort: 3, reps: ["8", "8"], weight: "150" });
    await page.locator("[data-agent-id='finish-workout']").click();
    await expect(page.locator("[data-agent-id='workout-week-label']")).toContainText("Week 3/4");
    await expect(page.locator("[data-agent-id='workout-day-title']")).toContainText("Day 1");
    await expect(page.locator("[data-agent-id='manual-checkin-modal']")).toBeVisible();
    await expect(page.locator("[data-agent-id='manual-checkin-modal']")).toContainText(
      "Last week Barbell Bench Press caused a pain of 4/5",
    );
  });

  test("skipped sets stay in non-planned workout progress totals", async ({ page }) => {
    await createTwoLiftFirstDayTemplate(page, "Skipped Progress");
    await startSelectedProgram(page, 4);

    await completeLiftWithFeedback(page, "Barbell Bench Press", { pain: 4, weight: "100" });
    await completeLiftWithFeedback(page, "Barbell Deadlift", { weight: "100" });
    await page.locator("[data-agent-id='finish-workout']").click();
    await expect(page.locator("[data-agent-id='workout-day-title']")).toContainText("Day 2");
    await completeActiveLiftWithFeedback(page, { pain: 1, effort: 3, reps: ["8", "8"], weight: "150" });
    await page.locator("[data-agent-id='finish-workout']").click();

    await expect(page.locator("[data-agent-id='workout-week-label']")).toContainText("Week 2/4");
    await expect(page.locator("[data-agent-id='workout-day-title']")).toContainText("Day 1");
    await expect(page.locator("[data-agent-id='manual-checkin-modal']")).toBeVisible();
    await page.locator("[data-agent-id='manual-checkin-skip-yes']").click();

    await expect(page.locator("[data-agent-id='manual-checkin-modal']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("0% done");
    await expect(page.locator("[data-agent-id^='set-skipped-']")).toHaveCount(2);

    await completeLiftWithFeedback(page, "Barbell Deadlift", { reps: "8", weight: "100" });
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("50% done");
    await expect(page.locator("[data-agent-id='finish-workout']")).toBeVisible();
  });

  test("high-pain manual check-in can reset on mobile", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await openWeekTwoBenchManualCheckIn(page, { templateName: "Mobile Bench Check", pain: 5 });

    await page.locator("[data-agent-id='manual-checkin-skip-no']").click();
    await expect(page.locator("[data-agent-id='manual-checkin-modal']")).toContainText(
      "Would you like to reset progress for Barbell Bench Press?",
    );
    await page.locator("[data-agent-id='manual-checkin-reset-yes']").click();

    await expect(page.locator("[data-agent-id='manual-checkin-modal']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("0% done");
    await expect(page.locator("[data-agent-id^='set-reps-']")).toHaveCount(2);
    await expect(page.locator("[data-agent-id^='set-weight-']")).toHaveCount(2);
    await expect(page.locator("[data-agent-id^='set-reps-']").nth(0)).toBeEnabled();
    await expect(page.locator("[data-agent-id^='set-reps-']").nth(0)).toHaveValue("");
    await expect(page.locator("[data-agent-id^='set-weight-']").nth(0)).toHaveValue("");
  });

  test("high-pain manual check-in can continue without reset", async ({ page }) => {
    await openWeekTwoBenchManualCheckIn(page, { templateName: "Continue Bench Check", pain: 4 });

    await page.locator("[data-agent-id='manual-checkin-skip-no']").click();
    await page.locator("[data-agent-id='manual-checkin-reset-no']").click();

    await expect(page.locator("[data-agent-id='manual-checkin-modal']")).toHaveCount(0);
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("0% done");
    await expect(page.locator("[data-agent-id^='set-reps-']").nth(0)).toBeEnabled();
    await expect(page.locator("[data-agent-id^='set-reps-']").nth(0)).toHaveAttribute("placeholder", "10");
    await expect(page.locator("[data-agent-id^='set-weight-']").nth(0)).toHaveValue("100");
    await page.locator("[data-agent-id^='set-weight-']").nth(0).fill("95");
    await expect(page.locator("[data-agent-id^='set-weight-']").nth(0)).toHaveValue("95");
  });

  test("time-based workout rows show seconds and normalize partial blocks on mobile", async ({
    page,
  }, testInfo) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await openTemplateFocus(page, "Timed Planks");
    await page.locator(".muscle-focus-grid").getByRole("button", { name: "Core" }).click();
    await page.locator("[data-agent-id='template-muscle-focus-next']").click();
    await page.locator("[data-agent-id='template-days-per-week-2']").click();
    await page.locator("[data-agent-id='template-days-per-week-next']").click();
    await addExerciseToCurrentTemplateDay(page, "plank", /^Plank/);
    await addExerciseToCurrentTemplateDay(page, "weighted plank", /^Weighted Plank/);
    await page.locator("[data-agent-id='template-day-2']").click();
    await addExerciseToCurrentTemplateDay(page, "bench", /Barbell Bench Press/);
    await page.locator("[data-agent-id='save-template']").click();
    await startSelectedProgram(page, 4);

    const liftCards = page.locator("[data-agent-id^='lift-card-']");
    const plankCard = liftCards.filter({
      has: page.getByRole("heading", { exact: true, name: "Plank" }),
    });
    const weightedPlankCard = liftCards.filter({
      has: page.getByRole("heading", { exact: true, name: "Weighted Plank" }),
    });
    const plankSecondsInputs = plankCard.locator("[data-agent-id^='set-reps-']");
    const plankWeightInputs = plankCard.locator("[data-agent-id^='set-weight-']");
    const weightedSecondsInputs = weightedPlankCard.locator("[data-agent-id^='set-reps-']");
    const weightedWeightInputs = weightedPlankCard.locator("[data-agent-id^='set-weight-']");

    await expect(page.getByRole("heading", { exact: true, name: "Plank" })).toBeVisible();
    await expect(page.getByRole("heading", { exact: true, name: "Weighted Plank" })).toBeVisible();
    await expect(plankCard.getByText("Seconds")).toHaveCount(2);
    await expect(weightedPlankCard.getByText("Seconds")).toHaveCount(2);
    await expect(plankWeightInputs.first()).toBeDisabled();
    await expect(plankWeightInputs.first()).toHaveValue("BW");
    await expect(weightedWeightInputs.first()).toBeEnabled();

    await plankSecondsInputs.nth(0).fill("97");
    await page.waitForTimeout(setAutosaveSettleMs);
    await expect(plankSecondsInputs.nth(0)).toHaveValue("90");
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("25% done");

    await plankSecondsInputs.nth(1).fill("14");
    await page.waitForTimeout(setAutosaveSettleMs);
    await expect(plankSecondsInputs.nth(1)).toHaveValue("");
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("25% done");

    await weightedSecondsInputs.nth(0).fill("97");
    await weightedWeightInputs.nth(0).fill("25");
    await page.waitForTimeout(setAutosaveSettleMs);
    await expect(weightedSecondsInputs.nth(0)).toHaveValue("90");
    await expect(weightedWeightInputs.nth(0)).toHaveValue("25");
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("50% done");
    await expectMobileScreenshot(page, testInfo, "warm-stone-time-based-workout-mobile.png");

    await page.locator("[data-agent-id='workout-day-next']").click();
    await expect(page.getByRole("heading", { name: "Barbell Bench Press" })).toBeVisible();
    await expect(page.locator("[data-agent-id^='lift-card-']").filter({ hasText: "Barbell Bench Press" })).toContainText(
      "Reps",
    );
  });

  test("reps-only workout disables weight input and logs reps only", async ({ page }) => {
    await openTemplateFocus(page, "Bodyweight Check");
    await selectFocusAndOpenDays(page);
    await page.locator("[data-agent-id='template-days-per-week-2']").click();
    await page.locator("[data-agent-id='template-days-per-week-next']").click();
    await page.locator("[data-agent-id='add-exercise']").click();
    await page.locator("[data-agent-id='exercise-search-input']").fill("pull-up");
    await page.getByRole("button", { name: /^Pull Up/ }).click();
    await page.locator("[data-agent-id='template-day-2']").click();
    await page.locator("[data-agent-id='add-exercise']").click();
    await page.locator("[data-agent-id='exercise-search-input']").fill("squat");
    await page.getByRole("button", { name: /Barbell Back Squat/ }).click();
    await page.locator("[data-agent-id='save-template']").click();
    await page.locator("[data-agent-id='select-template-next']").click();
    await page.locator("[data-agent-id='program-length-4']").click();
    await page.locator("[data-agent-id='program-length-next']").click();

    await expect(page).toHaveURL(/\/programs\/\d+\/workouts\/\d+$/);
    await expect(page.getByRole("heading", { name: "Pull Up" })).toBeVisible();

    const firstRep = page.locator("[data-agent-id^='set-reps-']").nth(0);
    const firstWeight = page.locator("[data-agent-id^='set-weight-']").nth(0);
    const secondRep = page.locator("[data-agent-id^='set-reps-']").nth(1);
    const secondWeight = page.locator("[data-agent-id^='set-weight-']").nth(1);

    await expect(firstWeight).toBeDisabled();
    await expect(firstWeight).toHaveValue("BW");
    await expect(secondWeight).toBeDisabled();
    await expect(secondWeight).toHaveValue("BW");

    await firstRep.fill("8");
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("50% done");
    await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toHaveCount(0);

    await secondRep.fill("7");
    await expect(page.locator("[data-agent-id='workout-progress-percent']")).toContainText("100% done");
    await expect(page.locator("[data-agent-id='lift-feedback-modal']")).toBeVisible();
  });
});
