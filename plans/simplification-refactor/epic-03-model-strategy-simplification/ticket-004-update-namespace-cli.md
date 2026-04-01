# E03-T004: Update NAMESPACE + cli.r

## Objective

Update roxygen2 tags across all modified files to produce the correct NAMESPACE entries, and simplify `cli.r` to remove any dependency on the deleted `linear_regression_strategy()`.

## Dependencies

- E03-T003 (artifact + pipeline updates -- all source files now use new API)

## Files to Modify

| File                          | Action                                                                  |
| ----------------------------- | ----------------------------------------------------------------------- |
| `R/model-strategy.r`          | Verify roxygen tags produce correct exports (no S3method for fit_model) |
| `R/model-linear-regression.r` | Verify roxygen tags register new S3methods                              |
| `R/artifact.r`                | Remove `@export` from deleted `build_artifact_metadata`                 |
| `R/cli.r`                     | Remove any `linear_regression_strategy()` usage if present              |
| `NAMESPACE`                   | Regenerate via `devtools::document()`                                   |

## Detailed Implementation

### 1. Verify roxygen2 tags in `R/model-strategy.r`

After E03-T001, `R/model-strategy.r` should have:

- `fit_model`: `@export` (regular function, not S3 generic -- produces `export(fit_model)`)
- `predict_model`: `@export` (S3 generic -- produces `export(predict_model)`)
- `predict_model.default`: `@export` (produces `S3method(predict_model,default)`)
- `model_metadata`: `@export` (S3 generic -- produces `export(model_metadata)`)
- `model_metadata.default`: `@export` (produces `S3method(model_metadata,default)`)

Verify no stale roxygen tags reference `model_strategy`, `new_model_strategy`, or old method signatures.

### 2. Verify roxygen2 tags in `R/model-linear-regression.r`

After E03-T002, `R/model-linear-regression.r` should have:

- `fit_linear_regression`: `@export` (produces `export(fit_linear_regression)`)
- `predict_model.linear_regression_model`: `@export` (produces `S3method(predict_model,linear_regression_model)`)
- `model_metadata.linear_regression_model`: `@export` (produces `S3method(model_metadata,linear_regression_model)`)

Verify no stale roxygen tags reference `linear_regression_strategy`, `fit_model.linear_regression`, `predict_model.linear_regression`, or `model_metadata.linear_regression`.

### 3. Verify roxygen2 tags in `R/artifact.r`

After E03-T003:

- `build_artifact_metadata` is deleted -- ensure no orphaned roxygen block remains
- `build_model_artifact`: `@export` with updated parameter docs
- `validate_artifact`: `@export` unchanged
- Internal helpers (`normalize_config_for_hash`, `get_config_hash_keys`, `check_artifact_*`): no `@export`

### 4. Update `R/cli.r`

Current `cli.r` code (lines 126-128):

```r
if (config$mode == "train") {
    train_main(config, parallel = parallel, resume = resume)
} else if (config$mode == "predict") {
    predict_main(config, parallel = parallel, resume = resume)
}
```

Check for any `linear_regression_strategy()` call or `strategy` variable assignment. Current code does NOT explicitly create a strategy -- it relies on the default parameter in `train_main` and `predict_main`. Since `train_main` now defaults to `strategy = "linear_regression"` (string) and `predict_main` has no `strategy` parameter, no change should be needed in the function body.

However, verify:

- Roxygen `@seealso` does not reference `[linear_regression_strategy()]`
- No stale imports or references to `new_model_strategy`

### 5. Regenerate NAMESPACE

Run `devtools::document()` to regenerate NAMESPACE from roxygen2 tags.

Expected NAMESPACE changes:

**Remove:**

```
S3method(fit_model,linear_regression)
S3method(fit_model,model_strategy)
S3method(model_metadata,linear_regression)
S3method(model_metadata,model_strategy)
S3method(predict_model,linear_regression)
S3method(predict_model,model_strategy)
export(build_artifact_metadata)
export(linear_regression_strategy)
export(new_model_strategy)
```

**Add:**

```
S3method(predict_model,linear_regression_model)
S3method(predict_model,default)
S3method(model_metadata,linear_regression_model)
S3method(model_metadata,default)
export(fit_linear_regression)
```

**Keep unchanged:**

```
export(build_model_artifact)
export(cli_main)
export(fit_model)
export(model_metadata)
export(predict_model)
export(validate_artifact)
```

(Plus all other existing exports unrelated to model strategy.)

### 6. Verify NAMESPACE correctness

After regeneration, verify:

1. No references to `model_strategy`, `linear_regression` (old class), `new_model_strategy`, `linear_regression_strategy`, or `build_artifact_metadata`
2. `fit_model` is exported as `export(fit_model)` (NOT as S3method)
3. `predict_model` and `model_metadata` are exported as both `export()` and have S3method registrations for `linear_regression_model` and `default`
4. `fit_linear_regression` is exported
5. All other existing exports are preserved

## Acceptance Criteria

1. `NAMESPACE` is regenerated via `devtools::document()` and contains no stale entries
2. Old S3 method registrations removed: `fit_model.linear_regression`, `fit_model.model_strategy`, `predict_model.linear_regression`, `predict_model.model_strategy`, `model_metadata.linear_regression`, `model_metadata.model_strategy`
3. Old exports removed: `new_model_strategy`, `linear_regression_strategy`, `build_artifact_metadata`
4. New S3 method registrations present: `predict_model.linear_regression_model`, `predict_model.default`, `model_metadata.linear_regression_model`, `model_metadata.default`
5. New exports present: `fit_linear_regression`
6. `fit_model` is exported as a regular function (not S3 generic)
7. `cli.r` has no references to `linear_regression_strategy()` or `model_strategy`
8. `devtools::document()` runs without errors or warnings

## Scope Boundaries

- Do NOT modify function implementations (those were done in E03-T001/T002/T003)
- Do NOT modify test files (that is E03-T005)
- Do NOT manually edit NAMESPACE -- use `devtools::document()` only
- If `devtools::document()` produces unexpected output, report the discrepancy rather than manually fixing NAMESPACE

## Technical Notes

- `fit_model` as a regular (non-generic) function with `@export` will produce `export(fit_model)` in NAMESPACE. roxygen2 only generates `S3method()` entries for functions whose names match the `generic.class` pattern or that use `UseMethod()`. Since `fit_model` no longer calls `UseMethod()`, roxygen2 will correctly treat it as a plain export.
- If roxygen2 caches stale method registrations, a clean document pass (`devtools::document(clean = TRUE)` or deleting `man/` first) may be needed.
