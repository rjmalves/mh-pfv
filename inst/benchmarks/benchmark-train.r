library(data.table)

benchmark_train <- function(data_dir = NULL) {
    if (is.null(data_dir)) {
        data_dir <- file.path(
            pkgload::pkg_path(), "tests", "testthat", "data"
        )
    }

    stopifnot(dir.exists(data_dir))

    cat("=== Train Pipeline Benchmark ===\n\n")
    cat("Data directory:", data_dir, "\n")

    config <- tryCatch(
        {
            pkgload::load_all(pkgload::pkg_path(), quiet = TRUE)
            conn <- conectamock_pfv(data_dir)
            usinas <- get_usinas(conn)

            gen_config(
                mode = "train",
                input = data_dir,
                artifact = tempdir(),
                janela = list("2025-07-01", "2025-09-30"),
                ids_usinas = usinas$id_usina,
                ordem_prioridade_fontes = list("PI", "CCEE", "CCEE1h"),
                ordem_prioridade_modelosNWP = list("GFS"),
                fator_tolerancia_limite_superior_geracao = 1.1
            )
        },
        error = function(e) {
            cat("ERROR loading data:", conditionMessage(e), "\n")
            cat("This may be caused by arrow/zstd codec issues.\n")
            NULL
        }
    )

    if (is.null(config)) {
        cat("\nSkipping train benchmark (data loading failed).\n")
        return(invisible(NULL))
    }

    config <- parse_config(config, conectamock_pfv(data_dir))
    n_usinas <- length(config$ids_usinas)
    cat("Number of plants:", n_usinas, "\n\n")

    result <- tryCatch(
        {
            bench::mark(
                sequential = train_main(config, parallel = FALSE),
                parallel = train_main(config, parallel = TRUE),
                check = FALSE,
                min_iterations = 3L,
                filter_gc = FALSE
            )
        },
        error = function(e) {
            cat("ERROR during benchmark:", conditionMessage(e), "\n")
            NULL
        }
    )

    if (is.null(result)) {
        cat("\nTrain benchmark could not complete.\n")
        return(invisible(NULL))
    }

    cat("\nResults:\n")
    print(result[, c("expression", "min", "median", "mem_alloc", "n_itr")])
    cat("\nNote: with only", n_usinas, "plants, parallel overhead",
        "may dominate. Speedup scales with plant count.\n")

    invisible(result)
}

if (sys.nframe() == 0L) {
    pkgload::load_all(pkgload::pkg_path(), quiet = TRUE)
    args <- commandArgs(trailingOnly = TRUE)
    data_dir <- if (length(args) > 0L) args[1L] else NULL
    benchmark_train(data_dir)
}
