import type { ButtonHTMLAttributes, ReactNode } from "react";
import { Button } from "../Button";
import "./FlowActionBar.css";

type FlowActionVariant = "primary" | "secondary" | "outline" | "danger";

interface FlowAction {
  agentId: string;
  label: ReactNode;
  ariaLabel?: string;
  disabled?: boolean;
  leadingIcon?: ReactNode;
  onClick: ButtonHTMLAttributes<HTMLButtonElement>["onClick"];
  trailingIcon?: ReactNode;
  variant?: FlowActionVariant;
}

interface FlowActionBarProps {
  className?: string;
  leftAction: FlowAction;
  rightAction: FlowAction;
}

export function FlowActionBar({ className = "", leftAction, rightAction }: FlowActionBarProps) {
  const classes = ["flow-action-bar", className].filter(Boolean).join(" ");

  return (
    <div className={classes}>
      <Button
        aria-label={leftAction.ariaLabel}
        className="flow-action-bar__button"
        data-agent-id={leftAction.agentId}
        disabled={leftAction.disabled}
        leadingIcon={leftAction.leadingIcon}
        onClick={leftAction.onClick}
        variant={leftAction.variant ?? "secondary"}
      >
        {leftAction.label}
      </Button>
      <Button
        aria-label={rightAction.ariaLabel}
        className="flow-action-bar__button"
        data-agent-id={rightAction.agentId}
        disabled={rightAction.disabled}
        leadingIcon={rightAction.leadingIcon}
        onClick={rightAction.onClick}
        trailingIcon={rightAction.trailingIcon}
        variant={rightAction.variant ?? "outline"}
      >
        {rightAction.label}
      </Button>
    </div>
  );
}
