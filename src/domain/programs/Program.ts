import type { EntityId } from "../ids";
import type { PowerJackStatus } from "../status";

export interface Program {
  id: EntityId;
  name: string;
  programLengthWeeks: number;
  status: PowerJackStatus;
  locked: boolean;
  templateId: EntityId;
  createdAt: string;
  updatedAt: string;
}
