# E01-T005 Add Integration Test for Predict Pipeline

## Context

### Background

The predict pipeline (`predict_main()`) is the primary production codepath for mhpfv. It loads trained model artifacts, applies data consistency checks, fills missing data using regression estimates, and writes the final "melhor historico" output in Parquet format. No integration test currently exercises this full pipeline. This test is critical for regression detection, especially before the refactoring in Epic 2.

### Relation to Epic

This ticket depends on E01-T002 (test helpers), E01-T003 (internalized CLI), and E01-T004 (train integration test -- the predict pipeline needs model artifacts produced by training). It is a prerequisite for E01-T006 (snapshot tests).

### Current State

- `predict_main(args)` is exported but only tested indirectly through its internal functions
- `test-predict.r` tests `organiza_resultados()` in isolation
- `test-preenchimento-dados-faltantes.r` tests `preenche_geracao_unit()`, `substitui_por_estimativas()`, `zera_horarios_extremos()`, and `aplica_cortes_em_geracao()` in isolation
- The predict pipeline requires model artifacts to exist (produced by `train_main()`)
- Output is written via `write_melhor_historico_geracao()` and `write_melhor_historico_geracao_sem_cortes()` which call pfvIO functions

## Specification

### Requirements

1. Create `/home/rogerio/git/mh-pfv/tests/testthat/test-integration-predict.r` with integration tests for the predict pipeline
2. The test must first run `train_main()` to produce model artifacts, then run `predict_main()` to exercise the full predict pipeline
3. Tests must verify that output Parquet files are written correctly
4. Tests must verify output data structure: data.table with columns `id_fonte_observacao`, `id_usina`, `data_hora_observacao`, `valor`, `status`
5. Tests must verify basic data integrity: no Inf values, values within physical limits, correct plant IDs

### Inputs/Props

- Test dataset at `/home/rogerio/git/mh-pfv/tests/testthat/data/`
- Factory functions from `helper-generators.r` (E01-T002)
- `cli_main()` from `cli.r` (E01-T003)
- Model artifacts produced by `train_main()` in the test setup phase

### Outputs/Behavior

- Tests pass in under 60 seconds (includes train + predict)
- All temporary files are cleaned up automatically
- Output Parquet files are validated for structure and basic data integrity

### Error Handling

- Skip tests if test data directory is missing
- Use `withr::local_tempdir()` for all temporary output
- Ensure cleanup even on test failure

## Acceptance Criteria

- [ ] Given the test dataset and trained model artifacts, when `predict_main()` is called, then it completes without error
- [ ] Given the predict pipeline completes, when the output directory is inspected, then it contains `melhor_historico_geracao.parquet` and `melhor_historico_geracao_sem_cortes.parquet`
- [ ] Given the output Parquet files, when read with `arrow::read_parquet()`, then they are valid data.tables with columns `id_fonte_observacao`, `id_usina`, `data_hora_observacao`, `valor`, `status`
- [ ] Given the output data, when inspected, then all `valor` entries are either NA or finite numeric (no NaN, no Inf)
- [ ] Given the output data, when plant IDs are extracted, then they match the plant IDs from the config
- [ ] Given the output data, when the `id_fonte_observacao` column is inspected, then all non-NA values are `"Consis"`
- [ ] Given `R CMD check`, when run, then it passes with no new warnings

## Implementation Guide

### Suggested Approach

1. Create `/home/rogerio/git/mh-pfv/tests/testthat/test-integration-predict.r`
2. Write a shared setup that runs train first, then predict:

```r
test_that("predict_main completes without error after training", {
    skip_if_not(dir.exists(test_path("data")))

    temp_artifact <- withr::local_tempdir()
    temp_output <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))

    # Phase 1: Train to produce artifacts
    config_train <- gen_config(mode = "train")
    config_train$input <- test_path("data")
    config_train$artifact <- temp_artifact
    config_train <- parse_config(config_train, conn)
    train_main(config_train)

    # Phase 2: Predict using those artifacts
    config_predict <- gen_config(mode = "predict")
    config_predict$input <- test_path("data")
    config_predict$artifact <- temp_artifact
    config_predict$output <- temp_output
    config_predict <- parse_config(config_predict, conn)

    expect_no_error(predict_main(config_predict))
})

test_that("predict_main produces valid output files", {
    skip_if_not(dir.exists(test_path("data")))

    temp_artifact <- withr::local_tempdir()
    temp_output <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))

    # Train
    config_train <- gen_config(mode = "train")
    config_train$input <- test_path("data")
    config_train$artifact <- temp_artifact
    config_train <- parse_config(config_train, conn)
    train_main(config_train)

    # Predict
    config_predict <- gen_config(mode = "predict")
    config_predict$input <- test_path("data")
    config_predict$artifact <- temp_artifact
    config_predict$output <- temp_output
    config_predict <- parse_config(config_predict, conn)
    predict_main(config_predict)

    # Verify output files exist
    output_files <- list.files(temp_output, pattern = "\\.parquet$")
    expect_true("melhor_historico_geracao.parquet" %in% output_files)
    expect_true("melhor_historico_geracao_sem_cortes.parquet" %in% output_files)

    # Verify structure of output
    mhg <- arrow::read_parquet(file.path(temp_output, "melhor_historico_geracao.parquet"))
    mhg <- as.data.table(mhg)

    expected_cols <- c("id_fonte_observacao", "id_usina", "data_hora_observacao", "valor", "status")
    expect_true(all(expected_cols %in% names(mhg)))

    # Verify data integrity
    expect_true(all(is.finite(mhg$valor) | is.na(mhg$valor)))
    expect_true(all(mhg$id_fonte_observacao == "Consis" | is.na(mhg$id_fonte_observacao)))
    expect_true(all(mhg$id_usina %in% config_predict$ids_usinas))
})
```

3. Consider extracting the train+predict setup into a local helper function within the test file to reduce duplication

### Key Files to Modify

- **Create**: `/home/rogerio/git/mh-pfv/tests/testthat/test-integration-predict.r`

### Patterns to Follow

- Use `withr::local_tempdir()` for all temporary directories
- Use `test_path("data")` for the test dataset
- Use `arrow::read_parquet()` to read output files (matching production code)
- Follow existing test naming convention

### Pitfalls to Avoid

- The predict pipeline calls `pfvIO:::get_model_artifact(iu, artifact_dir)` with the triple-colon operator -- model artifacts must be in the expected location and format
- The `write_melhor_historico_geracao()` function calls `pfvIO:::valida_dado_singular_completo()` which validates column names and types -- if the output schema does not match, the write will fail
- The predict config needs `output` set to the temp directory, whereas the train config needs `artifact`
- The `janela` field in the config determines the date range -- the test dataset's date range must overlap with the parsed janela
- Consider using a fixed date-range janela (e.g., `c("2020-01-01", "2025-12-31")`) instead of the rolling 90-day default to ensure the test data is always within range

## Testing Requirements

### Unit Tests

Not applicable -- this IS the integration test.

### Integration Tests

This ticket creates the integration tests.

### E2E Tests

None.

## Dependencies

- **Blocked By**: E01-T002, E01-T003, E01-T004
- **Blocks**: E01-T006

## Effort Estimate

**Points**: 3
**Confidence**: High
