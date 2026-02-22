# Accumulated Learnings Summary -- Through Epic 05

**Last Updated**: 2026-02-22
**Epics Completed**: 5 (Quality Foundation, Extensibility Refactor, Performance and Parallelization, MLOps and Provenance, Infrastructure Hardening)

## Test Infrastructure

- Test data at `tests/testthat/data/` covers July--September 2025 with 2 plants (BAUFI1, BAUFI2)
- Every test calling `parse_config()` must use `janela = list("2025-07-01", "2025-09-30")` -- `list()` not `c()`
- Factory functions in `tests/testthat/helper-generators.r` provide `gen_model_artifact()` (enriched, with metadata) and `gen_model_artifact_legacy()` (old format, no metadata); both are needed for backward-compatibility tests
- Use `withr::local_tempdir()` for temp directories; `skip_if_not(dir.exists(test_path("data")))` for dataset-dependent tests
- Use `withr::local_envvar()` for all environment variable manipulation in tests; `withr` must be in `DESCRIPTION` Suggests
- Mock S3 methods require `registerS3method("generic", "class", fn, envir = asNamespace("mhpfv"))` for dispatch
- Snapshot tests in `_snaps/snapshot-regression.md` are the primary regression safety net
- Parallel tests must call `withr::defer(future::plan("sequential"))` to avoid leaking plan state
- Internal functions are tested via `mhpfv:::fn()` triple-colon access
- `lgr` log messages do NOT propagate as R conditions -- `expect_warning()` will not catch them
- Tests use nested `test_that()` blocks: outer asserts `is.function(f)`, inner blocks test behaviors

## I/O Layer

- All pipeline data access routes through `pfvIO::conectamock_pfv(datadir)` creating a filesystem-backed connection
- `pfvIO:::get_model_artifact()` (triple colon) is used in `R/predict.r` -- fragile coupling to pfvIO internals (pre-existing)
- Arrow Parquet files require ZSTD support; `ARROW_WITH_ZSTD=ON` and `libzstd-dev` are set in `Dockerfile` builder/runtime stages
- Model artifacts are `list(id_usina, parametros, metadata)` as RDS; enriched by `build_model_artifact()` in `R/artifact.r`
- Provenance and checkpoint files are JSON; intermediate per-plant predict results are RDS (`plant-result-{id_usina}.rds`)
- All file-writing operations in `R/provenance.r` are wrapped in `tryCatch` so I/O failures never crash the pipeline

## Architecture After Epic 05

- `R/cli.r::cli_main(datadir, parallel, resume, workers)` dispatches to `train_main(config, parallel, resume)` or `predict_main(config, parallel, resume)`
- Priority chain for each runtime parameter: CLI flag > `MHPFV_*` env var > hardcoded default; `!isTRUE(param)` is the correct gate because argparse `store_true` returns `FALSE` (not `NULL`) for unset flags
- `MHPFV_PARALLEL`, `MHPFV_RESUME`, `MHPFV_WORKERS` declared as `ENV` defaults in `Dockerfile` runtime stage; configurable at `docker run` time
- `setup_parallel_plan()` in `R/parallel.r` reads `MHPFV_WORKERS` via `read_env_workers_fallback()` before falling back to `availableCores() - 1`
- Artifact enrichment happens inside `ajustar_usina()` in `R/train.r` via `build_model_artifact()`; provenance registered with `on.exit()` before parallel plan cleanup
- `<<-` is used in `lapply` callbacks to update provenance in enclosing scope; documented with inline comments

## Docker / Infrastructure Conventions

- Two-stage Dockerfile: builder `rocker/r-ver:4.5.2` with build tools + renv restore; runtime `rocker/r-ver:4.5.2` copies R library paths only
- `RENV_CONFIG_REPOS_OVERRIDE="https://p3m.dev/cran/__linux__/noble/latest"` in builder routes CRAN packages to PPM pre-built binaries
- Runtime stage installs: `libcurl4-openssl-dev`, `libssl-dev`, `libzstd-dev`, `python3` -- missing any causes silent segfault (not clean R error)
- `plans/`, `.claude/`, `inst/benchmarks/`, `mhpfv.Rcheck/` excluded from Docker build context via `.dockerignore`
- All six OCI labels in a single `LABEL` instruction in the runtime stage only; `MHPFV_VERSION` passed as `ARG`

## CI/CD Conventions

- All five workflows use `concurrency: group: ${{ github.workflow }}-${{ github.head_ref || github.ref }}` with `cancel-in-progress: true`
- Lint workflow uses `r-lib/actions/setup-r-dependencies@v2` with `extra-packages: any::lintr, any::cyclocomp`; no manual `install.packages`
- `test-coverage.yaml` triggers on push/PR to both `main` and `develop`; 75% threshold from E01-T008 is unchanged
- `benchmark.yaml` triggers on PRs to `main` only; `continue-on-error: true` on the job (not just steps); artifact uploaded to `benchmark-results/` (30-day retention)
- `docker.yaml` uses `cache-from: type=gha` / `cache-to: type=gha,mode=max` for layer caching; triggers on tags only

## Strategy Pattern Conventions

- Constructor: `new_model_strategy(type, ...)` creates `c(type, "model_strategy")` dual-class object
- Adding a new strategy: create 1 file with 4 functions (constructor + 3 methods) -- no existing files modified
- `strategy` is always the second-to-last named parameter; `parallel` and `resume` come after

## MLOps / Provenance Conventions

- Config identity determined by `normalize_config_for_hash()` in `R/artifact.r`; same hash in artifact metadata and provenance records
- Provenance record fields: `run_id`, `mode`, `package_version`, `r_version`, `start_time`, `end_time`, `duration_seconds`, `config_hash`, `n_plants`, `plant_ids`, `plant_status`, `parallel`, `status`
- File naming: `provenance-{run_id}.json` (permanent), `checkpoint-{run_id}.json` (ephemeral), `plant-result-{id_usina}.rds` (ephemeral)
- Backward compatibility: old-format artifacts (no `metadata`) accepted with lgr warning; check via `"metadata" %in% names(artifact)`

## Parallelism Conventions

- `parallel = FALSE` default on all entry points for backward compatibility
- `future.seed = TRUE` required on all `future_lapply` calls for reproducibility
- Artifact and checkpoint writing remain sequential -- never from parallel workers
- Strategy objects are plain S3 lists -- safe to serialize to workers without special handling
- `copy()` on data.table objects passed to workers where `:=` mutation could occur

## Code Conventions

- All column names, error messages, and log messages in Portuguese
- data.table exclusively; `copy()` calls at strategy and parallel boundaries; `unname()` on named vectors before passing to `data.table()` constructor
- Non-exported helper functions documented with roxygen2 docblocks (no `@export`); consistent with `validate_workers()` in `R/parallel.r`

## Known Technical Debt

- `parsearg_janela.character` S3 method not registered in NAMESPACE (pre-existing)
- `pfvIO:::get_model_artifact()` triple-colon access (pre-existing)
- `R/zzz.r` lifecycle hooks permanently uncoverable by covr (~0.8% gap)
- Inconsistent parallel dispatch: `train_main` (explicit if/else) vs `predict_main` (do.call) -- carried across 3 epics without resolution
- Cache key uses raw `paste()` on floats in `R/utils.r` -- platform-dependent representation risk
- `attr(diffs, "timestamp_a")` in `compare_metadata()` in `R/model-comparison.r` -- attributes lost on JSON serialization
- `read_checkpoint()` orders by `file.mtime()` -- unreliable on network filesystems
- Per-plant intermediate results written only when `resume = TRUE`; a crash during non-resume predict leaves no resumable state
- Arrow ZSTD acceptance test (`docker run` with `arrow::arrow_info()$capabilities[['zstd']]`) cannot be confirmed from source alone; requires a Docker build

## Recommendations for Next Epics

- Epic 06: Log `MHPFV_PARALLEL`, `MHPFV_RESUME`, `MHPFV_WORKERS` values at startup in `cli_main()` for auditability; values live in `R/cli.r` lines 86-104
- Epic 06: `provenance-{run_id}.json` files feed health reports directly; `duration_seconds`, `n_plants`, `status`, `plant_status` are ready to aggregate
- Epic 06: All provenance/checkpoint logs use `lgr::get_logger("mhpfv")`; configure appenders on this logger, not a new name
- Epic 06: Benchmark workflow posts results as artifact but no PR comment; add a parser step to post timing summaries as PR comment for regression detection
- Epic 06: Fix inconsistent parallel dispatch style in `train_main` (`R/train.r`) to match `predict_main`'s `do.call` pattern
- Epic 06: Export `cleanup_checkpoint()` from NAMESPACE if a `mhpfv cleanup` CLI subcommand is added
