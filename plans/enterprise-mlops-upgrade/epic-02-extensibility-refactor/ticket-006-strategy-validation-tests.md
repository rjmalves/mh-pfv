# E02-T006 Add Unit Tests for Model Strategy and Validation

## Context

### Background

After the model strategy refactoring (E02-T001 through E02-T004) and the validation framework (E02-T005), comprehensive tests are needed to verify the full strategy lifecycle, the interaction between strategy and pipeline, and the validation framework edge cases. This ticket ensures the Epic 2 deliverables are thoroughly tested before moving to Epic 3.

### Relation to Epic

This is the final ticket in the Extensibility Refactor epic. It depends on E02-T004 (predict refactor) and E02-T005 (validation framework). It verifies all Epic 2 work is correct and complete.

### Current State

- Basic strategy tests exist from E02-T001 and E02-T002
- Basic validation tests exist from E02-T005
- No tests verify the full strategy-to-pipeline integration
- No tests verify strategy extensibility (implementing a mock strategy)

## Specification

### Requirements

1. Add a mock model strategy (`test_strategy`) that returns deterministic values, to prove the strategy pattern is truly pluggable
2. Test the full lifecycle: create strategy -> fit_model -> artifact -> predict_model
3. Test that train_main and predict_main work with a custom strategy
4. Test validation framework with all 5 schemas using both valid and invalid data
5. Test that validation error messages are informative and list all failures
6. Verify that snapshot tests still pass after all Epic 2 changes

### Inputs/Props

- Factory functions from `helper-generators.r`
- Strategy interface from `model-strategy.r`
- Validation framework from `validation.r`

### Outputs/Behavior

- All new tests pass
- All existing tests pass (no regressions)
- All snapshot tests pass (numerical equivalence)

### Error Handling

- Mock strategy should handle edge cases (empty data, all-NA values)

## Acceptance Criteria

- [ ] Given a mock strategy implementation, when `fit_model()` is called, then S3 dispatch routes to the mock method
- [ ] Given a mock strategy, when used with `train_main()`, then training completes (proving pluggability)
- [ ] Given each of the 5 validation schemas, when tested with valid data, then validation passes
- [ ] Given each of the 5 validation schemas, when tested with missing columns, then an informative error is raised
- [ ] Given a data.table with multiple validation failures, when validated, then all failures are listed in the error message
- [ ] Given all snapshot tests, when run after Epic 2, then they pass
- [ ] Given `R CMD check`, when run, then it passes with no warnings

## Implementation Guide

### Suggested Approach

1. Create a mock strategy in the test file (not in the package):

```r
# In tests/testthat/test-strategy-integration.r

# Mock strategy for testing pluggability
fit_model.test_strategy <- function(strategy, dty, dtx, dty_bruta, ...) {
    # Return a fixed coefficient data.frame
    horas <- seq(5.0, 18.5, by = 0.5)
    nomes <- sprintf("%02d:%02d", floor(horas), ifelse(horas %% 1 == 0.5, 30, 0))
    data.frame(a = rep(0.5, length(horas)), b = rep(0, length(horas)), row.names = nomes)
}

predict_model.test_strategy <- function(strategy, model, df_ger_usi, df_irrad_prev, lim_dados, ...) {
    # Delegate to the standard implementation (proves the interface works)
    substitui_por_estimativas(df_ger_usi, df_irrad_prev, model, lim_dados)
}

model_metadata.test_strategy <- function(strategy, model, ...) {
    list(type = "test_strategy", n_slots = nrow(model), timestamp = Sys.time())
}
```

2. Write strategy lifecycle tests:

```r
test_that("custom strategy can be used with train_main", {
    skip_if_not(dir.exists(test_path("data")))
    temp_artifact <- withr::local_tempdir()
    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(mode = "train")
    config$input <- test_path("data")
    config$artifact <- temp_artifact
    config <- parse_config(config, conn)

    strategy <- new_model_strategy("test_strategy")
    expect_no_error(train_main(config, strategy = strategy))

    # Verify mock strategy's fixed coefficients
    artifacts <- list.files(temp_artifact, pattern = "\\.rds$", full.names = TRUE)
    model <- readRDS(artifacts[1])
    expect_true(all(model[[2]]$a == 0.5))
})
```

3. Write comprehensive validation tests:

```r
test_that("validate_input catches multiple errors", {
    dt <- data.table(wrong_col = 1, another_wrong = "x")
    err <- expect_error(validate_input(dt, "geracao_observada"))
    expect_true(grepl("id_usina", err$message))
    expect_true(grepl("data_hora_observacao", err$message))
    expect_true(grepl("valor", err$message))
})
```

4. Run full test suite and snapshot tests

### Key Files to Modify

- **Create**: `/home/rogerio/git/mh-pfv/tests/testthat/test-strategy-integration.r`
- **Modify**: `/home/rogerio/git/mh-pfv/tests/testthat/test-validation.r` (add comprehensive edge cases)

### Patterns to Follow

- Define mock S3 methods in the test file (not in the package)
- Use the test dataset for integration-level strategy tests
- Test both positive (validation passes) and negative (validation fails) paths

### Pitfalls to Avoid

- The mock S3 methods must be defined BEFORE they are used in `test_that()` blocks
- The mock `fit_model.test_strategy` must return a data.frame with the correct structure (a, b columns, HH:MM row names) because the artifact writing and predict pipeline depend on this format
- Clean up any globally registered S3 methods after tests (use `withr::defer()` if needed)

## Testing Requirements

### Unit Tests

This ticket IS about writing comprehensive tests.

### Integration Tests

The strategy integration tests verify end-to-end behavior.

### E2E Tests

None.

## Dependencies

- **Blocked By**: E02-T004, E02-T005
- **Blocks**: None

## Effort Estimate

**Points**: 3
**Confidence**: High
