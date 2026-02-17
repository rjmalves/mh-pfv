# Accumulated Learnings Summary -- Through Epic 02

**Last Updated**: 2026-02-17
**Epics Completed**: 2 (Quality Foundation, Extensibility Refactor)

## Test Infrastructure

- Test data at `tests/testthat/data/` covers July--September 2025 with 2 plants (BAUFI1, BAUFI2)
- Every test calling `parse_config()` must use `janela = list("2025-07-01", "2025-09-30")` -- `list()` not `c()`
- Factory functions in `tests/testthat/helper-generators.r` provide 9+ generators (`gen_config`, `gen_usinas`, `gen_geracao_observada`, `gen_irradiancia_prevista`, `gen_corte_observado`, `gen_mhg`, `gen_model_artifact`, etc.)
- Use `withr::local_tempdir()` for all temp directories; `skip_if_not(dir.exists(test_path("data")))` for dataset-dependent tests
- Mock S3 methods in tests require `registerS3method("generic", "class", fn, envir = asNamespace("mhpfv"))` -- simple function definition does not enable dispatch through the package namespace
- Snapshot tests in `_snaps/snapshot-regression.md` are the primary regression safety net; run before/after any refactoring

## I/O Layer

- All data access routes through `pfvIO::conectamock_pfv(datadir)` creating a filesystem-backed connection
- `pfvIO:::get_model_artifact()` (triple colon) is used in `R/predict.r` line 147 -- fragile coupling to pfvIO internals
- Arrow Parquet files require ZSTD support (`ARROW_WITH_ZSTD=ON`) for test data reads
- Model artifacts are `list(id_usina, parametros)` as RDS; format is NOT strategy-aware yet

## Architecture After Epic 02

- `R/cli.r::cli_main(datadir)` is the entry point; dispatches to `train_main(config)` or `predict_main(config)`
- `train_main` and `predict_main` accept optional `strategy` parameter (default: `linear_regression_strategy()`)
- Strategy flows: `train_main -> ajustar_usina -> fit_model(strategy, ...)` and `predict_main -> processar_usina -> preenche_geracao_unit -> predict_model(strategy, ...)`
- Three S3 generics: `fit_model`, `predict_model`, `model_metadata` -- defined in `R/model-strategy.r`
- Linear regression concrete strategy in `R/model-linear-regression.r` -- delegates to existing `ajusta_regressao_ger_irrad()` and `substitui_por_estimativas()`
- Input validation framework in `R/validation.r` with 5 schemas -- exported but NOT wired into pipeline (opt-in)
- `associa_nwp_usina()` is called per-plant in both pipelines -- redundant work that should be hoisted for parallelization

## Strategy Pattern Conventions

- Constructor: `new_model_strategy(type, ...)` creates `c(type, "model_strategy")` dual-class object
- Each strategy type gets a convenience constructor (e.g., `linear_regression_strategy()`) in `model-<type>.r`
- Adding a new strategy requires creating 1 file with 4 functions (constructor + 3 methods) -- no existing files modified
- `fit_model` must return an object compatible with the artifact `parametros` slot
- `predict_model` must return a data.table with `valor` and `status` columns
- `strategy` is always the last named parameter in function signatures for backward compatibility

## Validation Framework

- `validate_input(dt, schema_name)` checks columns, types, and key NAs; collects ALL errors before raising
- 5 schemas: `geracao_observada`, `irradiancia_prevista`, `corte_observado`, `usinas`, `melhor_historico_geracao`
- `check_type()` is lenient: integer passes as numeric; numeric passes as integer schema type
- Schemas are R lists in `get_all_schemas()` -- no external config files
- `validate_all_inputs(dataset, dt_usinas)` validates the full dataset returned by `get_dataset()`

## Code Conventions

- All column names and error messages in Portuguese (e.g., `id_usina`, `Colunas obrigatorias ausentes`)
- Tests use nested `test_that()` blocks: outer asserts `is.function(f)`, inner blocks test behaviors
- data.table exclusively; `copy()` calls preserved at strategy boundaries to prevent mutation
- roxygen2 `@rdname` groups method docs with generics; `[function()]` bracket syntax for exported cross-refs only
- New files: `model-strategy.r`, `model-<type>.r`, `validation.r`; tests: `test-model-strategy.r`, `test-validation.r`, `test-strategy-integration.r`

## Known Technical Debt

- `parsearg_janela.character` S3 method not registered in NAMESPACE (pre-existing)
- `pfvIO:::get_model_artifact()` uses triple-colon access (pre-existing)
- `model[[2]]` hardcoded index in `preenche_geracao_unit` -- should be `model$parametros` (new)
- `R/zzz.r` lifecycle hooks permanently uncoverable by covr (~0.8% gap)
- Validation schemas hardcoded in mhpfv; no sync mechanism with pfvIO column formats
- `validate_all_inputs` does not guard against NULL dataset components

## Recommendations for Next Epics

- Epic 03: `lapply` calls at `train_main` line 52 and `predict_main` line 55 are parallelization points; strategy objects are safe to share across workers
- Epic 03: Hoist `associa_nwp_usina()` out of per-plant loops before parallelizing -- currently computed redundantly per plant
- Epic 03: Use `test_strategy` mock for fast-running parallel correctness tests
- Epic 04: Wire `model_metadata()` into artifact structure as third element alongside `id_usina` and `parametros`
- Epic 04: Reuse `validate_input()` schemas for artifact/provenance validation rather than creating a parallel system
- Epic 04: Fix `model[[2]]` to `model$parametros` when enriching artifact structure
- Epic 05: Raise CI threshold from 75% to 80% once coverage stabilizes
