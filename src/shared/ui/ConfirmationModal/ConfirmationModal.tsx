import type { ReactNode } from "react";
import { Button } from "../Button";
import "./ConfirmationModal.css";

interface ConfirmationModalProps {
  agentId: string;
  title: string;
  body?: ReactNode;
  cancelLabel?: string;
  confirmLabel?: string;
  confirmAgentId?: "modal-confirm" | "modal-delete";
  destructive?: boolean;
  onCancel: () => void;
  onConfirm?: () => void;
}

export function ConfirmationModal({
  agentId,
  title,
  body,
  cancelLabel = "Back",
  confirmLabel,
  confirmAgentId = "modal-confirm",
  destructive = false,
  onCancel,
  onConfirm,
}: ConfirmationModalProps) {
  const bodyId = body ? `${agentId}-body` : undefined;

  return (
    <div className="modal-overlay" role="presentation">
      <section
        aria-describedby={bodyId}
        aria-labelledby={`${agentId}-title`}
        aria-modal="true"
        className="confirmation-modal"
        data-agent-id={agentId}
        role="alertdialog"
      >
        <h2 id={`${agentId}-title`}>{title}</h2>
        {body ? (
          <div className="confirmation-modal__body" id={bodyId}>
            {body}
          </div>
        ) : null}
        <div className="confirmation-modal__actions">
          <Button data-agent-id="modal-back" onClick={onCancel} variant="secondary">
            {cancelLabel}
          </Button>
          {confirmLabel && onConfirm ? (
            <Button
              data-agent-id={confirmAgentId}
              onClick={onConfirm}
              variant={destructive ? "danger" : "primary"}
            >
              {confirmLabel}
            </Button>
          ) : null}
        </div>
      </section>
    </div>
  );
}
