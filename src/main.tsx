import { bootstrap } from "./app/bootstrap";
import "./shared/styles/index.css";

bootstrap().catch((error: unknown) => {
  console.error("PowerJack failed to start", error);
});
