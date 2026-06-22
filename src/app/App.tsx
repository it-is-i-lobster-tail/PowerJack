import { RouterProvider, type RouterProviderProps } from "react-router-dom";
import { InteractionFeedbackBoundary } from "../shared/ui/InteractionFeedbackBoundary";

interface AppProps {
  router: RouterProviderProps["router"];
}

export function App({ router }: AppProps) {
  return (
    <InteractionFeedbackBoundary>
      <RouterProvider router={router} />
    </InteractionFeedbackBoundary>
  );
}
