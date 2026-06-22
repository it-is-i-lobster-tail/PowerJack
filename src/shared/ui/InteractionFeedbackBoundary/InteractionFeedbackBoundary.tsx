import type { FocusEvent, MouseEvent, ReactNode } from "react";
import { useEffect, useRef } from "react";

const feedbackAttribute = "data-interaction-feedback";
const feedbackDurationMs = 210;

const clickFeedbackSelector = [
  "button",
  "select",
  "input[type='checkbox']",
  "input[type='radio']",
  "[role='button']",
  "[role='checkbox']",
  "[role='menuitem']",
  "[role='menuitemcheckbox']",
  "[role='menuitemradio']",
  "[role='option']",
  "[role='radio']",
  "[role='switch']",
  "[role='tab']",
].join(",");

const textInputTypes = new Set([
  "",
  "date",
  "datetime-local",
  "email",
  "month",
  "number",
  "password",
  "search",
  "tel",
  "text",
  "time",
  "url",
  "week",
]);

interface InteractionFeedbackBoundaryProps {
  children: ReactNode;
}

export function InteractionFeedbackBoundary({ children }: InteractionFeedbackBoundaryProps) {
  const activeTimers = useRef(new Map<HTMLElement, ReturnType<typeof window.setTimeout>>());

  useEffect(() => {
    const timers = activeTimers.current;

    return () => {
      for (const timer of timers.values()) {
        window.clearTimeout(timer);
      }

      timers.clear();
    };
  }, []);

  function triggerFeedback(element: HTMLElement): void {
    const activeTimer = activeTimers.current.get(element);

    if (activeTimer) {
      window.clearTimeout(activeTimer);
    }

    element.removeAttribute(feedbackAttribute);
    void element.offsetWidth;
    element.setAttribute(feedbackAttribute, "active");

    const timer = window.setTimeout(() => {
      element.removeAttribute(feedbackAttribute);
      activeTimers.current.delete(element);
    }, feedbackDurationMs);

    activeTimers.current.set(element, timer);
  }

  function handleClickCapture(event: MouseEvent<HTMLDivElement>): void {
    const element = findClickFeedbackElement(event.target, event.currentTarget);

    if (element) {
      triggerFeedback(element);
    }
  }

  function handleFocusCapture(event: FocusEvent<HTMLDivElement>): void {
    const element = event.target;

    if (isEditableTextControl(element)) {
      triggerFeedback(element);
    }
  }

  return (
    <div onClickCapture={handleClickCapture} onFocusCapture={handleFocusCapture}>
      {children}
    </div>
  );
}

function findClickFeedbackElement(target: EventTarget | null, boundary: HTMLElement): HTMLElement | null {
  if (!(target instanceof Element)) {
    return null;
  }

  const element = target.closest(clickFeedbackSelector);

  if (!(element instanceof HTMLElement) || !boundary.contains(element) || isNativeDisabled(element)) {
    return null;
  }

  return element;
}

function isEditableTextControl(element: EventTarget): element is HTMLInputElement | HTMLTextAreaElement {
  if (element instanceof HTMLTextAreaElement) {
    return !element.disabled && !element.readOnly;
  }

  if (!(element instanceof HTMLInputElement)) {
    return false;
  }

  return !element.disabled && !element.readOnly && textInputTypes.has(element.type);
}

function isNativeDisabled(element: HTMLElement): boolean {
  return (
    (element instanceof HTMLButtonElement ||
      element instanceof HTMLInputElement ||
      element instanceof HTMLSelectElement ||
      element instanceof HTMLTextAreaElement) &&
    element.disabled
  );
}
