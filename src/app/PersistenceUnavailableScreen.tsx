import "./PersistenceUnavailableScreen.css";

export function PersistenceUnavailableScreen() {
  return (
    <main className="persistence-unavailable" data-agent-id="persistence-unavailable">
      <section className="persistence-unavailable__panel" aria-labelledby="persistence-unavailable-title">
        <p className="persistence-unavailable__eyebrow">Local storage</p>
        <h1 id="persistence-unavailable-title">Storage unavailable</h1>
        <p>
          PowerJack could not open its local database. Restart the app and try again before
          saving workouts or templates.
        </p>
        <button
          className="persistence-unavailable__retry"
          data-agent-id="persistence-unavailable-retry"
          onClick={() => window.location.reload()}
          type="button"
        >
          Retry
        </button>
      </section>
    </main>
  );
}
