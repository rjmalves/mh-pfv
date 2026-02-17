# E01-T001 Measure Baseline Test Coverage and Identify Gaps

## Context

### Background

The mhpfv package (v0.1.1) has 7 test files in `tests/testthat/` covering config parsing, utilities, data consistency, training, prediction, and missing data imputation. However, the actual line coverage percentage has never been measured or documented. Before increasing coverage, we need a quantified baseline and a gap analysis to guide the subsequent test-writing tickets.

### Relation to Epic

This is the first ticket in the Quality Foundation epic. Its output -- the coverage report and gap analysis -- directly informs E01-T007 (expand unit test coverage) and validates the success of all other tickets in this epic.

### Current State

- 7 test files exist in `/home/rogerio/git/mh-pfv/tests/testthat/`
- CI runs coverage via `covr::package_coverage()` and uploads to Codecov, but no minimum threshold is enforced
- No local documentation of coverage gaps exists
- The `main.r` file (678 lines) is outside the package boundary and is not measured by `covr`

## Specification

### Requirements

1. Run `covr::package_coverage()` locally and capture the per-file and per-function coverage report
2. Generate a coverage summary document listing each R source file, its line coverage percentage, and the specific uncovered lines/functions
3. Identify the top 5 coverage gaps (functions or code paths with lowest coverage)
4. Document findings in a markdown file at `tests/coverage-baseline.md`

### Inputs/Props

- The mhpfv package source at `/home/rogerio/git/mh-pfv/`
- Existing test files in `/home/rogerio/git/mh-pfv/tests/testthat/`
- Test data in `/home/rogerio/git/mh-pfv/tests/testthat/data/`

### Outputs/Behavior

- A markdown file `tests/coverage-baseline.md` containing:
  - Overall package coverage percentage
  - Per-file coverage table (file name, lines total, lines covered, percentage)
  - Per-function coverage for functions below 70% coverage
  - Top 5 gaps with specific line ranges and brief description of what they cover
  - Date of measurement

### Error Handling

- If `covr` cannot be loaded, the ticket documents installation instructions and defers execution
- If test failures are encountered during coverage measurement, document the failures separately -- do not fix them in this ticket

## Acceptance Criteria

- [ ] Given the mhpfv package source, when `covr::package_coverage()` is run, then a coverage report is generated without errors
- [ ] Given the coverage report, when `tests/coverage-baseline.md` is written, then it contains an overall percentage, per-file table, and top 5 gaps
- [ ] Given the baseline document, when a developer reads it, then they can identify which functions and files need additional tests
- [ ] Given `R CMD check`, when run after this ticket, then it passes with no new warnings or errors

## Implementation Guide

### Suggested Approach

1. Open an R session in the project root `/home/rogerio/git/mh-pfv/`
2. Run `covr::package_coverage(quiet = FALSE)` and capture the result object
3. Use `covr::tally_coverage()` to get per-line details
4. Aggregate by file using data.table or base R to compute per-file percentages
5. Use `covr::function_coverage()` or parse the tally to get per-function details
6. Write the markdown report to `tests/coverage-baseline.md`
7. Run `devtools::check()` to confirm nothing is broken

### Key Files to Modify

- **Create**: `/home/rogerio/git/mh-pfv/tests/coverage-baseline.md`
- **Read only**: All files in `/home/rogerio/git/mh-pfv/R/` and `/home/rogerio/git/mh-pfv/tests/testthat/`

### Patterns to Follow

- Use markdown tables (pipe syntax) matching the style in `ARCHITECTURE.md`
- Include the measurement date in ISO 8601 format

### Pitfalls to Avoid

- Do not modify any source code or test code in this ticket
- Do not attempt to fix any test failures found during coverage measurement
- Ensure `covr` is run with `clean = TRUE` to avoid stale compiled objects
- Note that `main.r` is outside the package and will NOT appear in covr output -- document this explicitly as a known gap

## Testing Requirements

### Unit Tests

None -- this ticket produces a documentation artifact, not code.

### Integration Tests

None.

### E2E Tests

None.

## Dependencies

- **Blocked By**: None
- **Blocks**: E01-T007, E01-T008

## Effort Estimate

**Points**: 1
**Confidence**: High
