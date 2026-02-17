# Epic 02: Extensibility Refactor

## Goal

Introduce a pluggable S3-class model strategy pattern and an input data validation framework to the mhpfv package, enabling future model algorithms to be added without modifying existing code. Refactor `train.r` and `predict.r` to use the strategy pattern while maintaining 100% backward compatibility with existing configuration and output formats.

## Scope

1. Design and implement the S3 model strategy interface (`model-strategy.r`)
2. Wrap the existing linear regression algorithm as the first concrete strategy (`linear_regression`)
3. Refactor `train.r` to use the strategy for model fitting
4. Refactor `predict.r` to use the strategy for prediction/imputation
5. Add an input data validation framework for runtime validation of data.tables
6. Ensure all existing tests and snapshot tests continue to pass (numerical equivalence)

## Out of Scope

- Implementing new model types (only wrapping the existing linear regression)
- Changing the artifact storage format (RDS structure stays the same)
- Adding parallelism (Epic 3)
- Modifying pfvIO

## Success Criteria

- All existing unit tests pass unchanged
- All snapshot tests from E01-T006 pass (numerical equivalence proven)
- The model strategy interface is documented with roxygen2
- A developer can add a new model type by implementing 3 S3 methods without touching train.r or predict.r
- Input validation catches malformed data.tables with informative error messages
- `R CMD check` and `lintr` pass with no new warnings

## Tickets

| ID       | Title                                                      | Effort | Dependencies       |
| -------- | ---------------------------------------------------------- | ------ | ------------------ |
| E02-T001 | Design and implement S3 model strategy interface           | Medium | E01-T006           |
| E02-T002 | Wrap existing linear regression as strategy implementation | Medium | E02-T001           |
| E02-T003 | Refactor train.r to use model strategy                     | Medium | E02-T002           |
| E02-T004 | Refactor predict.r to use model strategy                   | Medium | E02-T003           |
| E02-T005 | Add input data validation framework                        | Medium | E01-T002           |
| E02-T006 | Add unit tests for model strategy and validation           | Medium | E02-T004, E02-T005 |

## Estimated Duration

2-3 weeks with 2-3 developers.

## Dependencies on Other Epics

- **Epic 01**: All snapshot tests must pass before and after this refactor (regression safety net)
- **Blocked by**: E01-T006 (snapshot tests provide numerical equivalence verification)

## Risks

- S3 method dispatch overhead may affect performance (mitigated: overhead is negligible for this use case)
- Wrapping existing code in a strategy may introduce subtle bugs (mitigated: snapshot tests catch any numerical difference)
- Over-abstracting may make the code harder to understand (mitigated: keep the interface minimal -- 3 methods only)
