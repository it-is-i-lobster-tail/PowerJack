export const agentRestTimerResetEventName = "powerjack:agent-reset";

export function dispatchRestTimerAgentReset(): void {
  window.dispatchEvent(new Event(agentRestTimerResetEventName));
}
