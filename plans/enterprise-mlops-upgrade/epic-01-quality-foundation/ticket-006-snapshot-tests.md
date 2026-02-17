# E01-T006 Add Snapshot Tests for Numerical Regression Detection

## Context

### Background

The mhpfv package produces numerical outputs (model coefficients, consolidated generation time series) that must remain stable across code changes. Snapshot testing captures a "golden" reference output and automatically compares future outputs against it, detecting any unintended numerical drift. This is particularly important before the refactoring in Epic 2, where the model strategy pattern and code restructuring must preserve identical numerical results.

### Relation to Epic

This ticket depends on E01-T004 (train integration test) and E01-T005 (predict integration test), which establish that the pipeline runs correctly. Snapshot tests capture the exact output of those successful runs as the golden reference.

### Current State

- No snapshot tests exist in the project
- testthat v3 supports `expect_snapshot()` and `expect_snapshot_value()` for snapshot testing
- The existing test config uses `mode: "train"` with the 2-plant test dataset
- Model artifacts (RDS) and output Parquet files are the primary outputs to snapshot

## Specification

### Requirements

1. Create `/home/rogerio/git/mh-pfv/tests/testthat/test-snapshot-regression.r` with snapshot tests
2. Snapshot the model artifact structure (coefficients per half-hour slot) for each plant in the test dataset
3. Snapshot the output Parquet data (melhor historico geracao) numerical values
4. Use `testthat::expect_snapshot_value()` with `style = "json2"` for structured data comparison
5. Generate initial snapshot files by running `testthat::snapshot_accept()` once
6. Add snapshot files to version control in `tests/testthat/_snaps/`

### Inputs/Props

- Test dataset at `/home/rogerio/git/mh-pfv/tests/testthat/data/`
- Factory functions from `helper-generators.r`
- Working train and predict pipelines (E01-T004, E01-T005)

### Outputs/Behavior

- Snapshot files stored in `/home/rogerio/git/mh-pfv/tests/testthat/_snaps/snapshot-regression/`
- Tests pass when output matches snapshot exactly (or within a tolerance for floating point)
- Tests fail with an informative diff when numerical output changes

### Error Handling

- Use `tolerance` parameter in snapshot comparison for floating-point values (suggest `1e-10`)
- Skip if test data is missing

## Acceptance Criteria

- [ ] Given a clean test run, when snapshot tests execute for the first time, then snapshot files are created in `tests/testthat/_snaps/`
- [ ] Given snapshot files exist, when the pipeline produces identical output, then all snapshot tests pass
- [ ] Given a hypothetical change to the regression algorithm, when snapshot tests run, then they detect the difference and fail
- [ ] Given the model artifacts, when snapshotted, then the snapshot captures `id_usina`, `parametros$a`, `parametros$b`, and row names
- [ ] Given the predict output, when snapshotted, then the snapshot captures `valor` and `status` columns per plant
- [ ] Given `R CMD check`, when run, then it passes with no new warnings
- [ ] Given snapshot files, when committed to git, then they are tracked in `tests/testthat/_snaps/`

## Implementation Guide

### Suggested Approach

1. Create `/home/rogerio/git/mh-pfv/tests/testthat/test-snapshot-regression.r`
2. For model artifact snapshots:

```r
test_that("train model coefficients match snapshot", {
    skip_if_not(dir.exists(test_path("data")))

    temp_artifact <- withr::local_tempdir()
    conn <- conectamock_pfv(test_path("data"))

    config <- gen_config(mode = "train")
    config$input <- test_path("data")
    config$artifact <- temp_artifact
    config$janela <- c("2020-01-01", "2025-12-31")
    config <- parse_config(config, conn)

    train_main(config)

    # Read and snapshot each artifact
    artifact_files <- sort(list.files(temp_artifact, pattern = "\\.rds$", full.names = TRUE))
    for (f in artifact_files) {
        model <- readRDS(f)
        # Round coefficients to avoid platform-dependent floating point differences
        model[[2]]$a <- round(model[[2]]$a, digits = 8)
        expect_snapshot_value(model, style = "json2", tolerance = 1e-6)
    }
})
```

3. For predict output snapshots:

```r
test_that("predict output matches snapshot", {
    skip_if_not(dir.exists(test_path("data")))

    temp_artifact <- withr::local_tempdir()
    temp_output <- withr::local_tempdir()
    conn <- conectamock_pfv(test_path("data"))

    # Train
    config_train <- gen_config(mode = "train")
    config_train$input <- test_path("data")
    config_train$artifact <- temp_artifact
    config_train$janela <- c("2020-01-01", "2025-12-31")
    config_train <- parse_config(config_train, conn)
    train_main(config_train)

    # Predict
    config_predict <- gen_config(mode = "predict")
    config_predict$input <- test_path("data")
    config_predict$artifact <- temp_artifact
    config_predict$output <- temp_output
    config_predict$janela <- c("2020-01-01", "2025-12-31")
    config_predict <- parse_config(config_predict, conn)
    predict_main(config_predict)

    # Read and snapshot output
    mhg <- as.data.table(arrow::read_parquet(
        file.path(temp_output, "melhor_historico_geracao.parquet")
    ))

    # Snapshot a summary rather than full data (for manageable snapshot size)
    summary_dt <- mhg[, .(
        n_rows = .N,
        n_na = sum(is.na(valor)),
        mean_valor = round(mean(valor, na.rm = TRUE), 6),
        sd_valor = round(sd(valor, na.rm = TRUE), 6),
        min_valor = round(min(valor, na.rm = TRUE), 6),
        max_valor = round(max(valor, na.rm = TRUE), 6)
    ), by = id_usina]

    expect_snapshot_value(as.list(summary_dt), style = "json2", tolerance = 1e-4)
})
```

4. Run the tests once with `testthat::snapshot_accept("snapshot-regression")` to generate initial snapshots
5. Commit the `_snaps/` directory to git

### Key Files to Modify

- **Create**: `/home/rogerio/git/mh-pfv/tests/testthat/test-snapshot-regression.r`
- **Create**: `/home/rogerio/git/mh-pfv/tests/testthat/_snaps/snapshot-regression/` (auto-generated by testthat)

### Patterns to Follow

- Use `expect_snapshot_value()` with `style = "json2"` for structured data (serializable to JSON)
- Use `tolerance` parameter for floating-point comparison
- Round values before snapshotting to avoid platform-specific differences
- Snapshot summaries (aggregates) rather than full datasets to keep snapshot files manageable
- Use fixed date ranges in janela to ensure reproducibility

### Pitfalls to Avoid

- Do NOT snapshot raw POSIXct objects -- they serialize differently across platforms. Convert to character or use summaries.
- Do NOT snapshot the full predict output data.table if it has thousands of rows -- snapshot summaries per plant instead
- Ensure the `janela` date range is wide enough to include the test data but fixed (not rolling)
- The `_snaps/` directory must be committed to git, otherwise CI will always create new snapshots instead of comparing
- If tests are run on different R versions, floating-point results may differ slightly -- use appropriate tolerance

## Testing Requirements

### Unit Tests

Not applicable -- this ticket creates snapshot tests which are a specific test type.

### Integration Tests

The snapshot tests depend on the integration test infrastructure but are a distinct test category.

### E2E Tests

None.

## Dependencies

- **Blocked By**: E01-T004, E01-T005
- **Blocks**: None (but provides safety net for all subsequent epics)

## Effort Estimate

**Points**: 2
**Confidence**: High
