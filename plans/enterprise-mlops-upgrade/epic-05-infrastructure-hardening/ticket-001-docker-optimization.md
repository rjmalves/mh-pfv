# E05-T001 Optimize Docker Image with Multi-Stage Build

## Context

### Background

The mhpfv package currently ships in a Docker image built from `rocker/tidyverse:4.5.2`, a heavyweight base that includes the full tidyverse ecosystem, RStudio Server, and TeX Live -- none of which are needed at runtime. The local image (`mhpfv-coverage:latest`) occupies 4.29 GB virtual / 1.09 GB compressed, far exceeding the 800 MB target. Since Epic 03 introduced `future` and `future.apply` as new runtime dependencies, and Epic 04 added `digest` and `jsonlite` (both already present via transitive deps), the Dockerfile must account for all current `Imports` in `DESCRIPTION`.

### Relation to Epic

This is the first ticket in Epic 05 (Infrastructure Hardening). It directly targets the epic's goal of reducing the production image below 800 MB and improving build time through layer caching. The resulting image serves as the base for the resource configuration ticket (E05-T003), which adds default `ENV` declarations.

### Current State

The existing `Dockerfile` at `/home/rogerio/git/mh-pfv/Dockerfile` is a single-stage build:

```dockerfile
FROM rocker/tidyverse:4.5.2
WORKDIR /app
COPY DESCRIPTION DESCRIPTION
COPY NAMESPACE NAMESPACE
RUN mkdir -p renv/
COPY renv.lock renv.lock
COPY renv/activate.R renv/activate.R
COPY renv/settings.json renv/settings.json
COPY .Rprofile .Rprofile
RUN R -e "renv::restore()"
COPY R/ R/
COPY main.r main.r
RUN R -e "install.packages('remotes')" && \
    R -e "remotes::install_local('.', dependencies = FALSE, upgrade = 'never')"
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD Rscript -e "library(mhpfv); cat('OK')" || exit 1
ENV LOG_LEVEL=info
ENTRYPOINT ["Rscript", "main.r"]
CMD ["--datadir", "/app/data"]
```

Key problems:

- `rocker/tidyverse:4.5.2` bundles ~1.5 GB of unnecessary packages (ggplot2, tidyr, dplyr, stringr, etc.)
- System libraries for compilation (build-essential, compilers) remain in the final image
- renv restores and compiles from source without leveraging Posit Package Manager (PPM) binaries
- The `remotes::install_local()` step installs the full package but build tools stay
- `.dockerignore` already excludes tests and docs, which is correct

Dependencies from `DESCRIPTION` that must be present at runtime:

- `argparse` (requires Python >= 3.2 at runtime for argument parsing)
- `arrow` (C++ library, largest dependency -- needs ZSTD codec)
- `data.table`
- `digest`
- `future`, `future.apply`
- `jsonlite`
- `lgr`
- `lubridate`
- `pfvIO` (installed from GitHub via `Remotes: lkhenayfis/pfvIO`)

The `renv.lock` pins R 4.5.2 and all package versions. The `.Rprofile` sources `renv/activate.R`.

## Specification

### Requirements

1. Replace the single-stage Dockerfile with a two-stage build:
   - **Stage 1 (builder)**: Based on `rocker/r-ver:4.5.2`, installs build tools, system libraries, restores renv, and installs the package
   - **Stage 2 (runtime)**: Based on `rocker/r-ver:4.5.2`, copies only the installed R library from the builder, adds runtime system dependencies, and sets the entrypoint
2. Use Posit Public Package Manager (PPM) for pre-compiled Linux binaries where possible, falling back to source compilation only for `pfvIO` (GitHub-only)
3. Ensure arrow is built with ZSTD codec support (`ARROW_WITH_ZSTD=ON`) to resolve the known technical debt from the learnings
4. Python must be present in the runtime stage (required by `argparse`)
5. Preserve the existing `.dockerignore` content
6. Preserve the existing container labels, `HEALTHCHECK`, `ENTRYPOINT`, and `CMD` semantics
7. Final image must be under 800 MB (virtual size)
8. Add a `MHPFV_VERSION` build argument for image tagging, defaulting to the `Version` field in DESCRIPTION

### Inputs/Props

- `Dockerfile` -- the file being rewritten
- `renv.lock` -- dependency specifications (read-only, unchanged)
- `.dockerignore` -- build context exclusions (update only if necessary)
- `DESCRIPTION` -- package metadata (read-only)

### Outputs/Behavior

- A two-stage `Dockerfile` that:
  - Produces a runtime image under 800 MB virtual size
  - Successfully runs `Rscript main.r --datadir /app/data` with test data
  - Passes the existing `HEALTHCHECK` (`Rscript -e "library(mhpfv); cat('OK')"`)
  - Supports arrow Parquet reads with ZSTD compression
  - Retains all OCI labels

### Error Handling

- If renv restore fails in the builder stage, the build must fail clearly (no `|| true`)
- If arrow ZSTD compilation fails, the build must fail (do not silently skip codecs)
- Runtime stage must validate that Python is accessible (used by argparse)

## Acceptance Criteria

- [ ] Given the new Dockerfile, when `docker build -t mhpfv:test .` is run, then the build completes without errors
- [ ] Given the built image, when `docker images mhpfv:test` is inspected, then the virtual size is under 800 MB
- [ ] Given the built image, when `docker run --rm mhpfv:test Rscript -e "library(mhpfv); cat('OK')"` is run, then it prints "OK" and exits 0
- [ ] Given the built image, when `docker run --rm mhpfv:test Rscript -e "arrow::arrow_info()$capabilities[['zstd']]"` is run, then it prints `TRUE`
- [ ] Given the built image, when `docker run --rm mhpfv:test python3 --version` is run, then it prints a Python >= 3.2 version
- [ ] Given the built image, when test data is mounted and the entrypoint runs, then train/predict completes as before
- [ ] Given the Dockerfile, when inspected, then it has exactly 2 `FROM` directives (builder + runtime)
- [ ] Given the `.dockerignore`, when inspected, then `plans/` is excluded (CI/plan files not needed in image)
- [ ] Given the built image, when `docker inspect` is run, then the OCI labels (`org.opencontainers.image.*`) are present

## Implementation Guide

### Suggested Approach

1. **Rewrite `Dockerfile` as two-stage build**:

   ```dockerfile
   # ---- Stage 1: Builder ----
   FROM rocker/r-ver:4.5.2 AS builder

   # Install build tools and system libraries
   RUN apt-get update && apt-get install -y --no-install-recommends \
       build-essential cmake libcurl4-openssl-dev libssl-dev libxml2-dev \
       libfontconfig1-dev libfreetype6-dev libfribidi-dev libharfbuzz-dev \
       libjpeg-dev libpng-dev libtiff-dev python3 python3-dev git \
       && rm -rf /var/lib/apt/lists/*

   # Configure PPM for binary packages
   RUN echo 'options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))' \
       >> /usr/local/lib/R/etc/Rprofile.site

   WORKDIR /app

   # Setup renv (cached layer)
   COPY renv.lock renv.lock
   COPY renv/activate.R renv/activate.R
   COPY renv/settings.json renv/settings.json
   COPY .Rprofile .Rprofile
   RUN mkdir -p renv/
   RUN R -e "renv::restore()"

   # Copy and install the package
   COPY DESCRIPTION DESCRIPTION
   COPY NAMESPACE NAMESPACE
   COPY R/ R/
   COPY main.r main.r
   RUN R -e "remotes::install_local('.', dependencies = FALSE, upgrade = 'never')"

   # ---- Stage 2: Runtime ----
   FROM rocker/r-ver:4.5.2

   # Runtime-only system dependencies
   RUN apt-get update && apt-get install -y --no-install-recommends \
       libcurl4-openssl-dev libssl-dev python3 \
       && rm -rf /var/lib/apt/lists/*

   # Copy R library from builder
   COPY --from=builder /usr/local/lib/R/site-library /usr/local/lib/R/site-library
   COPY --from=builder /usr/local/lib/R/library /usr/local/lib/R/library

   # Copy application code
   WORKDIR /app
   COPY main.r main.r

   # Labels, healthcheck, entrypoint (same as original)
   ...
   ```

2. **Key decisions**:
   - Use `rocker/r-ver:4.5.2` (not `rocker/r-base`) -- same R version as renv.lock, smaller than tidyverse
   - PPM provides pre-compiled binaries for Ubuntu, reducing builder stage compile time
   - `renv.lock` is used in the builder to pin exact versions; the runtime just copies the installed library tree
   - Arrow's C++ library is compiled with ZSTD by default when installing from PPM; verify with acceptance test
   - Python3 must be in both stages (builder for any package install scripts, runtime for argparse)

3. **Update `.dockerignore`** to also exclude:
   - `plans/` (implementation plan files)
   - `inst/benchmarks/` (benchmark scripts)
   - `.claude/` (AI assistant config)
   - `mhpfv.Rcheck/` (check output)

4. **Update the Docker CI workflow** (`docker.yaml`) to add BuildKit cache mounts for renv if desired (optional optimization for CI build speed)

### Key Files to Modify

- `/home/rogerio/git/mh-pfv/Dockerfile` -- complete rewrite to multi-stage
- `/home/rogerio/git/mh-pfv/.dockerignore` -- add exclusions for `plans/`, `inst/benchmarks/`, `.claude/`, `mhpfv.Rcheck/`
- `/home/rogerio/git/mh-pfv/.github/workflows/docker.yaml` -- add Docker layer caching via `cache-from`/`cache-to` on the build-push-action

### Patterns to Follow

- The existing Dockerfile already uses good layer ordering (DESCRIPTION before R/ for caching). Preserve this in the builder stage.
- Follow the `rocker` project conventions for R Docker images.
- Use `--no-install-recommends` on all `apt-get install` calls to minimize layer size.
- Use `rm -rf /var/lib/apt/lists/*` after every `apt-get` call.

### Pitfalls to Avoid

- **Do NOT remove python3 from the runtime stage** -- argparse requires it at runtime for the CLI parser. The `argparse` R package delegates to Python's `argparse` module.
- **Do NOT use `rocker/r-base`** -- it uses Debian testing which may not match `renv.lock`'s R version pinning.
- **Do NOT skip the renv restore** in favor of direct `install.packages()` -- renv.lock provides exact version pinning that must be respected for reproducibility.
- **Do NOT copy the entire `/app` directory from builder to runtime** -- only copy the R library paths and `main.r`. The package source code is already installed into the library.
- **Watch for pfvIO** -- it comes from GitHub (`Remotes: lkhenayfis/pfvIO`), so it cannot use PPM binaries. renv handles this via the lock file, but git must be available in the builder stage.
- **Arrow system libraries** -- arrow's C++ runtime needs `libcurl` and `libssl` at runtime. Missing libraries cause segfaults, not clean errors.

## Testing Requirements

### Unit Tests

No R-level unit tests needed for this ticket. Docker builds are validated manually and via CI.

### Integration Tests

- Build the image locally: `docker build -t mhpfv:test .`
- Verify image size: `docker images mhpfv:test --format "{{.Size}}"` is under 800 MB
- Verify healthcheck: `docker run --rm mhpfv:test Rscript -e "library(mhpfv); cat('OK')"`
- Verify arrow ZSTD: `docker run --rm mhpfv:test Rscript -e "arrow::arrow_info()\$capabilities[['zstd']]"`
- Verify Python: `docker run --rm mhpfv:test python3 --version`
- Verify full pipeline: mount test data and run train mode

### E2E Tests

- Push a tag to verify the `docker.yaml` workflow builds and pushes successfully to GHCR.

## Dependencies

- **Blocked By**: E03-T001 (parallel infrastructure -- completed)
- **Blocks**: None

## Effort Estimate

**Points**: 3
**Confidence**: Medium
