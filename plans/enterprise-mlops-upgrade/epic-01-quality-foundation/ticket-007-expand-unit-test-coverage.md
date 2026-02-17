# E01-T007 Expand Unit Test Coverage for Under-Tested Functions

## Context

### Background

Based on the codebase analysis, several internal functions have limited or no direct unit test coverage. While the integration tests (E01-T004, E01-T005) exercise the full pipeline, targeted unit tests are needed to cover edge cases, error paths, and boundary conditions that are difficult to trigger through integration tests alone. This ticket focuses on closing the coverage gaps identified in E01-T001.

### Relation to Epic

This ticket depends on E01-T002 (test helpers for synthetic data). It is a prerequisite for E01-T008 (coverage threshold enforcement). The coverage baseline from E01-T001 guides which functions need additional tests.

### Current State

Functions with likely coverage gaps based on code analysis:

1. **`get_dataset()` in predict.r** (lines 95-117): No direct tests. Calls 5 pfvIO functions to load data.
2. **`ajustar_usina()` in train.r** (lines 66-117): No direct unit test. Only `ajusta_regressao_ger_irrad()` is tested.
3. **`processar_usina()` in predict.r** (lines 120-195): No direct unit test. Complex function with multiple steps.
4. **`preenche_geracao_unit()` edge cases**: Tested but lacks edge cases (empty cortes with non-NULL value, edge hour boundaries).
5. **`combina_dados()` edge cases**: Tested but lacks cases where all sources are NA for some timestamps.
6. **`logger_setup()` in logging.r**: No test.
7. **`get_pkg_logger()` in logging.r**: No test.
8. **`get_parser()` in parser.r**: No test.
9. **`inner_parser_generic_args()` in parser.r**: No test.
10. **`write_melhor_historico_geracao()` in escrita.r**: No direct test.
11. **`write_melhor_historico_geracao_sem_cortes()` in escrita.r**: No direct test.
12. **`cli_main()` in cli.r** (created in E01-T003): Minimal smoke test only.

## Specification

### Requirements

1. Add unit tests for all functions listed above that do not have direct tests
2. Each function must have at least one "happy path" test and one "error/edge case" test
3. Tests must use synthetic data from `helper-generators.r` where applicable
4. Target: achieve >= 80% line coverage across the package after this ticket

### Inputs/Props

- Factory functions from `helper-generators.r` (E01-T002)
- Coverage baseline from `tests/coverage-baseline.md` (E01-T001)
- Existing test files in `/home/rogerio/git/mh-pfv/tests/testthat/`

### Outputs/Behavior

- New test cases added to existing test files (not new files, to keep the test structure clean)
- Exception: `test-logging.r`, `test-parser.r`, `test-escrita.r`, `test-cli.r` may be new files if they do not already exist
- All tests pass within existing test infrastructure

### Error Handling

- Tests for error paths must use `expect_error()` with a pattern matching the expected error message
- Tests must be isolated (no side effects between tests)

## Acceptance Criteria

- [ ] Given `get_dataset()`, when called with valid args and conn, then it returns a named list with 5 elements (ger_obs, corte, irrad_prev, mhg, mhg_sem_cortes)
- [ ] Given `ajustar_usina()`, when called with valid inputs for a single plant, then it returns a list with `id_usina` and `parametros`
- [ ] Given `processar_usina()`, when called with valid inputs and a model artifact, then it returns a list with `com_cortes` and `sem_cortes` data.tables
- [ ] Given `logger_setup()`, when called, then it returns an lgr Logger object with threshold set from LOG_LEVEL env var
- [ ] Given `get_pkg_logger()`, when called after package load, then it returns the same Logger object
- [ ] Given `get_parser()`, when called, then it returns an ArgumentParser object with `--datadir` argument
- [ ] Given `write_melhor_historico_geracao()`, when called with a valid data.table and temp directory, then a Parquet file is written
- [ ] Given `cli_main()`, when called with an invalid mode in config, then it raises an error containing "Modo invalido"
- [ ] Given the overall package, when coverage is measured after this ticket, then line coverage is >= 80%
- [ ] Given `R CMD check`, when run, then it passes with no new warnings

## Implementation Guide

### Suggested Approach

Add tests organized by source file:

**1. Tests for `logging.r`** -- Create `/home/rogerio/git/mh-pfv/tests/testthat/test-logging.r`:

```r
test_that("logger_setup returns a Logger", {
    lg <- logger_setup()
    expect_true(inherits(lg, "Logger"))
})

test_that("get_pkg_logger returns the package logger", {
    lg <- get_pkg_logger()
    expect_true(inherits(lg, "Logger"))
})

test_that("LOG_LEVEL environment variable controls threshold", {
    withr::local_envvar(LOG_LEVEL = "debug")
    lg <- logger_setup()
    expect_equal(lg$threshold, lgr::get_log_levels()["debug"])
})
```

**2. Tests for `parser.r`** -- Create `/home/rogerio/git/mh-pfv/tests/testthat/test-parser-expanded.r`:

```r
test_that("get_parser returns ArgumentParser", {
    parser <- get_parser()
    expect_true(inherits(parser, "ArgumentParser"))
})

test_that("parser has --datadir argument with default", {
    parser <- get_parser()
    args <- parser$parse_args(c())
    expect_equal(args$datadir, "./data")
})

test_that("parser accepts custom --datadir", {
    parser <- get_parser()
    args <- parser$parse_args(c("--datadir", "/tmp/test"))
    expect_equal(args$datadir, "/tmp/test")
})
```

**3. Tests for `escrita.r`** -- Create `/home/rogerio/git/mh-pfv/tests/testthat/test-escrita.r`:

```r
test_that("write_melhor_historico_geracao writes parquet file", {
    skip_if_not(dir.exists(test_path("data")))
    temp_dir <- withr::local_tempdir()

    # Create a valid data.table matching expected schema
    dt <- data.table(
        id_fonte_observacao = "Consis",
        id_usina = "U1",
        data_hora_observacao = seq(
            as.POSIXct("2025-01-01 00:00:00", tz = "UTC"),
            by = "30 min", length.out = 48
        ),
        valor = runif(48, 0, 10),
        status = rep(1L, 48)
    )

    # This may fail if pfvIO validation rejects the schema -- adjust columns as needed
    # based on pfvIO:::guess_col_names("melhor_historico_geracao")
    expect_no_error(write_melhor_historico_geracao(dt, temp_dir))
    expect_true(file.exists(file.path(temp_dir, "melhor_historico_geracao.parquet")))
})
```

**4. Tests for `predict.r` internal functions** -- Add to `/home/rogerio/git/mh-pfv/tests/testthat/test-predict.r`:

```r
test_that("get_dataset returns named list with all components", {
    skip_if_not(dir.exists(test_path("data")))
    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(mode = "predict")
    config$input <- test_path("data")
    config$janela <- c("2020-01-01", "2025-12-31")
    config <- parse_config(config, conn)

    dataset <- get_dataset(config, conn)
    expect_true(is.list(dataset))
    expect_named(dataset, c("ger_obs", "corte", "irrad_prev", "mhg", "mhg_sem_cortes"))
})
```

**5. Tests for `cli.r` error paths** -- Add to `/home/rogerio/git/mh-pfv/tests/testthat/test-cli.r`:

```r
test_that("cli_main errors on nonexistent datadir", {
    expect_error(cli_main(datadir = "/nonexistent/path/abc123"))
})
```

### Key Files to Modify

- **Create**: `/home/rogerio/git/mh-pfv/tests/testthat/test-logging.r`
- **Create**: `/home/rogerio/git/mh-pfv/tests/testthat/test-parser-expanded.r`
- **Create**: `/home/rogerio/git/mh-pfv/tests/testthat/test-escrita.r`
- **Modify**: `/home/rogerio/git/mh-pfv/tests/testthat/test-predict.r` (add `get_dataset` test)
- **Modify**: `/home/rogerio/git/mh-pfv/tests/testthat/test-cli.r` (add error path tests, created in E01-T003)

### Patterns to Follow

- Follow existing test structure: one `test_that()` block per behavior
- Use `expect_no_error()` for happy path, `expect_error()` for error paths
- Use `withr::local_tempdir()` and `withr::local_envvar()` for test isolation
- Use the factory functions from `helper-generators.r` for test data

### Pitfalls to Avoid

- The `escrita.r` write functions use `pfvIO:::` internal functions for validation -- the test data must match the exact schema pfvIO expects. If tests fail on schema validation, inspect `pfvIO:::guess_col_names()` and `pfvIO:::guess_col_types()` to understand the required format.
- The `get_dataset()` function requires a pfvIO connection -- use `conectamock_pfv(test_path("data"))` to create it
- Do not mock pfvIO functions unless absolutely necessary -- the point is integration correctness
- When testing `processar_usina()`, a model artifact must exist in the artifact directory for the plant being tested

## Testing Requirements

### Unit Tests

This ticket IS about writing unit tests. All tests described above are the deliverable.

### Integration Tests

Already covered by E01-T004 and E01-T005.

### E2E Tests

None.

## Dependencies

- **Blocked By**: E01-T002
- **Blocks**: E01-T008

## Effort Estimate

**Points**: 3
**Confidence**: High
