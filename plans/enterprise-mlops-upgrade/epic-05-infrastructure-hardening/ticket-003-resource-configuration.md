# E05-T003 Add Resource Configuration via Environment Variables

## Context

### Background

The mhpfv pipeline currently has limited runtime configurability. The `parallel` flag on `train_main()` and `predict_main()` enables parallelism, and `setup_parallel_plan()` in `R/parallel.r` defaults to `availableCores() - 1` workers, but there is no way to override the worker count, toggle parallelism, or pass the `resume` flag without modifying R code. The CLI entry point (`cli_main()` in `R/cli.r`) only accepts `--datadir` and hardcodes `parallel = FALSE`, `resume = FALSE`. The learnings explicitly note: "No `--parallel` or `--resume` CLI flags in `cli_main()`" as known technical debt. The logging level is already configurable via the `LOG_LEVEL` environment variable (read in `R/logging.r`).

### Relation to Epic

This ticket completes Epic 05's resource configuration goal. It enables deployment teams to tune the pipeline for different environments (local dev, CI runners, production Docker containers) without modifying config files or R code. Combined with the optimized Docker image (E05-T001), the environment variables can be set as `ENV` defaults in the Dockerfile or overridden at `docker run` time.

### Current State

**`R/cli.r` -- `cli_main()`** (the entire function):

```r
cli_main <- function(datadir = "./data") {
    lg <- get_pkg_logger()
    conn <- conectamock_pfv(datadir)
    config <- get_config(conn)
    config <- parse_config(config, conn)
    if (config$mode == "train") {
        train_main(config)
    } else if (config$mode == "predict") {
        predict_main(config)
    } else {
        stop(
            "Modo invalido. Apenas os modos 'train' e 'predict'",
            " estao disponiveis para esse modelo."
        )
    }
    invisible(0L)
}
```

Neither `parallel` nor `resume` are passed through. Both `train_main()` and `predict_main()` already accept `parallel = FALSE` and `resume = FALSE` as parameters.

**`R/parser.r` -- `get_parser()`**:

```r
get_parser <- function() {
    parser <- ArgumentParser(description = "Modelo de Consistencia do Melhor Historico de Geracao Solar")
    parser <- inner_parser_generic_args(parser)
    return(parser)
}
inner_parser_generic_args <- function(parser) {
    parser$add_argument("--datadir", type = "character", default = "./data", help = help_msg)
    return(parser)
}
```

Only `--datadir` is supported.

**`R/parallel.r` -- `setup_parallel_plan()`**:

```r
setup_parallel_plan <- function(workers = NULL,
    strategy = c("multisession", "multicore", "sequential")) {
    strategy <- match.arg(strategy)
    validate_workers(workers)
    if (is.null(workers)) {
        workers <- max(1L, future::availableCores() - 1L)
    }
    ...
}
```

The `workers` parameter can be set programmatically but has no external configuration path.

**`R/logging.r` -- `logger_setup()`**:

```r
logger_setup <- function() {
    lg <- get_logger()
    lg$set_threshold(Sys.getenv("LOG_LEVEL", unset = "info"))
    ...
}
```

This is the existing pattern for environment variable configuration.

**`main.r`** (CLI entry point):

```r
parser <- get_parser()
args <- parser$parse_args()
tryCatch({ cli_main(args$datadir) ... })
```

Only passes `datadir` to `cli_main`.

**Dockerfile** (relevant ENV):

```dockerfile
ENV LOG_LEVEL=info
```

## Specification

### Requirements

1. **Add CLI flags** to `R/parser.r`:
   - `--parallel` (flag, store_true, default FALSE): Enables parallel plant processing
   - `--resume` (flag, store_true, default FALSE): Enables checkpoint-based pipeline resume
   - `--workers` (integer, default NULL): Number of parallel workers (NULL = auto-detect via `availableCores() - 1`)

2. **Add environment variable support** with priority: CLI flag > environment variable > default value. Support these environment variables:
   - `MHPFV_PARALLEL` (`true`/`false`, default `false`): Enables parallel processing
   - `MHPFV_RESUME` (`true`/`false`, default `false`): Enables pipeline resume
   - `MHPFV_WORKERS` (positive integer or empty, default empty = auto): Number of workers

3. **Update `cli_main()`** to accept `parallel`, `resume`, and `workers` parameters and pass them through to `train_main()` / `predict_main()`

4. **Update `main.r`** to read the new CLI flags and pass them to `cli_main()`

5. **Update `setup_parallel_plan()`** to read `MHPFV_WORKERS` as a fallback when `workers = NULL` and the environment variable is set

6. **Add default `ENV` declarations** to the Dockerfile for the new environment variables

7. **Add a helper function** `read_env_flag(name, default)` for parsing boolean environment variables (`"true"`/`"false"` strings to logical), following the same pattern as `LOG_LEVEL` in `logging.r`

### Inputs/Props

| Parameter | CLI Flag      | Env Var          | Type            | Default       |
| --------- | ------------- | ---------------- | --------------- | ------------- |
| parallel  | `--parallel`  | `MHPFV_PARALLEL` | logical         | `FALSE`       |
| resume    | `--resume`    | `MHPFV_RESUME`   | logical         | `FALSE`       |
| workers   | `--workers N` | `MHPFV_WORKERS`  | integer or NULL | `NULL` (auto) |

Priority resolution for each parameter: CLI flag (if explicitly set) > environment variable (if non-empty) > hardcoded default.

### Outputs/Behavior

- `cli_main(datadir, parallel, resume, workers)` dispatches to `train_main(config, parallel = parallel, resume = resume)` or `predict_main(config, parallel = parallel, resume = resume)`
- When `parallel = TRUE` and `workers` is non-NULL, `setup_parallel_plan(workers = workers)` is called (either by `train_main`/`predict_main` which already call it, or by passing the workers value through)
- When `MHPFV_WORKERS` is set and `workers` parameter is NULL, `setup_parallel_plan` reads the env var as fallback
- `main.r` correctly parses all flags and passes them to `cli_main()`
- The Dockerfile declares `ENV MHPFV_PARALLEL=false`, `ENV MHPFV_RESUME=false`, `ENV MHPFV_WORKERS=`

### Error Handling

- If `MHPFV_WORKERS` is set to a non-integer or negative value, `validate_workers()` in `R/parallel.r` catches it and raises a clear error message (already exists)
- If `MHPFV_PARALLEL` or `MHPFV_RESUME` are set to values other than `"true"` or `"false"`, `read_env_flag()` logs a warning via `lgr` and falls back to the default
- If `--workers` is provided without `--parallel`, log a warning that workers are ignored when parallel is disabled

## Acceptance Criteria

- [ ] Given `Rscript main.r --datadir ./data --parallel`, when `train_main` is called, then `parallel = TRUE` is passed
- [ ] Given `Rscript main.r --datadir ./data --resume`, when `predict_main` is called, then `resume = TRUE` is passed
- [ ] Given `Rscript main.r --datadir ./data --parallel --workers 4`, when `setup_parallel_plan` is called, then `workers = 4L`
- [ ] Given `MHPFV_PARALLEL=true` in the environment and no `--parallel` flag, when `cli_main` runs, then `parallel = TRUE`
- [ ] Given `MHPFV_PARALLEL=true` in the environment and `--parallel` NOT passed (argparse default FALSE), when the priority resolution runs, then `parallel = TRUE` because env var overrides default but not explicit CLI
- [ ] Given `MHPFV_WORKERS=2` in the environment and no `--workers` flag, when `setup_parallel_plan` is called with `workers = NULL`, then it uses 2 workers
- [ ] Given `MHPFV_PARALLEL=banana` (invalid), when parsed, then a warning is logged and the default `FALSE` is used
- [ ] Given the Dockerfile, when inspected, then it contains `ENV MHPFV_PARALLEL=false`, `ENV MHPFV_RESUME=false`, `ENV MHPFV_WORKERS=`
- [ ] Given `cli_main` called without the new parameters, when it runs, then it behaves identically to current behavior (backward compatible)
- [ ] Given `main.r`, when `Rscript main.r --help` is run, then `--parallel`, `--resume`, and `--workers` appear in the help text

## Implementation Guide

### Suggested Approach

1. **Create `read_env_flag()` helper** in `R/cli.r` (or a new `R/config-env.r` if preferred, but `R/cli.r` is simpler since it is the only consumer):

   ```r
   read_env_flag <- function(name, default = FALSE) {
       val <- Sys.getenv(name, unset = "")
       if (val == "") return(default)
       val_lower <- tolower(trimws(val))
       if (val_lower %in% c("true", "1", "yes")) return(TRUE)
       if (val_lower %in% c("false", "0", "no")) return(FALSE)
       lg <- lgr::get_logger("mhpfv")
       lg$warn(
           "Valor invalido para %s: '%s'. Usando padrao: %s",
           name, val, default
       )
       default
   }

   read_env_integer <- function(name, default = NULL) {
       val <- Sys.getenv(name, unset = "")
       if (val == "") return(default)
       parsed <- suppressWarnings(as.integer(val))
       if (is.na(parsed) || parsed < 1L) {
           lg <- lgr::get_logger("mhpfv")
           lg$warn(
               "Valor invalido para %s: '%s'. Deve ser inteiro positivo. Usando padrao.",
               name, val
           )
           return(default)
       }
       parsed
   }
   ```

2. **Update `R/parser.r`** to add `--parallel`, `--resume`, and `--workers` flags:

   ```r
   inner_parser_generic_args <- function(parser) {
       parser$add_argument("--datadir", type = "character", default = "./data", help = help_msg)
       parser$add_argument("--parallel",
           action = "store_true", default = FALSE,
           help = "Habilita processamento paralelo de usinas"
       )
       parser$add_argument("--resume",
           action = "store_true", default = FALSE,
           help = "Habilita retomada do pipeline a partir do ultimo checkpoint"
       )
       parser$add_argument("--workers",
           type = "integer", default = NULL,
           help = "Numero de workers paralelos (padrao: auto-detect)"
       )
       return(parser)
   }
   ```

3. **Update `R/cli.r` -- `cli_main()`** to accept and resolve the new parameters:

   ```r
   cli_main <- function(datadir = "./data", parallel = NULL, resume = NULL,
       workers = NULL) {
       lg <- get_pkg_logger()

       # Resolve: CLI flag > env var > default
       if (is.null(parallel) || identical(parallel, FALSE)) {
           parallel <- read_env_flag("MHPFV_PARALLEL", FALSE)
       }
       if (is.null(resume) || identical(resume, FALSE)) {
           resume <- read_env_flag("MHPFV_RESUME", FALSE)
       }
       if (is.null(workers)) {
           workers <- read_env_integer("MHPFV_WORKERS", NULL)
       }

       if (!parallel && !is.null(workers)) {
           lg$warn("--workers ignorado quando --parallel nao esta habilitado")
           workers <- NULL
       }

       conn <- conectamock_pfv(datadir)
       config <- get_config(conn)
       config <- parse_config(config, conn)

       if (config$mode == "train") {
           train_main(config, parallel = parallel, resume = resume)
       } else if (config$mode == "predict") {
           predict_main(config, parallel = parallel, resume = resume)
       } else {
           stop(
               "Modo invalido. Apenas os modos 'train' e 'predict'",
               " estao disponiveis para esse modelo."
           )
       }

       invisible(0L)
   }
   ```

   Note: The `workers` parameter needs to reach `setup_parallel_plan()`. Since `train_main` and `predict_main` call `setup_parallel_plan()` without a workers argument, update `setup_parallel_plan()` to read `MHPFV_WORKERS` as a fallback (step 5). This avoids threading `workers` through the entire call chain.

4. **Update `main.r`** to pass the new arguments:

   ```r
   parser <- get_parser()
   args <- parser$parse_args()
   tryCatch({
       cli_main(
           datadir = args$datadir,
           parallel = args$parallel,
           resume = args$resume,
           workers = args$workers
       )
       q(status = 0)
   }, ...)
   ```

5. **Update `R/parallel.r` -- `setup_parallel_plan()`** to read `MHPFV_WORKERS` as fallback:

   ```r
   setup_parallel_plan <- function(workers = NULL,
       strategy = c("multisession", "multicore", "sequential")) {
       strategy <- match.arg(strategy)

       if (is.null(workers)) {
           env_workers <- Sys.getenv("MHPFV_WORKERS", unset = "")
           if (env_workers != "") {
               workers <- suppressWarnings(as.integer(env_workers))
               if (is.na(workers) || workers < 1L) {
                   lgr::get_logger("mhpfv")$warn(
                       "MHPFV_WORKERS invalido: '%s'. Usando auto-detect.", env_workers
                   )
                   workers <- NULL
               }
           }
       }

       validate_workers(workers)

       if (is.null(workers)) {
           workers <- max(1L, future::availableCores() - 1L)
       }
       # ... rest unchanged
   }
   ```

6. **Update Dockerfile** (after E05-T001 multi-stage rewrite, or current Dockerfile) to add ENV defaults:

   ```dockerfile
   ENV LOG_LEVEL=info
   ENV MHPFV_PARALLEL=false
   ENV MHPFV_RESUME=false
   ENV MHPFV_WORKERS=
   ```

### Key Files to Modify

- `/home/rogerio/git/mh-pfv/R/cli.r` -- add `read_env_flag()`, `read_env_integer()`, update `cli_main()` signature and body
- `/home/rogerio/git/mh-pfv/R/parser.r` -- add `--parallel`, `--resume`, `--workers` arguments
- `/home/rogerio/git/mh-pfv/R/parallel.r` -- add `MHPFV_WORKERS` env var fallback in `setup_parallel_plan()`
- `/home/rogerio/git/mh-pfv/main.r` -- pass new args to `cli_main()`
- `/home/rogerio/git/mh-pfv/Dockerfile` -- add ENV declarations
- `/home/rogerio/git/mh-pfv/man/cli_main.Rd` -- regenerate via `devtools::document()` after updating roxygen2

### Patterns to Follow

- Follow the existing `LOG_LEVEL` env var pattern from `R/logging.r` -- `Sys.getenv(name, unset = "")` with a default
- Follow the codebase convention of Portuguese log messages and error messages
- Follow the learnings recommendation: "`strategy` is always the second-to-last named parameter; `parallel` and `resume` come after"
- Use the `lgr::get_logger("mhpfv")` logger for all warnings (consistent with all other modules)
- Helper functions that are not exported should be defined without roxygen `@export` tags, consistent with `validate_workers()` in `R/parallel.r`

### Pitfalls to Avoid

- **argparse `store_true` returns FALSE by default, not NULL** -- so the priority resolution needs to handle `FALSE` from CLI meaning "not explicitly set" vs `FALSE` meaning "explicitly disabled". The cleanest approach: if CLI flag is FALSE AND env var says TRUE, use TRUE. If CLI flag is TRUE, always use TRUE.
- **Do NOT make `workers` a parameter on `train_main`/`predict_main`** -- this would require modifying their signatures. Instead, let `setup_parallel_plan()` read the env var, keeping the pipeline functions unchanged.
- **Do NOT change `cli_main`'s default `datadir = "./data"`** -- this maintains backward compatibility for programmatic callers.
- **Do NOT add memory limit enforcement** -- R does not support hard memory limits natively. `MHPFV_MEMORY_LIMIT` was in the original outline but is not actionable. Skip it.
- **Test data requires specific `janela`** -- integration tests calling `parse_config()` must use `janela = list("2025-07-01", "2025-09-30")` (not `c()`).

## Testing Requirements

### Unit Tests

Add tests in a new file `/home/rogerio/git/mh-pfv/tests/testthat/test-cli.r`:

1. **`read_env_flag()` tests**:
   - Returns default when env var is unset
   - Returns TRUE for `"true"`, `"TRUE"`, `"1"`, `"yes"`
   - Returns FALSE for `"false"`, `"FALSE"`, `"0"`, `"no"`
   - Returns default and warns for invalid values (test via `expect_no_warning` on valid, verify log behavior on invalid)

2. **`read_env_integer()` tests**:
   - Returns default (NULL) when env var is unset
   - Returns correct integer for valid values
   - Returns default and warns for non-integer values
   - Returns default and warns for negative values

3. **`cli_main()` parameter resolution tests** (mock `train_main`/`predict_main` with `mockery::mock()` or use `withr::local_envvar()`):
   - With env vars set, verify they are passed through
   - With explicit parameters, verify they override env vars

Use `withr::local_envvar()` for all environment variable manipulation in tests.

### Integration Tests

- Run `Rscript main.r --help` and verify `--parallel`, `--resume`, `--workers` appear in help output
- Run with `MHPFV_PARALLEL=true` and verify parallel execution (integration test with test data)
- Run `devtools::check()` to verify no regressions

## Dependencies

- **Blocked By**: E03-T001 (parallel infrastructure -- completed)
- **Blocks**: None

## Effort Estimate

**Points**: 2
**Confidence**: High
