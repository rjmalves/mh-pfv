# E01-T004: Resilience Integration Tests

## Objective

Add integration tests verifying that partial plant failures produce correct provenance, artifacts, checkpoints, and health reports in both train and predict pipelines.

## Dependencies

- E01-T002 (train resilience)
- E01-T003 (predict resilience)

## Files to Create/Modify

| File                                        | Action | Details                                                |
| ------------------------------------------- | ------ | ------------------------------------------------------ |
| `tests/testthat/test-integration-train.r`   | Modify | Add test cases for partial failure in train pipeline   |
| `tests/testthat/test-integration-predict.r` | Modify | Add test cases for partial failure in predict pipeline |

## Technical Details

### Strategy for simulating failures

Use `mockery::stub()` to make `ajustar_usina` (train) or `processar_usina` (predict) throw an error for a specific plant ID while succeeding for others:

```r
stub(train_main, "ajustar_usina", function(iu, ...) {
    if (iu == "USI_FAIL") stop("simulated failure")
    # return a valid model artifact for other plants
    gen_model_artifact(id_usina = iu)
})
```

### Test cases for train (`test-integration-train.r`)

1. **Partial failure (1 of 3 plants fails)**
   - Setup: config with 3 plants, stub `ajustar_usina` to fail for plant 2
   - Assert: provenance has plant 1 = "completed", plant 2 = "failed", plant 3 = "completed"
   - Assert: `final_status == "failed"`
   - Assert: artifacts exist for plants 1 and 3, not for plant 2
   - Assert: health report has `overall_health == "failed"` and error entry for plant 2

2. **All plants fail**
   - Setup: config with 2 plants, stub `ajustar_usina` to fail for all
   - Assert: all plants "failed" in provenance
   - Assert: no artifacts written
   - Assert: `final_status == "failed"`

3. **Resume after partial failure**
   - Setup: create a checkpoint with plant 1 = "completed", plant 2 = "pending"
   - Stub `ajustar_usina` to succeed for plant 2
   - Assert: only plant 2 is processed; plant 1 is skipped
   - Assert: `final_status == "completed"`

### Test cases for predict (`test-integration-predict.r`)

1. **Partial failure (1 of 3 plants fails)**
   - Setup: config with 3 plants, stub `processar_usina` to fail for plant 2
   - Assert: provenance has plant 1 = "completed", plant 2 = "failed", plant 3 = "completed"
   - Assert: output files are written with data from plants 1 and 3 only
   - Assert: health report has `overall_health == "failed"`

2. **All plants fail**
   - Setup: config with 2 plants, all fail
   - Assert: no output files written
   - Assert: `final_status == "failed"`

### Test helpers

If `gen_model_artifact()` does not already exist in `helper-generators.r`, verify it does before using. It currently exists (used in `test-model-strategy.r`).

Use `withr::local_tempdir()` for all I/O. Mock `conectamock_pfv`, `get_usinas`, `get_dataset` as done in existing integration tests.

## Acceptance Criteria

- [ ] At least 2 test cases for train partial failure (partial + all-fail)
- [ ] At least 2 test cases for predict partial failure (partial + all-fail)
- [ ] At least 1 test for resume-after-partial-failure
- [ ] All tests pass with `devtools::test()`
- [ ] No regressions in existing tests

## Definition of Done

- Tests added to existing integration test files
- `devtools::test()` passes fully
- `devtools::check()` produces no new warnings

## Estimated Effort

~25 minutes
