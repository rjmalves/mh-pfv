# Epic 01: Quality Foundation

## Goal

Establish a comprehensive testing infrastructure and measurable quality baseline for the mhpfv package. This epic is the prerequisite for all subsequent refactoring -- every change in later epics depends on having reliable tests to catch regressions.

## Scope

1. Measure current test coverage and identify gaps
2. Internalize `main.r` into the package boundary (makes it testable and lint-able)
3. Add integration tests for the full train and predict pipelines using the existing 2-plant test dataset
4. Add snapshot tests for numerical regression detection
5. Expand unit test coverage for under-tested internal functions
6. Add a test helper module with synthetic data generators for reuse across tests

## Out of Scope

- Changing any business logic or algorithms
- Adding new features to the pipeline
- Performance optimizations
- Changing the I/O layer or pfvIO

## Success Criteria

- Test coverage >= 80% line coverage as measured by `covr::package_coverage()`
- Integration tests for both `train_main()` and `predict_main()` pass with the test dataset
- Snapshot tests capture current numerical output and detect any regression
- All existing tests continue to pass
- `R CMD check` passes with no new warnings
- `lintr` passes with no new warnings

## Tickets

| ID       | Title                                                    | Effort | Dependencies                 |
| -------- | -------------------------------------------------------- | ------ | ---------------------------- |
| E01-T001 | Measure baseline test coverage and identify gaps         | Small  | None                         |
| E01-T002 | Create test helper module with synthetic data generators | Small  | None                         |
| E01-T003 | Internalize main.r into package as cli.r                 | Medium | None                         |
| E01-T004 | Add integration test for train pipeline                  | Medium | E01-T002, E01-T003           |
| E01-T005 | Add integration test for predict pipeline                | Medium | E01-T002, E01-T003, E01-T004 |
| E01-T006 | Add snapshot tests for numerical regression detection    | Medium | E01-T004, E01-T005           |
| E01-T007 | Expand unit test coverage for under-tested functions     | Medium | E01-T002                     |
| E01-T008 | Add coverage threshold enforcement to CI                 | Small  | E01-T007                     |

## Estimated Duration

2-3 weeks with 2-3 developers working in parallel.

## Dependencies on Other Epics

None. This is the foundation epic.

## Risks

- Test dataset may be too small to exercise all code paths (mitigated by synthetic data generators in E01-T002)
- `main.r` internalization may have subtle differences in how pfvIO connections are established (mitigated by integration tests in E01-T004/T005)
