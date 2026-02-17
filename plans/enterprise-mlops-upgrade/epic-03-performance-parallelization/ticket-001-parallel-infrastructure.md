# E03-T001 Add future/future.apply Dependency and Parallel Infrastructure

> **[OUTLINE]** This ticket requires refinement before execution.
> It will be refined with learnings from earlier epics.

## Objective

Add the `future` and `future.apply` packages as dependencies to the mhpfv package and create a helper module for configuring parallelism (number of workers, plan type). This provides the foundation for parallelizing per-plant processing in subsequent tickets.

## Anticipated Scope

- **Files likely to be modified**: `/home/rogerio/git/mh-pfv/DESCRIPTION` (add Imports), `/home/rogerio/git/mh-pfv/R/mh-pfv.r` (add @import), new file `R/parallel.r` for configuration helpers
- **Key decisions needed**: Whether to use `future::plan(multisession)` vs `future::plan(multicore)` as default; whether parallelism is configurable via config.jsonc or only via R API; how to handle the renv.lock update
- **Open questions**: Does the current renv environment support future/future.apply without conflicts? What is the optimal default worker count for the ONS use case?

## Dependencies

- **Blocked By**: E02-T004
- **Blocks**: E03-T002, E03-T003

## Effort Estimate

**Points**: 1
**Confidence**: Low (will be re-estimated during refinement)
