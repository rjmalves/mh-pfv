# Epic 01: Quality Foundation -- Learnings

**Epic**: epic-01-quality-foundation
**Date**: 2026-02-17
**Tickets Completed**: 8/8

---

## Patterns Established

- **Nested test_that structure**: All new test files use an outer `test_that("function_name", { ... })` block that first asserts `is.function(f)`, with inner `test_that()` blocks for individual behaviors. Observed in `/home/rogerio/git/mh-pfv/tests/testthat/test-logging.r`, `test-parser-expanded.r`, `test-escrita.r`, `test-cli.r`, `test-integration-train.r`, `test-integration-predict.r`, and `test-predict.r`.

- **Factory function convention**: Test data generators live in `/home/rogerio/git/mh-pfv/tests/testthat/helper-generators.r` and follow the naming convention `gen_<entity>()`. Each generator has sensible defaults and accepts overrides via named parameters. The `gen_geracao_observada()` function uses S3-like dispatch through `gen_geracao_apply_pattern()` to handle different data patterns (normal, frozen, missing, all_na).

- **Janela override pattern for tests**: The test dataset covers July--September 2025 exclusively. Every test that calls `parse_config()` must pass `janela = list("2025-07-01", "2025-09-30")` to override the default rolling 90-day window. Using `list()` rather than `c()` is required because `parse_config()` expects a list. This is the single most critical pattern for any future test that exercises the pipeline. Observed in every integration and snapshot test file.

- **pkgload::load_all over library**: Tests must use `pkgload::load_all('.')` (or rely on testthat's automatic loading) rather than `library(mhpfv)`. The `library()` call installs the package into the library path, which interferes with covr instrumentation. The test infrastructure relies on testthat's helper-file auto-sourcing.

- **withr for test isolation**: All temporary directories use `withr::local_tempdir()` for automatic cleanup. Environment variable overrides use `withr::local_envvar()`. No manual cleanup code exists in tests. Observed in `/home/rogerio/git/mh-pfv/tests/testthat/test-logging.r` and all integration test files.

- **pfvIO connection via conectamock_pfv**: All data access in tests (and in production) routes through `conectamock_pfv(datadir)` from the pfvIO package. This creates a mock connection object that reads from the filesystem. The connection is then passed to `parse_config()`, `get_dataset()`, `get_usinas()`, etc. This is the universal I/O entry point. Observed in `/home/rogerio/git/mh-pfv/R/cli.r` and all test files.

- **Snapshot via serialized summary**: Snapshot tests in `/home/rogerio/git/mh-pfv/tests/testthat/test-snapshot-regression.r` snapshot per-plant summaries (n_rows, mean, sd, min, max, status_counts) rather than full datasets. Model artifacts are snapshotted as structured lists with `round(..., 8)` applied to coefficients. This keeps snapshot files manageable (~214 lines) while detecting numerical regressions.

---

## Architectural Decisions

- **cli_main as exported function, main.r as thin shim**: The original `main.r` (28 lines) was split into `R/cli.r::cli_main()` (exported, testable, covr-measurable) and a reduced `main.r` shim (16 lines) that handles `q(status = ...)`. The shim only loads `library(mhpfv)`, calls `get_parser()`, and delegates to `cli_main()`. The alternative of keeping all logic in `main.r` was rejected because covr cannot measure files outside the package boundary. See `/home/rogerio/git/mh-pfv/R/cli.r` and `/home/rogerio/git/mh-pfv/main.r`.

- **75% CI threshold with 2% tolerance**: The coverage threshold was set to 75% rather than 80% to accommodate measurement variance across R versions and platforms. Codecov project target is 75% with 2% threshold (allowing drops to 73%), and patch target is 70% with 5% threshold. The in-workflow check uses `covr::percent_coverage(cov) < 75` as a hard stop. See `/home/rogerio/git/mh-pfv/.github/workflows/test-coverage.yaml` and `/home/rogerio/git/mh-pfv/codecov.yml`.

- **No mocking of pfvIO**: Integration tests call real pfvIO functions (`conectamock_pfv`, `get_config`, `get_usinas`, `get_geracao_observada`, etc.) against the filesystem test dataset rather than mocking them. This ensures that schema changes in pfvIO are caught by mhpfv tests. The trade-off is that tests require the test dataset at `tests/testthat/data/` and are slower (~seconds rather than milliseconds).

---

## Files and Structures Created

- `/home/rogerio/git/mh-pfv/R/cli.r` -- Exported `cli_main(datadir)` function that loads config, parses it, and dispatches to `train_main()` or `predict_main()`. Returns `invisible(0L)` on success, throws error on failure.
- `/home/rogerio/git/mh-pfv/tests/testthat/helper-generators.r` -- 7 factory functions: `gen_config`, `gen_default_datas`, `gen_usinas`, `gen_solar_curve`, `gen_geracao_observada`, `gen_irradiancia_prevista`, `gen_corte_observado`, `gen_mhg`, `gen_model_artifact`. Plus internal pattern dispatch functions (`gen_geracao_apply_pattern_*`).
- `/home/rogerio/git/mh-pfv/tests/testthat/test-integration-train.r` -- Integration tests verifying full train pipeline produces valid RDS artifacts with expected structure.
- `/home/rogerio/git/mh-pfv/tests/testthat/test-integration-predict.r` -- Integration tests verifying full predict pipeline (train + predict) produces valid Parquet output with expected schema.
- `/home/rogerio/git/mh-pfv/tests/testthat/test-snapshot-regression.r` -- Snapshot tests capturing model coefficients and predict output summaries per plant.
- `/home/rogerio/git/mh-pfv/tests/testthat/_snaps/snapshot-regression.md` -- Snapshot file with golden reference values for 2 plants (BAUFI1, BAUFI2).
- `/home/rogerio/git/mh-pfv/tests/testthat/test-logging.r` -- Unit tests for `logger_setup()` and `get_pkg_logger()`.
- `/home/rogerio/git/mh-pfv/tests/testthat/test-parser-expanded.r` -- Unit tests for `get_parser()` and `inner_parser_generic_args()`.
- `/home/rogerio/git/mh-pfv/tests/testthat/test-escrita.r` -- Unit tests for `write_melhor_historico_geracao()` and `write_melhor_historico_geracao_sem_cortes()`.
- `/home/rogerio/git/mh-pfv/tests/testthat/test-cli.r` -- Tests for `cli_main()` including error paths and invalid mode detection.
- `/home/rogerio/git/mh-pfv/tests/coverage-baseline.md` -- Coverage baseline report documenting 61.1% initial coverage, per-file breakdown, top 5 gaps, and CI threshold configuration.
- `/home/rogerio/git/mh-pfv/codecov.yml` -- Codecov configuration with project (75%) and patch (70%) targets.

---

## Conventions Adopted

- **Test file naming**: Integration tests use `test-integration-<pipeline>.r`. Snapshot tests use `test-snapshot-<purpose>.r`. Unit tests for specific source files use `test-<source-file-name>.r` or `test-<source-file-name>-expanded.r` when a file with the base name already exists.
- **Portuguese column names and error messages**: All data.table column names (`id_usina`, `data_hora_observacao`, `valor`, `status`, `id_fonte_observacao`) and user-facing error messages are in Portuguese, matching the existing codebase convention. Test assertions use these Portuguese names verbatim.
- **Config construction in tests**: Always use `gen_config(mode = "...", janela = list("2025-07-01", "2025-09-30"))`, set `config$input`, `config$artifact`, `config$output` to temp/test paths, then call `parse_config(config, conn)` to finalize. The `parse_config()` step populates `ids_usinas` from the connection and converts `janela` to Date objects.
- **skip_if_not guard**: Every test that requires the test dataset starts with `skip_if_not(dir.exists(test_path("data")))`. This allows tests to run in environments where the test dataset is not available.
- **data.table assertion style**: Use `data.table::setDT()` when reading Arrow Parquet output to ensure data.table type before assertions. Use `data.table::data.table()` (not `data.frame()`) for constructing test fixtures.

---

## Surprises and Deviations

- **Test data date range**: The tickets initially suggested using `janela = c("2020-01-01", "2025-12-31")` as a wide date range. In practice, this caused issues because the test dataset only contains data from July--September 2025. The implementation switched to `janela = list("2025-07-01", "2025-09-30")` throughout. Future tests must use this exact range or a subset of it. The `list()` wrapper (not `c()`) is required by `parse_config()`.

- **Plant IDs in test data are BAUFI1 and BAUFI2**: The ticket examples used placeholder IDs like "U1", "U2", but the actual test dataset at `/home/rogerio/git/mh-pfv/tests/testthat/data/` contains plants BAUFI1 and BAUFI2. The factory functions in `helper-generators.r` use synthetic IDs (USI1, USI2) for unit tests, but integration tests rely on the real test data IDs.

- **parsearg_janela S3 method bug**: The pre-existing bug in `parsearg_janela.character` S3 method registration (missing `S3method()` directive in NAMESPACE) was documented in the coverage baseline but NOT fixed in this epic. It remains as technical debt. The test `test-config-file.r:89` may exhibit this issue.

- **Coverage final result (84.8%) exceeded the 80% target**: The epic target was >= 80% line coverage. The actual result was 84.8%, exceeding the target by nearly 5 percentage points. The main remaining gap is `R/predict.r` at 27.8% coverage (the `processar_usina()` function has complex branching that is partially but not fully covered by integration tests) and `R/zzz.r` at 0% (lifecycle hooks that covr cannot exercise).

- **Snapshot style**: The ticket suggested `expect_snapshot_value(..., style = "json2")` and this was followed exactly. However, the snapshots are stored in a single `.md` file (`_snaps/snapshot-regression.md`) rather than separate JSON files. This is the default testthat v3 behavior for `expect_snapshot_value()` with json2 style.

- **gen_geracao_apply_pattern uses match.call dispatch**: The `helper-generators.r` file implements pattern-based data generation using `match.call()` manipulation rather than simple `switch()` or `if/else`. This is a deliberate design matching the S3 dispatch idiom used elsewhere in the codebase (`gen_geracao_apply_pattern_normal`, `gen_geracao_apply_pattern_frozen`, etc.).

---

## Recommendations for Future Epics

- **Epic 02 (Extensibility Refactor)**: When refactoring `train.r` and `predict.r` to use the strategy pattern, the snapshot tests in `/home/rogerio/git/mh-pfv/tests/testthat/test-snapshot-regression.r` will serve as the primary regression safety net. Run them before and after every refactoring step. If numerical output changes, the snapshot file at `_snaps/snapshot-regression.md` will show the exact diff.

- **Epic 02 (Extensibility Refactor)**: The `processar_usina()` function in `/home/rogerio/git/mh-pfv/R/predict.r` (lines 120-195) is the most complex function in the codebase and the primary refactoring target. It has 10 parameters and calls 8 internal functions sequentially. The unit test at `/home/rogerio/git/mh-pfv/tests/testthat/test-predict.r` covers the happy path but does not cover error paths or edge cases within `processar_usina()`. Epic 02 should add error-path coverage when restructuring this function.

- **Epic 02 (Extensibility Refactor)**: The `get_dataset()` function in `/home/rogerio/git/mh-pfv/R/predict.r` (lines 95-117) is shared between train and predict pipelines. When introducing the strategy pattern, this function should be extracted or parameterized since train and predict load different dataset components. The current tests at `test-predict.r` verify its return structure.

- **Epic 03 (Performance)**: When parallelizing `train_main()` and `predict_main()`, the `lapply` calls on per-plant processing (line 52 of `/home/rogerio/git/mh-pfv/R/predict.r`) are the natural parallelization points. Integration tests already verify correctness for sequential execution. Add a comparison test that asserts parallel results match sequential results.

- **Epic 05 (Infrastructure)**: The CI coverage threshold at 75% in `/home/rogerio/git/mh-pfv/.github/workflows/test-coverage.yaml` should be raised to 80% once coverage stabilizes above 80% for 3+ consecutive PRs. The current coverage (84.8%) provides sufficient headroom.

- **All future epics**: The `helper-generators.r` factory functions produce synthetic data with fixed column schemas. If pfvIO changes its data format (column names, types), the generators must be updated to match. Reference the generators first when writing new tests rather than constructing data inline.

---

## Technical Debt Identified

- **parsearg_janela S3 method registration**: The NAMESPACE file is missing `S3method(parsearg_janela, character)`. This means `parsearg_janela("2025-01-01")` will not dispatch to the character method. Located in `/home/rogerio/git/mh-pfv/NAMESPACE`. The roxygen2 directive in the source file for this method may be missing or incorrect.

- **R/zzz.r is untestable by covr**: The `.onLoad` and `.onUnload` hooks in `/home/rogerio/git/mh-pfv/R/zzz.r` (5 lines) cannot be exercised by covr because they run during package loading before instrumentation. This is an inherent limitation, not a code quality issue. The 5 uncovered lines permanently reduce the theoretical maximum coverage by ~0.8%.

- **predict.r coverage gap (27.8%)**: The `processar_usina()` function has significant uncovered paths, particularly around the `idx_maior` comparison logic (lines 181-187) and the `coloca_na_antes_inicio()` call. The integration test exercises the happy path but not edge cases (e.g., plants with no data in the janela, all-NA irradiance). This should be addressed in Epic 02 when the function is refactored.

- **pfvIO triple-colon calls**: The production code in `/home/rogerio/git/mh-pfv/R/predict.r` uses `pfvIO:::get_model_artifact()` (triple colon, accessing unexported function). This creates a fragile coupling to pfvIO internals. If pfvIO refactors its internal API, this call will break silently.

- **Arrow ZSTD requirement**: Test data Parquet files require Arrow compiled with `ARROW_WITH_ZSTD=ON`. If Arrow is installed without ZSTD support, Parquet reads fail with an opaque compression error. This is not documented anywhere in the test setup instructions.
