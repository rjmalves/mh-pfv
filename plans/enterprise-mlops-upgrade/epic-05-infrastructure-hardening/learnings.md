# Epic 05 Learnings: Infrastructure Hardening

**Epic**: epic-05-infrastructure-hardening
**Date**: 2026-02-22
**Tickets**: E05-T001 (Docker optimization), E05-T002 (CI quality gates), E05-T003 (Resource configuration)

---

## Patterns Established

- **Two-stage Docker build pattern**: Builder stage based on `rocker/r-ver:4.5.2` installs build tools, restores renv, and compiles packages; runtime stage copies only `/usr/local/lib/R/site-library` and `/usr/local/lib/R/library` plus `main.r`. Eliminates build tools, compiler toolchains, and renv scaffolding from the final image. See `/home/rogerio/git/mh-pfv/Dockerfile` lines 6-99.

- **RENV_CONFIG_REPOS_OVERRIDE for PPM binaries**: Setting `RENV_CONFIG_REPOS_OVERRIDE="https://p3m.dev/cran/__linux__/noble/latest"` in the builder stage routes all CRAN package installs through Posit Package Manager pre-built Linux binaries, dramatically reducing compile time. GitHub-sourced packages (`pfvIO`) still install from source via renv. See `Dockerfile` line 33.

- **ENV var priority chain (CLI > env var > default)**: `cli_main()` in `R/cli.r` resolves each boolean parameter with `!isTRUE(param)` as the fallback trigger, then calls `read_env_flag()` / `read_env_integer()`. Because `argparse` `store_true` always returns `FALSE` (not `NULL`) for unset flags, the condition `!isTRUE(FALSE)` correctly evaluates to `TRUE`, allowing env vars to override the argparse default without the user passing the flag. See `R/cli.r` lines 91-99.

- **`read_env_workers_fallback()` as a private parallel.r helper**: Rather than threading a `workers` parameter through `train_main()` / `predict_main()` signatures, `setup_parallel_plan()` calls the private `read_env_workers_fallback()` helper (defined at `R/parallel.r` lines 107-119) before auto-detect. This keeps pipeline function signatures stable while enabling environment-level configuration.

- **Concurrency groups across all workflows**: All five CI workflows now use `${{ github.workflow }}-${{ github.head_ref || github.ref }}` with `cancel-in-progress: true`, cancelling redundant runs when a new commit is pushed to the same branch or PR. See `.github/workflows/*.yaml`.

- **`r-lib/actions/setup-r-dependencies@v2` for lint**: Replacing manual `install.packages("remotes")` + `remotes::install_version("lintr", version = "3.2.0")` with the standard `extra-packages: any::lintr, any::cyclocomp` + `needs: lint` eliminates version pinning fragility and enables r-lib's built-in caching. See `.github/workflows/lint.yaml` lines 34-37.

- **Benchmark workflow as non-blocking informational CI**: `benchmark.yaml` sets `continue-on-error: true` at the job level, not just on individual steps. This means arrow/ZSTD failures (which still block train/predict benchmarks) do not block PR merges. See `.github/workflows/benchmark.yaml` line 14.

---

## Architectural Decisions

- **Decision: `libzstd-dev` explicitly installed in runtime stage** -- Rejected: relying on arrow's transitive linkage. Rationale: missing `libzstd-dev` at runtime causes a silent segfault in arrow, not a clean R error with a useful message. Explicit installation makes the dependency visible and documentable. See `Dockerfile` lines 68-78.

- **Decision: `ARROW_WITH_ZSTD=ON` set as ENV in builder, not as a CMake flag** -- Rejected: passing it as a build argument to `install.packages`. Rationale: the environment variable is picked up by arrow's build system automatically; no custom `install.packages()` wrapper needed. See `Dockerfile` line 32.

- **Decision: `read_env_workers_fallback()` in `R/parallel.r`, NOT in `R/cli.r`** -- Rejected: placing the fallback inside `cli_main()` and threading `workers` through the call chain. Rationale: `setup_parallel_plan()` is also called directly (e.g., from tests and programmatic use), so the fallback belongs with the function that consumes it. The ticket specification explicitly required this approach to avoid widening `train_main`/`predict_main` signatures.

- **Decision: `withr` moved from a test-only implicit dependency to an explicit `Suggests` entry** -- Rejected: leaving it undeclared. Rationale: `withr::local_envvar()` is used throughout the new test-cli.r test suite; without the `Suggests` declaration, `R CMD check` emits a note. Added to `DESCRIPTION` Suggests field.

- **Decision: benchmark artifact upload path changed from `inst/benchmarks/` to `benchmark-results/`** -- The ticket spec's example code used `inst/benchmarks/` as the upload path but the benchmark R script creates `benchmark-results/` via `dir.create(file.path(getwd(), "benchmark-results"))`. The implementation correctly uploads from `benchmark-results/`, matching the script's actual output directory. See `.github/workflows/benchmark.yaml` lines 41-59.

---

## Files and Structures Created

- `/home/rogerio/git/mh-pfv/Dockerfile` -- Complete rewrite; two-stage build with builder and runtime stages, `MHPFV_*` ENV defaults added.
- `/home/rogerio/git/mh-pfv/.dockerignore` -- Added exclusions for `plans/`, `.claude/`, `inst/benchmarks/`, `mhpfv.Rcheck/`.
- `/home/rogerio/git/mh-pfv/.github/workflows/benchmark.yaml` -- New workflow; non-blocking benchmark runner triggered on PRs to `main`.
- `/home/rogerio/git/mh-pfv/R/cli.r` -- Added `read_env_flag()`, `read_env_integer()`, and expanded `cli_main()` with `parallel`, `resume`, `workers` parameters.
- `/home/rogerio/git/mh-pfv/R/parser.r` -- Added `--parallel`, `--resume`, `--workers` CLI arguments to `inner_parser_generic_args()`.
- `/home/rogerio/git/mh-pfv/R/parallel.r` -- Added `read_env_workers_fallback()` private helper; wired into `setup_parallel_plan()`.
- `/home/rogerio/git/mh-pfv/main.r` -- Updated to pass `parallel`, `resume`, `workers` from parsed args to `cli_main()`.
- `/home/rogerio/git/mh-pfv/tests/testthat/test-cli.r` -- Near-complete rewrite; previous 3-test file expanded to comprehensive test suite covering `read_env_flag()`, `read_env_integer()`, `cli_main()` with env var resolution, `get_parser()` with new flags, and `setup_parallel_plan()` with `MHPFV_WORKERS`.

---

## Conventions Adopted

- **ENV var naming**: All mhpfv-specific environment variables are prefixed `MHPFV_`. Boolean flags default to the string `"false"`, integer vars default to empty string `""` (meaning auto-detect). This matches the Dockerfile declarations: `ENV MHPFV_PARALLEL=false`, `ENV MHPFV_RESUME=false`, `ENV MHPFV_WORKERS=`. See `Dockerfile` lines 89-92.

- **`!isTRUE(param)` as env var fallback gate**: When a parameter comes from argparse with a `store_true` action, its default is `FALSE` (not `NULL`). The check `!isTRUE(param)` is the correct idiom to detect "not explicitly TRUE" -- it allows env var override when the user did not pass the flag, while respecting explicit `TRUE` from the CLI. See `R/cli.r` lines 91-96.

- **Roxygen2 documentation on non-exported helpers**: `read_env_flag()` and `read_env_integer()` have full roxygen2 docblocks despite not being exported, following the codebase standard for documenting intent within source files (matching `validate_workers()` in `R/parallel.r`).

- **`r-lib/actions` version pinning at major version**: All r-lib actions use `@v2` (e.g., `r-lib/actions/setup-r@v2`), consistent with the existing `R-CMD-check.yaml` convention. Do not pin to minor versions.

- **Docker label consolidation**: All six OCI labels are in a single multi-line `LABEL` instruction in the runtime stage only (not the builder), which keeps the builder layer count low and the label metadata in the published image. See `Dockerfile` lines 61-66.

---

## Surprises and Deviations

- **Benchmark artifact upload path**: The ticket's example `benchmark.yaml` specified `path: inst/benchmarks/` for the artifact upload step. The implemented benchmark script creates a dedicated `benchmark-results/` directory at the workspace root. The final `benchmark.yaml` correctly uses `path: benchmark-results/` to match the script's output, not the ticket example. Future benchmark result handling should be aware that outputs land in `benchmark-results/`, not `inst/benchmarks/`.

- **Man page cleanup as a side effect**: Three man pages were deleted (`man/ajusta_regressao_ger_irrad.Rd`, `man/organiza_resultados.Rd`, `man/train_main.Rd`) and others updated (`man/cli_main.Rd`, `man/predict_main.Rd`, `man/setup_parallel_plan.Rd`) as a result of running `devtools::document()` after the R code changes. These deletions reflect functions that had their roxygen export markers removed in earlier epics but whose man files persisted. This cleanup was correct and expected.

- **`withr` added to Suggests explicitly**: The test suite for E05-T003 uses `withr::local_envvar()` extensively, but `withr` was never declared in `DESCRIPTION`. Adding it to `Suggests` required a `DESCRIPTION` edit that was not mentioned in any ticket but is necessary for `R CMD check` compliance.

- **Arrow ZSTD remains unverified in CI**: The Dockerfile correctly sets `ARROW_WITH_ZSTD=ON` and installs `libzstd-dev` in both stages. However, actual Docker build verification (acceptance criterion: `docker run --rm mhpfv:test Rscript -e "arrow::arrow_info()$capabilities[['zstd']]"` prints `TRUE`) cannot be confirmed from the git diff alone. The train/predict benchmarks in `inst/benchmarks/` remain blocked until the Docker image is built and verified.

---

## Recommendations for Future Epics

- **Epic 06**: The three new `MHPFV_*` environment variables (`MHPFV_PARALLEL`, `MHPFV_RESUME`, `MHPFV_WORKERS`) are already declared in `Dockerfile` and respected by `cli_main()`. Any observability or health-reporting tool should log these values at startup for auditability -- they represent the runtime configuration state of a given run. See `R/cli.r` lines 86-104.

- **Epic 06**: The `benchmark.yaml` workflow's `continue-on-error: true` means failed benchmarks are silent in CI. A future observability ticket could add a benchmark results parser that posts a PR comment with timing summaries, enabling regression detection without blocking merges. The artifact is uploaded to `benchmark-results/` with 30-day retention.

- **Standardize `train_main` parallel dispatch**: The inconsistency (explicit `if/else` in `train_main` vs `do.call` in `predict_main`) was noted in Epic 03 and Epic 04 learnings but NOT fixed in Epic 05. It remains in `R/train.r`. Epic 06 refactor work should address this.

- **`cleanup_checkpoint()` export**: If a `mhpfv cleanup` CLI subcommand is added in Epic 06, `cleanup_checkpoint()` in `R/provenance.r` must be exported from NAMESPACE. Currently accessible only via `mhpfv:::cleanup_checkpoint`.

- **Cache key float representation risk**: The Haversine cache uses `paste()` on raw float coordinates (`R/utils.r`), which is platform-dependent. This was carried forward from Epic 03 and is not addressed in Epic 05. Any future cache key change should use `format(x, digits = 15)` for reproducibility.
