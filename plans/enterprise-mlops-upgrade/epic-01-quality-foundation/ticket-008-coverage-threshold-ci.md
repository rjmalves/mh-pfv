# E01-T008 Add Coverage Threshold Enforcement to CI

## Context

### Background

The mhpfv CI pipeline already measures test coverage via Codecov but does not enforce a minimum threshold. After expanding test coverage in E01-T007, we need to prevent coverage regressions by enforcing a minimum threshold in the GitHub Actions workflow. This ensures that future PRs cannot merge if they reduce coverage below the established baseline.

### Relation to Epic

This is the final ticket in the Quality Foundation epic. It depends on E01-T007 (expanded coverage) to ensure the threshold is achievable. It provides the automated guardrail that protects the quality investment made across all earlier tickets.

### Current State

- The file `/home/rogerio/git/mh-pfv/.github/workflows/test-coverage.yaml` runs `covr::package_coverage()` and uploads to Codecov
- No minimum threshold is checked in the workflow
- No `covr::codecov()` or `covr::package_coverage()` threshold argument is used
- Codecov may have its own threshold configuration (via `codecov.yml`), but no such file exists in the repo

## Specification

### Requirements

1. Modify `/home/rogerio/git/mh-pfv/.github/workflows/test-coverage.yaml` to fail the CI job if line coverage falls below 75%
2. Add a `codecov.yml` configuration file at the repo root that sets project-level and patch-level thresholds
3. The threshold should be 75% initially (slightly below the 80% target to allow for measurement variance), with a plan to increase to 80% once coverage stabilizes
4. Document the threshold in the coverage baseline file

### Inputs/Props

- Current coverage workflow at `/home/rogerio/git/mh-pfv/.github/workflows/test-coverage.yaml`
- Coverage measurement results from E01-T001 and E01-T007

### Outputs/Behavior

- CI fails if coverage drops below 75%
- Codecov reports include threshold information in PR comments
- Clear error message when threshold is not met

### Error Handling

- If coverage measurement itself fails (not the threshold check), the workflow step should still fail clearly
- The threshold check should be a separate step from the measurement step for clarity

## Acceptance Criteria

- [ ] Given a PR that reduces coverage below 75%, when CI runs, then the coverage job fails
- [ ] Given a PR that maintains coverage above 75%, when CI runs, then the coverage job passes
- [ ] Given the file `codecov.yml`, when inspected, then it sets `project.default.threshold` and `patch.default.threshold`
- [ ] Given the modified workflow, when the threshold check step runs, then it prints the actual coverage percentage
- [ ] Given `R CMD check`, when run locally, then it passes with no new warnings (this ticket only modifies CI files)

## Implementation Guide

### Suggested Approach

1. **Modify the test-coverage workflow** to add a threshold check step:

Add after the `covr::to_cobertura(cov)` line in the R script step:

```yaml
- name: Test coverage
  run: |
    cov <- covr::package_coverage(
      quiet = FALSE,
      clean = FALSE,
      install_path = file.path(normalizePath(Sys.getenv("RUNNER_TEMP"), winslash = "/"), "package")
    )
    print(cov)
    covr::to_cobertura(cov)

    # Enforce minimum coverage threshold
    pct <- covr::percent_coverage(cov)
    cat(sprintf("Overall coverage: %.1f%%\n", pct))
    if (pct < 75) {
      stop(sprintf("Coverage %.1f%% is below minimum threshold of 75%%", pct))
    }
  shell: Rscript {0}
```

2. **Create `/home/rogerio/git/mh-pfv/codecov.yml`**:

```yaml
coverage:
  status:
    project:
      default:
        target: 75%
        threshold: 2%
    patch:
      default:
        target: 70%
        threshold: 5%

comment:
  layout: "reach,diff,flags,files"
  behavior: default
  require_changes: false
```

3. **Update `tests/coverage-baseline.md`** (if it exists from E01-T001) to document the CI threshold

### Key Files to Modify

- **Modify**: `/home/rogerio/git/mh-pfv/.github/workflows/test-coverage.yaml`
- **Create**: `/home/rogerio/git/mh-pfv/codecov.yml`
- **Modify**: `/home/rogerio/git/mh-pfv/tests/coverage-baseline.md` (add threshold documentation)

### Patterns to Follow

- Keep the threshold check in the same R script step as the coverage measurement (avoid parsing coverage from Cobertura XML)
- Use `covr::percent_coverage()` which returns a single numeric value
- Use `sprintf` for clear error messages

### Pitfalls to Avoid

- Do not set the threshold to exactly 80% initially -- allow 5% margin for measurement variance across platforms
- Do not add the threshold check as a separate workflow job -- it should be in the same job that measures coverage
- The `codecov.yml` file must be at the repo root, not inside `.github/`
- Ensure the `codecov.yml` threshold aligns with the in-workflow threshold (both 75%)

## Testing Requirements

### Unit Tests

None -- this ticket modifies CI configuration only.

### Integration Tests

None.

### E2E Tests

Verify by pushing a test branch and confirming CI behavior.

## Dependencies

- **Blocked By**: E01-T007
- **Blocks**: None

## Effort Estimate

**Points**: 1
**Confidence**: High
