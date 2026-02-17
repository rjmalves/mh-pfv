# E01-T003 Internalize main.r into Package as cli.r

## Context

### Background

The file `main.r` (678 lines) at `/home/rogerio/git/mh-pfv/main.r` is the CLI entry point for the mhpfv package. It currently sits outside the package boundary, which means it is not covered by `covr`, not checked by `lintr`, not included in `R CMD check`, and cannot be unit-tested through the standard package testing infrastructure. Internalizing it as an exported function within the package is a prerequisite for comprehensive testing and for later refactoring in Epic 2.

**Important**: Examining `main.r` reveals it is actually only 28 lines (not 678 as initially estimated). The file loads libraries, parses arguments, loads config, and dispatches to `train_main()` or `predict_main()` with error handling. This is a straightforward internalization.

### Relation to Epic

This ticket is a prerequisite for E01-T004 (integration test for train) and E01-T005 (integration test for predict), which need to call the full pipeline programmatically from tests. It also enables coverage measurement of the entry point logic.

### Current State

The current `main.r` at `/home/rogerio/git/mh-pfv/main.r` contains:

```r
suppressPackageStartupMessages(library(pfvIO))
suppressPackageStartupMessages(library(mhpfv))

lg <- get_pkg_logger()
parser <- get_parser()
args <- parser$parse_args()

conn <- conectamock_pfv(args$datadir)
config <- get_config(conn)
config <- parse_config(config, conn)

tryCatch(
    {
        if (config$mode == "train") {
            train_main(config)
        } else if (config$mode == "predict") {
            predict_main(config)
        } else {
            stop("Modo invalido. ...")
        }
        q(status = 0)
    },
    error = function(e) {
        lg$error(e)
        q(status = 1)
    }
)
```

Key observations:

- Uses `pfvIO::conectamock_pfv()` and `pfvIO::get_config()`
- Uses `q(status = ...)` for process exit
- No return value -- side effects only

## Specification

### Requirements

1. Create a new file `/home/rogerio/git/mh-pfv/R/cli.r` containing an exported function `cli_main(datadir = "./data")` that encapsulates the logic currently in `main.r`
2. The function must NOT call `q()` -- it must return an exit code (0 for success, 1 for error) or raise an error
3. Create a thin wrapper script to replace `main.r` that calls `mhpfv::cli_main()` and handles process exit
4. The new `main.r` must be a minimal shim (< 10 lines) that calls `cli_main()` and exits
5. Add roxygen2 documentation for `cli_main()`
6. Update `NAMESPACE` by running `devtools::document()`
7. Maintain full backward compatibility: `Rscript main.r --datadir ./data` must work identically

### Inputs/Props

- `datadir`: Character string, path to data directory (default `"./data"`)

### Outputs/Behavior

- `cli_main(datadir)` returns `0L` on success, or throws an error with an informative message on failure
- All logging, file I/O, and mode dispatching behavior is identical to the current `main.r`
- The Dockerfile `ENTRYPOINT ["Rscript", "main.r"]` continues to work unchanged

### Error Handling

- Invalid mode: `stop("Modo invalido. Apenas os modos 'train' e 'predict' estao disponiveis para esse modelo.")`
- Any error in train/predict: Logged via `lg$error(e)` and then re-raised (not swallowed)
- Connection failure: Let pfvIO error propagate naturally

## Acceptance Criteria

- [ ] Given the file `/home/rogerio/git/mh-pfv/R/cli.r` exists, when `devtools::document()` is run, then `cli_main` appears in `NAMESPACE` as an export
- [ ] Given `cli_main(datadir = test_path("data"))` is called in a test with mode "train", when the function runs, then it returns `0L` without calling `q()`
- [ ] Given the new `main.r` shim, when `Rscript main.r --datadir ./data` is run with a valid dataset, then it behaves identically to the previous `main.r`
- [ ] Given the Dockerfile, when built and run, then the entrypoint `Rscript main.r` works unchanged
- [ ] Given `R CMD check`, when run, then it passes with no new warnings
- [ ] Given `lintr::lint_package()`, when run, then no lint errors are reported for `R/cli.r`
- [ ] Given `man/cli_main.Rd`, when checked, then roxygen2 documentation is complete

## Implementation Guide

### Suggested Approach

1. Create `/home/rogerio/git/mh-pfv/R/cli.r` with the following structure:

```r
#' Funcao Principal de Linha de Comando
#'
#' Ponto de entrada principal do pacote mhpfv. Carrega configuracao,
#' valida parametros e despacha para o modo de execucao adequado
#' (treinamento ou previsao).
#'
#' @param datadir caminho para o diretorio de dados de entrada
#'
#' @return `0L` em caso de sucesso; levanta erro em caso de falha
#'
#' @export
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
        stop("Modo invalido. Apenas os modos 'train' e 'predict' estao disponiveis para esse modelo.")
    }

    invisible(0L)
}
```

2. Replace `/home/rogerio/git/mh-pfv/main.r` with a minimal shim:

```r
suppressPackageStartupMessages(library(mhpfv))

parser <- get_parser()
args <- parser$parse_args()

tryCatch(
    {
        cli_main(args$datadir)
        q(status = 0)
    },
    error = function(e) {
        lg <- get_pkg_logger()
        lg$error(e)
        q(status = 1)
    }
)
```

3. Run `devtools::document()` to regenerate NAMESPACE and man pages
4. Run `devtools::check()` to verify
5. Run `lintr::lint_package()` to verify

### Key Files to Modify

- **Create**: `/home/rogerio/git/mh-pfv/R/cli.r`
- **Modify**: `/home/rogerio/git/mh-pfv/main.r` (replace with minimal shim)
- **Auto-generated**: `/home/rogerio/git/mh-pfv/NAMESPACE` (via devtools::document)
- **Auto-generated**: `/home/rogerio/git/mh-pfv/man/cli_main.Rd` (via devtools::document)

### Patterns to Follow

- Follow the same roxygen2 documentation style as `train_main()` and `predict_main()` in the existing codebase
- Use `invisible(0L)` for the success return (matching R convention for side-effect functions)
- Keep the error message in Portuguese, matching the existing message in `main.r`
- The `pfvIO` library import is handled by the package-level `@import pfvIO` in `/home/rogerio/git/mh-pfv/R/mh-pfv.r`, so `cli.r` does not need `library(pfvIO)`

### Pitfalls to Avoid

- Do NOT call `q()` from within `cli_main()` -- this would kill the R process during testing
- Do NOT add `library()` calls inside `R/cli.r` -- the package imports handle this
- Do NOT remove the `suppressPackageStartupMessages(library(pfvIO))` from the shim `main.r` -- it was there before, but since `cli_main` is now an exported function from mhpfv and mhpfv imports pfvIO, the shim only needs `library(mhpfv)`. The pfvIO import is handled transitively.
- Ensure the shim `main.r` does NOT call `library(pfvIO)` separately since mhpfv already imports it via NAMESPACE
- Run `devtools::document()` BEFORE `devtools::check()` to ensure NAMESPACE is up to date

## Testing Requirements

### Unit Tests

Add a minimal test in `/home/rogerio/git/mh-pfv/tests/testthat/test-cli.r`:

```r
test_that("cli_main returns 0 on success with train mode", {
    # This is a smoke test; full integration tests come in E01-T004/T005
    # Skip if test data doesn't support full pipeline execution
    skip_if_not(dir.exists(test_path("data")))
    # The test data config is set to mode "train"
    result <- cli_main(datadir = test_path("data"))
    expect_equal(result, 0L)
})

test_that("cli_main errors on invalid datadir", {
    expect_error(cli_main(datadir = "/nonexistent/path"))
})
```

### Integration Tests

Deferred to E01-T004 and E01-T005.

### E2E Tests

None.

## Dependencies

- **Blocked By**: None
- **Blocks**: E01-T004, E01-T005

## Effort Estimate

**Points**: 2
**Confidence**: High
