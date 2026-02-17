# E05-T002 Enhance CI/CD with Quality Gates and Caching

> **[OUTLINE]** This ticket requires refinement before execution.
> It will be refined with learnings from earlier epics.

## Objective

Enhance the GitHub Actions CI/CD pipeline with comprehensive quality gates (coverage threshold, lint strictness, benchmark regression detection), R dependency caching for faster builds, and parallel job execution. The goal is a CI pipeline that prevents quality and performance regressions while completing in under 10 minutes.

## Anticipated Scope

- **Files likely to be modified**: `/home/rogerio/git/mh-pfv/.github/workflows/R-CMD-check.yaml`, `/home/rogerio/git/mh-pfv/.github/workflows/test-coverage.yaml`, `/home/rogerio/git/mh-pfv/.github/workflows/lint.yaml`, possibly new workflow files for benchmarks
- **Key decisions needed**: Whether to consolidate all checks into a single workflow or keep them separate; R dependency caching strategy (renv cache vs actions/cache); whether benchmark regression detection runs on every PR or only on release branches; required vs optional status checks
- **Open questions**: How to handle CI failures from benchmark variance (flaky performance tests)? Should the benchmark workflow block PR merges? What is the renv cache key strategy?

## Dependencies

- **Blocked By**: E01-T008
- **Blocks**: None

## Effort Estimate

**Points**: 3
**Confidence**: Low (will be re-estimated during refinement)
