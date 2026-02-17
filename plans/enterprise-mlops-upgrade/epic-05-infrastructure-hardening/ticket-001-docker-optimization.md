# E05-T001 Optimize Docker Image with Multi-Stage Build

> **[OUTLINE]** This ticket requires refinement before execution.
> It will be refined with learnings from earlier epics.

## Objective

Replace the current single-stage Docker build (based on `rocker/tidyverse:4.5.2`, ~2GB) with a multi-stage build that uses a smaller base image for the final runtime stage. The goal is to reduce the production image size to under 800MB while maintaining all package functionality.

## Anticipated Scope

- **Files likely to be modified**: `/home/rogerio/git/mh-pfv/Dockerfile` (complete rewrite to multi-stage), `.dockerignore` (if needed)
- **Key decisions needed**: Which base image for runtime (rocker/r-ver vs rocker/r-base vs custom); whether to compile R packages from source or use binary CRAN packages; how to handle the new `future` dependency from Epic 3; whether to use `renv` in the build stage or install directly
- **Open questions**: What system libraries are actually required at runtime (vs only at build time)? Is arrow's C++ library the largest contributor to image size? Can we use the RSPM (RStudio Package Manager) for pre-compiled binaries?

## Dependencies

- **Blocked By**: E03-T001
- **Blocks**: None

## Effort Estimate

**Points**: 3
**Confidence**: Low (will be re-estimated during refinement)
