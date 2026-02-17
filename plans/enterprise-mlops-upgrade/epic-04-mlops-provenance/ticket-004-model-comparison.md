# E04-T004 Add Model Comparison Utilities

> **[OUTLINE]** This ticket requires refinement before execution.
> It will be refined with learnings from earlier epics.

## Objective

Create utility functions that compare model artifacts across versions or across plants, reporting differences in coefficients, metadata, and training metrics. This enables operators to understand how model parameters change over time or between runs with different configurations.

## Anticipated Scope

- **Files likely to be modified**: New file `R/model-comparison.r` for comparison utilities, possibly test files for comparison functions
- **Key decisions needed**: Whether comparison output is a data.table (for programmatic use) or a formatted text report (for human reading) or both; which metrics to compare (coefficient-level diff, summary statistics, metadata differences); whether to support visual comparison (plots) or text only
- **Open questions**: What is the expected use case (comparing two specific artifacts, or comparing a new artifact against a "golden" reference)? Should comparison support different model types (e.g., linear_regression vs a future model type)? Is there a threshold for "significant" coefficient change?

## Dependencies

- **Blocked By**: E04-T001
- **Blocks**: None

## Effort Estimate

**Points**: 2
**Confidence**: Low (will be re-estimated during refinement)
