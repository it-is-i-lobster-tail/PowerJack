# ADR 0002: GitHub-Only Container Publishing

## Decision

PowerJack publishes its production container image only from GitHub Actions after a commit reaches `main`. The image serves the Vite static bundle with `cgr.dev/chainguard/nginx:latest` on port `8080`. The build stage uses `cgr.dev/chainguard/node:latest-dev` so the runtime image does not carry Node build tooling.

The workflow publishes to Docker Hub using repository variables for the target image and the existing `DOCKER_HUB_PERSON_ACCESS_TOKEN` secret for authentication:

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_NAMESPACE`
- `DOCKERHUB_IMAGE`

## Consequences

- Local development remains unchanged: use `npm run dev`, `npm run check`, and `npm run build`.
- Pull request validation does not log in to Docker Hub or push images.
- Docker Hub publishing fails fast if the required variables or secret are missing.
- Images are tagged as `latest`, `sha-<shortsha>`, and `<package-major>.<package-minor>.<github_run_number>`.
- The pushed image includes BuildKit SBOM and maximum provenance attestations.
- The Docker Hub repository must exist before the first publish job runs.
