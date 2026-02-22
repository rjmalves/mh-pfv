# E05-T002 Enhance CI/CD with Quality Gates and Caching

## Context

### Background

The mhpfv package currently has four separate GitHub Actions workflows: `R-CMD-check.yaml` (matrix build on 3 R versions), `test-coverage.yaml` (covr with 75% threshold), `lint.yaml` (lintr with custom `.lintr` config), and `docker.yaml` (build and push on tags/releases). While functional, these workflows have several gaps: no R dependency caching (every run installs from scratch), no benchmark regression detection, inconsistent trigger branches (`main` vs `main,develop`), and the lint workflow manually installs remotes/lintr instead of using `r-lib/actions/setup-r-dependencies`. Epic 03 added benchmarking infrastructure in `inst/benchmarks/` (train, predict, haversine benchmarks using `bench::mark()`), but these benchmarks are never run in CI.

### Relation to Epic

This ticket addresses the CI/CD enhancement goal of Epic 05. It consolidates and hardens the CI pipeline to prevent quality and performance regressions, with a target of completing in under 10 minutes. Combined with the Docker optimization (E05-T001) and resource configuration (E05-T003), this creates a production-ready build/deploy pipeline.

### Current State

**Workflow files in `.github/workflows/`:**

1. **`R-CMD-check.yaml`** (lines 1-54): Runs on push/PR to `main,develop`. Matrix of 3 R versions (`devel`, `release`, `oldrel-1`) on `ubuntu-latest`. Uses `r-lib/actions/setup-r-dependencies@v2` with `needs: check`. No caching beyond what `setup-r-dependencies` provides internally.

2. **`test-coverage.yaml`** (lines 1-76): Runs on push/PR to `main` only (not `develop`). Runs covr with 75% threshold. Uses `r-lib/actions/setup-r-dependencies@v2` with `needs: coverage`. Uploads to Codecov. No caching.

3. **`lint.yaml`** (lines 1-50): Runs on push/PR to `main,develop`. Manually installs `remotes` and `cyclocomp`, then `lintr 3.2.0`. Does NOT use `r-lib/actions/setup-r-dependencies`, so it gets no caching at all and version pinning is fragile.

4. **`docker.yaml`** (lines 1-55): Runs only on version tags (`v*`) and releases. Uses Buildx but no layer caching.

**Benchmarking infrastructure** (`inst/benchmarks/`):

- `benchmark-train.r`: Benchmarks sequential vs parallel train_main using `bench::mark()`
- `benchmark-predict.r`: Same pattern for predict_main
- `benchmark-haversine.r`: Benchmarks cached vs uncached Haversine distance computation

These benchmarks require test data from `tests/testthat/data/` and handle arrow/ZSTD failures gracefully.

**`.lintr` config** (at repo root):

```r
linters: linters_with_defaults(
  line_length_linter(120),
  object_name_linter(c("snake_case", "symbols"), regexes = character()),
  object_usage_linter = NULL,
  indentation_linter(4, "never"),
  return_linter = NULL,
  cyclocomp_linter(complexity_limit = 12L),
  object_length_linter(length = 50)
  )
```

## Specification

### Requirements

1. **Standardize trigger branches**: All workflows must trigger on push to `main` and `develop`, and on PRs targeting `main` and `develop`
2. **Fix lint workflow**: Replace manual package installation with `r-lib/actions/setup-r-dependencies@v2` using `extra-packages: any::lintr, any::cyclocomp` and `needs: lint`
3. **Add R dependency caching**: All workflows already use `r-lib/actions/setup-r-dependencies@v2` which caches internally, but ensure the lint workflow also benefits from this
4. **Add benchmark CI workflow**: Create a new `.github/workflows/benchmark.yaml` that runs the existing benchmarks on PRs to `main` and stores results as artifacts. This workflow should NOT block PR merges (informational only)
5. **Add Docker layer caching**: Update `docker.yaml` to use GitHub Actions cache for Docker layers via `cache-from` and `cache-to` on `docker/build-push-action`
6. **Coverage workflow**: Extend trigger to include `develop` branch (currently only `main`)
7. **Add concurrency groups**: Add `concurrency` config to all workflows to cancel superseded runs on the same branch/PR

### Inputs/Props

- `.github/workflows/R-CMD-check.yaml` -- update triggers, add concurrency
- `.github/workflows/test-coverage.yaml` -- update triggers, add concurrency
- `.github/workflows/lint.yaml` -- rewrite package installation, update triggers, add concurrency
- `.github/workflows/docker.yaml` -- add layer caching
- `.github/workflows/benchmark.yaml` -- new file

### Outputs/Behavior

- All 5 workflow files are syntactically valid GitHub Actions YAML
- All workflows trigger consistently on push/PR to `main` and `develop`
- Lint workflow uses `r-lib/actions/setup-r-dependencies@v2` instead of manual install
- Benchmark workflow runs all three benchmark scripts and uploads results as artifacts
- Docker workflow uses GHA cache for layer caching
- Superseded workflow runs are cancelled automatically

### Error Handling

- Benchmark workflow must NOT fail the overall CI -- use `continue-on-error: true` on the benchmark step or mark the job as non-required
- Benchmark scripts already handle data loading failures (arrow/ZSTD issues) by printing an error and returning NULL
- If codecov upload fails on PRs without `CODECOV_TOKEN`, the existing `fail_ci_if_error` conditional logic handles this

## Acceptance Criteria

- [ ] Given the updated `lint.yaml`, when a PR is opened, then lintr runs using dependencies from `r-lib/actions/setup-r-dependencies@v2` (no manual `install.packages("remotes")`)
- [ ] Given all workflow files, when inspected, then they all have `on: push: branches: [main, develop]` and `on: pull_request: branches: [main, develop]`
- [ ] Given all workflow files, when inspected, then they all have a `concurrency` group that cancels in-progress runs
- [ ] Given the new `benchmark.yaml`, when a PR is opened to `main`, then it runs the three benchmark scripts from `inst/benchmarks/`
- [ ] Given the benchmark workflow, when a benchmark script fails (e.g., arrow/ZSTD), then the workflow does NOT block the PR
- [ ] Given the benchmark workflow, when benchmarks succeed, then the results are uploaded as a GitHub Actions artifact
- [ ] Given the updated `docker.yaml`, when inspected, then it includes `cache-from` and `cache-to` parameters on the build-push-action step
- [ ] Given the `test-coverage.yaml`, when inspected, then it triggers on push/PR to both `main` and `develop`
- [ ] Given the workflow YAML files, when validated with `actionlint` (or similar), then no syntax errors are found

## Implementation Guide

### Suggested Approach

1. **Update `R-CMD-check.yaml`**: Add concurrency group. Triggers already correct.

   ```yaml
   concurrency:
     group: ${{ github.workflow }}-${{ github.head_ref || github.ref }}
     cancel-in-progress: true
   ```

2. **Update `test-coverage.yaml`**: Add `develop` to trigger branches. Add concurrency group. Keep existing 75% threshold logic unchanged.

   ```yaml
   on:
     push:
       branches: [main, develop]
     pull_request:
       branches: [main, develop]
   ```

3. **Rewrite `lint.yaml`**: Replace the manual `Install remotes` + `Install lintr` steps with `r-lib/actions/setup-r-dependencies@v2`:

   ```yaml
   - uses: r-lib/actions/setup-r-dependencies@v2
     with:
       extra-packages: any::lintr, any::cyclocomp
       needs: lint
   ```

   This eliminates the fragile `remotes::install_version("lintr", version = "3.2.0")` call and lets the action handle caching.

4. **Create `benchmark.yaml`**: New workflow:

   ```yaml
   name: Benchmark

   on:
     pull_request:
       branches: [main]

   concurrency:
     group: ${{ github.workflow }}-${{ github.head_ref || github.ref }}
     cancel-in-progress: true

   jobs:
     benchmark:
       runs-on: ubuntu-latest
       continue-on-error: true

       env:
         GITHUB_PAT: ${{ secrets.GITHUB_TOKEN }}

       steps:
         - uses: actions/checkout@v4
         - uses: r-lib/actions/setup-r@v2
           with:
             r-version: "release"
             use-public-rspm: true
         - run: |
             sudo apt-get update
             sudo apt-get install -y libcurl4-openssl-dev libssl-dev libxml2-dev
         - uses: r-lib/actions/setup-r-dependencies@v2
           with:
             extra-packages: any::bench, any::pkgload
             needs: check
         - name: Run benchmarks
           run: |
             results_dir <- file.path(tempdir(), "benchmark-results")
             dir.create(results_dir)

             scripts <- list.files("inst/benchmarks", pattern = "\\.r$", full.names = TRUE)
             for (script in scripts) {
               cat(sprintf("\n=== Running %s ===\n", basename(script)))
               tryCatch(
                 source(script, local = new.env(parent = globalenv())),
                 error = function(e) cat("FAILED:", conditionMessage(e), "\n")
               )
             }
           shell: Rscript {0}
         - name: Upload benchmark results
           if: always()
           uses: actions/upload-artifact@v4
           with:
             name: benchmark-results
             path: inst/benchmarks/
             retention-days: 30
   ```

5. **Update `docker.yaml`**: Add GHA cache to the build-push step:

   ```yaml
   - name: Build and push
     uses: docker/build-push-action@v6
     with:
       push: ${{ github.event_name != 'pull_request' }}
       tags: ${{ steps.meta.outputs.tags }}
       labels: ${{ steps.meta.outputs.labels }}
       cache-from: type=gha
       cache-to: type=gha,mode=max
   ```

### Key Files to Modify

- `/home/rogerio/git/mh-pfv/.github/workflows/R-CMD-check.yaml` -- add concurrency group
- `/home/rogerio/git/mh-pfv/.github/workflows/test-coverage.yaml` -- add `develop` triggers, add concurrency group
- `/home/rogerio/git/mh-pfv/.github/workflows/lint.yaml` -- rewrite to use `setup-r-dependencies`, add concurrency group
- `/home/rogerio/git/mh-pfv/.github/workflows/docker.yaml` -- add GHA layer caching
- `/home/rogerio/git/mh-pfv/.github/workflows/benchmark.yaml` -- new file

### Patterns to Follow

- Use `r-lib/actions/setup-r@v2` and `r-lib/actions/setup-r-dependencies@v2` consistently across all R workflows (these are the standard r-lib GitHub Actions maintained by the R community)
- Use `actions/checkout@v4` and `actions/upload-artifact@v4` (latest major versions)
- Use `docker/build-push-action@v6` with Buildx and GHA cache
- Concurrency groups should use `${{ github.workflow }}-${{ github.head_ref || github.ref }}` to cancel redundant runs per branch

### Pitfalls to Avoid

- **Do NOT make benchmark workflow a required status check** -- benchmark variance can cause flaky failures. Keep it informational only (`continue-on-error: true` on the job).
- **Do NOT remove the `cyclocomp` package from the lint workflow** -- the `.lintr` config uses `cyclocomp_linter(complexity_limit = 12L)` which requires it.
- **Do NOT change the coverage threshold** -- it is set to 75% in `test-coverage.yaml` and this was established in E01-T008.
- **Do NOT consolidate all workflows into a single file** -- separate workflows allow independent status checks and clearer CI feedback per concern.
- **Watch for the `needs:` parameter in `setup-r-dependencies`** -- it must match the workflow purpose (`check`, `coverage`, `lint`) to install only the relevant extra packages.
- **The `docker.yaml` trigger should remain on tags/releases only** -- do not add push/PR triggers as Docker builds are slow and only needed for releases.

## Testing Requirements

### Unit Tests

No R-level tests needed. This ticket modifies only CI workflow files.

### Integration Tests

- Validate all YAML files parse correctly (use `actionlint` locally if available, or `python -c "import yaml; yaml.safe_load(open('file.yaml'))"`)
- Push a branch and open a PR to verify all workflows trigger and complete
- Verify the lint workflow no longer has manual `install.packages("remotes")` steps
- Verify the benchmark workflow runs and uploads artifacts (check Actions tab)
- Verify superseded runs are cancelled when pushing new commits to the same PR

## Dependencies

- **Blocked By**: E01-T008 (coverage threshold CI -- completed)
- **Blocks**: None

## Effort Estimate

**Points**: 2
**Confidence**: High
