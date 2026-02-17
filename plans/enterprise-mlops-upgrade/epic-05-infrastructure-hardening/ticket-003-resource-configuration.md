# E05-T003 Add Resource Configuration via Environment Variables

> **[OUTLINE]** This ticket requires refinement before execution.
> It will be refined with learnings from earlier epics.

## Objective

Add support for configuring runtime resources (number of parallel workers, memory limits, log level) via environment variables. This enables deployment teams to tune the pipeline for different execution environments (local dev, CI, production Docker) without modifying the config file.

## Anticipated Scope

- **Files likely to be modified**: `/home/rogerio/git/mh-pfv/R/parallel.r` (if created in E03-T001), `/home/rogerio/git/mh-pfv/R/logging.r` (already reads LOG_LEVEL), `/home/rogerio/git/mh-pfv/R/cli.r` (environment variable reading), `/home/rogerio/git/mh-pfv/Dockerfile` (default ENV declarations)
- **Key decisions needed**: Which environment variables to support (MHPFV_WORKERS, MHPFV_MEMORY_LIMIT, LOG_LEVEL already exists); whether to add a validation step for environment variable values; priority order (env var > config file > default)
- **Open questions**: Should memory limits be enforced (R doesn't natively support hard memory limits) or just advisory? Does the parallel infrastructure from Epic 3 need worker count configuration at startup?

## Dependencies

- **Blocked By**: E03-T001
- **Blocks**: None

## Effort Estimate

**Points**: 1
**Confidence**: Low (will be re-estimated during refinement)
