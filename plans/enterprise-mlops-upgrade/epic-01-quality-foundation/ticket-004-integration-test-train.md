# E01-T004 Add Integration Test for Train Pipeline

## Context

### Background

The mhpfv package has unit tests for individual functions (`ajusta_regressao_ger_irrad`, `consiste_geracao_unit`, etc.) but no integration test that exercises the full `train_main()` pipeline end-to-end. An integration test ensures that the data loading, per-plant processing, consistency checks, regression fitting, and artifact writing all work together correctly. This is critical for catching regressions during the refactoring planned in Epic 2.

### Relation to Epic

This ticket depends on E01-T002 (test helpers) and E01-T003 (internalized CLI). It is a prerequisite for E01-T005 (predict integration test, which needs train artifacts) and E01-T006 (snapshot tests).

### Current State

- `train_main(args)` is exported and tested implicitly through `ajusta_regressao_ger_irrad` unit tests
- The test dataset at `/home/rogerio/git/mh-pfv/tests/testthat/data/` contains 2 plants with all required input files
- The config at `/home/rogerio/git/mh-pfv/tests/testthat/data/config.jsonc` is set to `mode: "train"`
- No test currently calls `train_main()` directly with the full pipeline

## Specification

### Requirements

1. Create `/home/rogerio/git/mh-pfv/tests/testthat/test-integration-train.r` with integration tests for the train pipeline
2. The test must exercise the full train pipeline: config loading -> data loading -> per-plant processing -> artifact generation
3. Tests must use the existing test dataset at `tests/testthat/data/` accessed via `testthat::test_path("data")`
4. Tests must verify that model artifacts are written correctly to a temporary output directory
5. Tests must verify the artifact structure: list with `id_usina` (character) and `parametros` (data.frame with columns `a`, `b` and row.names as "HH:MM" strings)

### Inputs/Props

- Test dataset at `/home/rogerio/git/mh-pfv/tests/testthat/data/`
- Factory functions from `helper-generators.r` (E01-T002) for config generation
- `cli_main()` or `train_main()` from `cli.r` (E01-T003)

### Outputs/Behavior

- Tests pass in under 30 seconds
- Model artifacts are created in a `withr::local_tempdir()` and cleaned up automatically
- All assertions use testthat expectations

### Error Handling

- Tests must handle missing test data gracefully with `skip_if_not(dir.exists(test_path("data")))`
- Temporary directories must be cleaned up even on test failure (use `withr::local_tempdir()`)

## Acceptance Criteria

- [ ] Given the test dataset at `tests/testthat/data/`, when `test-integration-train.r` is run, then all tests pass
- [ ] Given the train pipeline completes, when model artifacts are inspected, then each artifact is a list with elements `id_usina` (character) and `parametros` (data.frame)
- [ ] Given the model parametros data.frame, when inspected, then it has columns `a` and `b`, row.names are "HH:MM" formatted strings between "05:00" and "18:30", and all `b` values are 0
- [ ] Given the model parametros data.frame, when inspected, then `a` values are finite numeric (not NaN, not Inf) where not NA
- [ ] Given the train pipeline completes, when the number of artifacts is counted, then it equals the number of plant IDs in the config
- [ ] Given `R CMD check`, when run, then it passes with no new warnings

## Implementation Guide

### Suggested Approach

1. Create `/home/rogerio/git/mh-pfv/tests/testthat/test-integration-train.r`
2. Write a setup block that:
   - Creates a temporary directory for artifacts using `withr::local_tempdir()`
   - Constructs a config list using `gen_config(mode = "train")` from `helper-generators.r`
   - Sets the config paths: `input = test_path("data")`, `artifact = temp_dir`
   - Creates a pfvIO connection: `conn <- pfvIO::conectamock_pfv(test_path("data"))`
   - Parses the config: `config <- parse_config(config, conn)`

3. Write the following test cases:

```r
test_that("train_main completes without error for test dataset", {
    skip_if_not(dir.exists(test_path("data")))
    temp_artifact <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(mode = "train")
    config$input <- test_path("data")
    config$artifact <- temp_artifact
    config <- parse_config(config, conn)

    expect_no_error(train_main(config))
})

test_that("train_main produces valid model artifacts", {
    skip_if_not(dir.exists(test_path("data")))
    temp_artifact <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(mode = "train")
    config$input <- test_path("data")
    config$artifact <- temp_artifact
    config <- parse_config(config, conn)

    train_main(config)

    # Check artifacts exist
    artifact_files <- list.files(temp_artifact, pattern = "\\.rds$")
    expect_gt(length(artifact_files), 0)
    expect_equal(length(artifact_files), length(config$ids_usinas))

    # Validate artifact structure
    for (f in artifact_files) {
        model <- readRDS(file.path(temp_artifact, f))
        expect_true(is.list(model))
        expect_true(is.character(model[[1]]))
        expect_true(is.data.frame(model[[2]]))
        expect_true("a" %in% names(model[[2]]))
        expect_true("b" %in% names(model[[2]]))
        expect_true(all(model[[2]]$b == 0, na.rm = TRUE))

        # Row names should be HH:MM format
        rn <- rownames(model[[2]])
        expect_true(all(grepl("^\\d{2}:\\d{2}$", rn)))
    }
})
```

4. Note: The artifact writing uses `pfvIO:::write_model_artifact()` which writes to the artifact directory. Verify the exact file naming convention by checking what files are produced.

### Key Files to Modify

- **Create**: `/home/rogerio/git/mh-pfv/tests/testthat/test-integration-train.r`

### Patterns to Follow

- Use `withr::local_tempdir()` for temporary directories (auto-cleanup)
- Use `test_path("data")` for accessing the test dataset
- Use `skip_if_not()` for conditional test execution
- Follow the existing test naming convention: `test_that("function_name does X", { ... })`

### Pitfalls to Avoid

- Do not hardcode paths -- always use `test_path()` and `withr::local_tempdir()`
- The `pfvIO::write_model_artifact()` function is called via `pfvIO:::` (triple colon) in the source code -- the test should not call it directly but verify its side effects
- The config `janela` field needs proper parsing -- use `parse_config()` to ensure it is converted to Date objects
- The config `ids_usinas` field defaults to `list()` which means "all plants" -- `parse_config()` populates it from the connection
- Be aware that `pfvIO::conectamock_pfv()` reads from the filesystem -- the test data directory must have the correct structure

## Testing Requirements

### Unit Tests

Not applicable -- this IS the integration test.

### Integration Tests

This ticket creates the integration tests.

### E2E Tests

None.

## Dependencies

- **Blocked By**: E01-T002, E01-T003
- **Blocks**: E01-T005, E01-T006

## Effort Estimate

**Points**: 2
**Confidence**: High
