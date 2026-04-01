# E02-T004: Environment Adaptation Tests

## Objective

Update all test files that assert on provenance or metrics structure to work with environments instead of lists. Existing assertions using `$` access should mostly work unchanged, but assertions like `is.list(prov)`, `expect_true(is.list(...))`, or copy-on-modify checks need updating.

## Dependencies

- E02-T001 (provenance as environment)
- E02-T002 (metrics as environment)
- E02-T003 (pipeline <<- removal)

## Files to Create/Modify

| File                                        | Action | Details                                                                                                                                                   |
| ------------------------------------------- | ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tests/testthat/test-provenance.r`          | Modify | Update structure assertions from `is.list` to `is.environment`; update `plant_status` assertions to use environment access; add test for `prov_as_list()` |
| `tests/testthat/test-metrics.r`             | Modify | Update structure assertions from `is.list` to `is.environment`; update copy-on-modify test; add test for `metrics_as_list()`                              |
| `tests/testthat/test-pipeline-resume.r`     | Modify | Update any provenance structure assertions                                                                                                                |
| `tests/testthat/test-health-report.r`       | Modify | Update provenance/metrics creation calls if needed                                                                                                        |
| `tests/testthat/test-integration-train.r`   | Modify | Update any inline provenance/metrics assertions                                                                                                           |
| `tests/testthat/test-integration-predict.r` | Modify | Update any inline provenance/metrics assertions                                                                                                           |

## Technical Details

### `test-provenance.r` changes

1. **`create_provenance` tests:**
   - Change `expect_true(is.list(prov$plant_status))` to `expect_true(is.environment(prov$plant_status))`
   - Change `expect_true(all(vapply(prov$plant_status, identity, character(1)) == "pending"))` to iterate using `ls(prov$plant_status)`:
     ```r
     statuses <- vapply(ls(prov$plant_status), function(nm) prov$plant_status[[nm]], character(1L))
     expect_true(all(statuses == "pending"))
     ```
   - Or simpler: `expect_true(all(as.list(prov$plant_status) == "pending"))` (but check unordered)

2. **`update_plant_status` tests:**
   - Change `expect_error(f("not_a_list", ...))` -- this still errors because `is.environment()` check fails on a string
   - Current assertion `prov <- f(prov, "USI1", "completed")` works with environments (reassigning same reference)
   - Add a test verifying in-place mutation: `old_prov <- prov; f(prov, "USI1", "completed"); expect_identical(prov, old_prov)` and `expect_equal(prov$plant_status[["USI1"]], "completed")`

3. **`finalize_provenance` tests:**
   - Change `expect_error(f("not_a_list", ...))` stays valid (string is not environment)
   - `is.list(provenance)` checks in stopifnot become `is.environment(provenance)`

4. **Add `prov_as_list` tests:**

   ```r
   test_that("prov_as_list converts environment to list", {
       cfg <- gen_config(ids_usinas = c("USI1", "USI2"), ...)
       prov <- create_provenance(cfg, "train", FALSE)
       prov_list <- prov_as_list(prov)

       expect_true(is.list(prov_list))
       expect_true(is.list(prov_list$plant_status))
       expect_equal(prov_list$run_id, prov$run_id)
       expect_equal(names(prov_list$plant_status), c("USI1", "USI2"))
   })
   ```

### `test-metrics.r` changes

1. **`create_metrics` tests:**
   - Change `expect_true(is.list(result))` to `expect_true(is.environment(result))`
   - Change `expect_true(is.list(result$plants))` to `expect_true(is.environment(result$plants))`
   - `expect_equal(length(result$plants), 0L)` becomes `expect_equal(length(ls(result$plants)), 0L)`

2. **`record_plant_timing` tests:**
   - Remove the copy-on-modify test: `"record_plant_timing returns updated copy without modifying original"` -- this test explicitly checks that the original is NOT modified, which is the opposite of environment behavior. Replace with:
     ```r
     test_that("record_plant_timing mutates in place", {
         m <- create_metrics("test-run", "train")
         record_plant_timing(m, "USI1", 5.0)
         expect_equal(m$plants[["USI1"]]$duration_seconds, 5.0)
     })
     ```

3. **Other `record_*` tests:**
   - Update `is.list(metrics)` checks to `is.environment(metrics)`
   - `expect_error(f("not-a-list", ...))` stays valid

4. **`finalize_metrics` tests:**
   - `is.list(metrics)` in stopifnot becomes `is.environment(metrics)`

5. **Add `metrics_as_list` test:**

   ```r
   test_that("metrics_as_list converts environment to list", {
       m <- create_metrics("test-run", "train")
       record_plant_timing(m, "USI1", 5.0)
       m_list <- metrics_as_list(m)

       expect_true(is.list(m_list))
       expect_true(is.list(m_list$plants))
       expect_equal(m_list$plants$USI1$duration_seconds, 5.0)
   })
   ```

### `test-pipeline-resume.r` changes

If this file creates provenance via `create_provenance()`, the returned object is now an environment. Any `is.list()` assertions need updating. Review and adapt.

### `test-health-report.r` changes

If provenance is passed to `build_health_report()`, it must now be an environment. Update test setup to use `create_provenance()` (which returns an environment) instead of manual list construction. Check if any test manually constructs a provenance list -- if so, replace with `create_provenance()`.

## Acceptance Criteria

- [ ] All `is.list(provenance)` assertions updated to `is.environment(provenance)` where applicable
- [ ] All `is.list(metrics)` assertions updated to `is.environment(metrics)` where applicable
- [ ] Copy-on-modify test for metrics replaced with in-place mutation test
- [ ] `prov_as_list()` and `metrics_as_list()` have dedicated tests
- [ ] `devtools::test()` passes with zero failures
- [ ] `devtools::check()` passes with no new warnings

## Definition of Done

- All test files updated
- `devtools::test()` passes
- `devtools::check()` passes

## Estimated Effort

~25 minutes
