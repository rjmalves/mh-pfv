# Epic 05: Infrastructure Hardening

## Goal

Optimize the Docker image for production deployment, enhance CI/CD with quality gates and build caching, and add resource configuration for batch execution environments.

## Scope

1. Docker multi-stage build to reduce image size (from ~2GB to < 800MB)
2. CI/CD pipeline enhancement with benchmark regression detection
3. Resource configuration (memory limits, worker count) via environment variables
4. Dependency pinning and reproducibility improvements

## Out of Scope

- AWS-specific infrastructure (ECS task definitions, Lambda -- belongs in pfvIO/deployment repo)
- Kubernetes manifests
- Monitoring infrastructure (Epic 6)

## Success Criteria

- Docker image size < 800MB
- CI pipeline includes coverage threshold, lint, R-CMD-check, and benchmark comparison
- Resource limits are configurable via environment variables
- Build time reduced through caching

## Tickets

| ID       | Title                                                | Effort | Dependencies |
| -------- | ---------------------------------------------------- | ------ | ------------ |
| E05-T001 | Optimize Docker image with multi-stage build         | Medium | E03-T001     |
| E05-T002 | Enhance CI/CD with quality gates and caching         | Medium | E01-T008     |
| E05-T003 | Add resource configuration via environment variables | Small  | E03-T001     |

## Estimated Duration

1-2 weeks with 1-2 developers.

## Dependencies on Other Epics

- **Epic 01**: Coverage threshold CI (E01-T008) must be in place
- **Epic 03**: Parallel infrastructure determines Docker dependencies
