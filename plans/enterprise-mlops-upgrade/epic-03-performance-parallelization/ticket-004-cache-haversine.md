# E03-T004 Cache Haversine Distance Computations

> **[OUTLINE]** This ticket requires refinement before execution.
> It will be refined with learnings from earlier epics.

## Objective

Add memoization/caching to the Haversine distance computation in `associa_nwp_usina()` (utils.r). Currently, the function recomputes distances between every plant and every NWP grid point on every call, even though the plant coordinates and NWP grid points do not change between calls. Caching the distance matrix eliminates this redundant computation.

## Anticipated Scope

- **Files likely to be modified**: `/home/rogerio/git/mh-pfv/R/utils.r` (refactor `associa_nwp_usina` to cache results), possibly a new `R/cache.r` module for generic caching utilities
- **Key decisions needed**: Whether to use package-level environment caching (e.g., a private environment in the package namespace) or a session-level cache; cache invalidation strategy (when do coordinates change?); whether to vectorize the Haversine computation instead of looping
- **Open questions**: How large is the NWP coordinate grid in production (this determines cache benefit)? Is the distance matrix small enough to keep in memory? Should the distance computation be vectorized using data.table operations instead of a for loop?

## Dependencies

- **Blocked By**: E02-T004
- **Blocks**: None

## Effort Estimate

**Points**: 2
**Confidence**: Low (will be re-estimated during refinement)
