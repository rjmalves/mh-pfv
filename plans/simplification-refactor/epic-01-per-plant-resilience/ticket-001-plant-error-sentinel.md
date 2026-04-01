# E01-T001: Plant Error Sentinel

## Objective

Create a `plant_error` S3 constructor that wraps per-plant errors into a sentinel object. This sentinel is returned from the `tryCatch` handler inside plant processing loops, allowing the post-processing loop to distinguish success from failure via `inherits(x, "plant_error")`.

## Dependencies

None.

## Files to Create/Modify

| File                               | Action | Details                                                                   |
| ---------------------------------- | ------ | ------------------------------------------------------------------------- |
| `R/provenance.r`                   | Modify | Add `plant_error()` constructor function and `is_plant_error()` predicate |
| `tests/testthat/test-provenance.r` | Modify | Add tests for `plant_error()` and `is_plant_error()`                      |

## Technical Details

### `plant_error()` constructor

Add to `R/provenance.r` (after existing functions):

```r
plant_error <- function(id_usina, error) {
    stopifnot(
        is.character(id_usina), length(id_usina) == 1L,
        inherits(error, "condition") || is.character(error)
    )
    msg <- if (inherits(error, "condition")) conditionMessage(error) else error
    structure(
        list(id_usina = id_usina, error = msg),
        class = "plant_error"
    )
}
```

### `is_plant_error()` predicate

```r
is_plant_error <- function(x) {
    inherits(x, "plant_error")
}
```

### Design choices

- Accept both `condition` objects (from `tryCatch`) and plain character strings (for testing convenience).
- Store the error message as a string, not the condition object itself -- conditions may carry environments that bloat memory if stored in large result lists.
- `plant_error` is not exported -- it is internal to the pipeline logic. Neither is `is_plant_error`.

## Acceptance Criteria

- [ ] `plant_error("USI1", simpleError("boom"))` returns an object of class `"plant_error"` with `$id_usina == "USI1"` and `$error == "boom"`
- [ ] `plant_error("USI1", "boom")` also works (character fallback)
- [ ] `is_plant_error(plant_error("USI1", "x"))` returns `TRUE`
- [ ] `is_plant_error(list(id_usina = "USI1"))` returns `FALSE`
- [ ] Input validation: non-character `id_usina` or vector `id_usina` raises error
- [ ] All new tests pass with `devtools::test(filter = "provenance")`

## Definition of Done

- `plant_error()` and `is_plant_error()` implemented in `R/provenance.r`
- Unit tests added to `tests/testthat/test-provenance.r`
- `devtools::test(filter = "provenance")` passes
- `devtools::check()` produces no new warnings or notes related to these functions

## Estimated Effort

~10 minutes
