# Accumulated Learnings Summary -- Through Epic 01

**Last Updated**: 2026-02-17
**Epics Completed**: 1 (Quality Foundation)

## Test Infrastructure

- Test data at `tests/testthat/data/` covers July--September 2025 with 2 plants (BAUFI1, BAUFI2)
- Every test calling `parse_config()` must use `janela = list("2025-07-01", "2025-09-30")` -- `list()` not `c()`
- Factory functions in `tests/testthat/helper-generators.r` provide 7+ generators following `gen_<entity>()` naming
- Use `withr::local_tempdir()` for all temp directories, `withr::local_envvar()` for env overrides
- All tests guard with `skip_if_not(dir.exists(test_path("data")))` when test dataset is required
- Use `pkgload::load_all('.')` not `library(mhpfv)` -- the latter breaks covr instrumentation

## I/O Layer

- All data access routes through `pfvIO::conectamock_pfv(datadir)` which creates a filesystem-backed connection
- Connection object is passed to `parse_config()`, `get_dataset()`, `get_usinas()`, and all `get_*()` functions
- `pfvIO:::get_model_artifact()` (triple colon) is used in production code -- fragile coupling to pfvIO internals
- Arrow Parquet files require ZSTD support (`ARROW_WITH_ZSTD=ON`) for test data

## Codebase Architecture

- `R/cli.r::cli_main(datadir)` is the exported entry point; `main.r` is a thin shim with `q(status=...)` handling
- `config$ids_usinas` defaults to `list()` meaning "all plants" -- `parse_config()` populates from connection
- `processar_usina()` in `R/predict.r` is the most complex function (10 params, 8 internal calls, 75 lines)
- `get_dataset()` in `R/predict.r` is shared between train and predict and loads 5 data components
- `R/zzz.r` contains `.onLoad`/`.onUnload` hooks that covr cannot exercise (~0.8% permanent coverage gap)

## Code Conventions

- All column names and error messages are in Portuguese (e.g., `id_usina`, `data_hora_observacao`, `Modo invalido`)
- Tests use nested `test_that()` blocks: outer block asserts `is.function(f)`, inner blocks test behaviors
- data.table is the exclusive data manipulation library; use `data.table::setDT()` on Arrow read results
- No mocking of pfvIO -- integration tests call real pfvIO functions against filesystem test dataset

## Quality Metrics

- Coverage baseline: 61.1% -> final: 84.8% (target was >= 80%)
- CI threshold: 75% with 2% tolerance (Codecov), patch target 70% with 5% tolerance
- Main remaining gap: `R/predict.r` at 27.8% coverage (processar_usina branching)
- Snapshot tests in `_snaps/snapshot-regression.md` capture model coefficients and output summaries

## Known Technical Debt

- `parsearg_janela.character` S3 method is not registered in NAMESPACE (missing S3method directive)
- `pfvIO:::get_model_artifact()` uses triple-colon access to unexported pfvIO function
- `R/zzz.r` lifecycle hooks are permanently uncoverable by covr (5 lines)
- Arrow ZSTD requirement is undocumented in test setup instructions

## Recommendations for Next Epics

- Epic 02: Snapshot tests are the primary regression safety net during refactoring -- run before/after every change
- Epic 02: `processar_usina()` needs error-path test coverage when restructured for strategy pattern
- Epic 02: `get_dataset()` should be parameterized or extracted since train/predict load different components
- Epic 03: `lapply` calls in `predict_main()` line 52 are the natural parallelization points
- Epic 05: Raise CI threshold from 75% to 80% once coverage stabilizes above 80% for 3+ PRs
