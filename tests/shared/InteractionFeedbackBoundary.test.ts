import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { createElement } from "react";
import type { ReactNode } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { InteractionFeedbackBoundary } from "../../src/shared/ui/InteractionFeedbackBoundary";

const feedbackAttribute = "data-interaction-feedback";
const feedbackDurationMs = 210;

function renderBoundary(...children: ReactNode[]) {
  return render(createElement(InteractionFeedbackBoundary, null, ...children));
}

describe("InteractionFeedbackBoundary", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    cleanup();
    vi.clearAllTimers();
    vi.useRealTimers();
  });

  it("adds and removes feedback when an enabled button is clicked", () => {
    renderBoundary(createElement("button", { type: "button" }, "Lift"));

    const button = screen.getByRole("button", { name: "Lift" });

    fireEvent.click(button);

    expect(button).toHaveAttribute(feedbackAttribute, "active");

    vi.advanceTimersByTime(feedbackDurationMs);

    expect(button).not.toHaveAttribute(feedbackAttribute);
  });

  it("adds and removes feedback when a text input receives focus", () => {
    renderBoundary(createElement("input", { "aria-label": "Template name" }));

    const input = screen.getByRole("textbox", { name: "Template name" });

    fireEvent.focus(input);

    expect(input).toHaveAttribute(feedbackAttribute, "active");

    vi.advanceTimersByTime(feedbackDurationMs);

    expect(input).not.toHaveAttribute(feedbackAttribute);
  });

  it("flashes selected radio-style options", () => {
    renderBoundary(
      createElement(
        "div",
        { "aria-checked": "true", role: "radio", tabIndex: 0 },
        createElement("span", null, "Four weeks"),
      ),
    );

    const option = screen.getByRole("radio", { name: "Four weeks" });

    fireEvent.click(screen.getByText("Four weeks"));

    expect(option).toHaveAttribute(feedbackAttribute, "active");
  });

  it("does not flash native disabled controls", () => {
    renderBoundary(createElement("button", { disabled: true, type: "button" }, "Locked"));

    const button = screen.getByRole("button", { name: "Locked" });

    fireEvent.click(button);

    expect(button).not.toHaveAttribute(feedbackAttribute);
  });

  it("restarts the feedback timer on repeated clicks", () => {
    renderBoundary(createElement("button", { type: "button" }, "Again"));

    const button = screen.getByRole("button", { name: "Again" });

    fireEvent.click(button);
    vi.advanceTimersByTime(150);
    fireEvent.click(button);
    vi.advanceTimersByTime(100);

    expect(button).toHaveAttribute(feedbackAttribute, "active");

    vi.advanceTimersByTime(110);

    expect(button).not.toHaveAttribute(feedbackAttribute);
  });
});
