import { createContext } from "react";
import type { AppServices } from "./AppServices";

export const ServicesContext = createContext<AppServices | null>(null);
