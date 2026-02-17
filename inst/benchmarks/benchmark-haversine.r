library(data.table)

benchmark_haversine <- function(n_usinas = 20L, n_days = 7L) {
    pkgload::load_all(pkgload::pkg_path(), quiet = TRUE)

    helpers_path <- file.path(
        pkgload::pkg_path(), "tests", "testthat", "helper-generators.r"
    )
    source(helpers_path, local = TRUE)

    cat("=== Haversine / NWP Association Benchmark ===\n\n")
    cat("Plants:", n_usinas, "\n")
    cat("Days:", n_days, "\n")

    ids <- paste0("USI", seq_len(n_usinas))
    dt_usinas <- gen_usinas(ids = ids)
    datas <- gen_default_datas(n_days = n_days)
    dt_irrad_prev <- gen_irradiancia_prevista(ids = ids, datas = datas)

    n_rows <- nrow(dt_irrad_prev)
    cat("Irradiance rows:", n_rows, "\n\n")

    run_uncached <- function() {
        clear_haversine_cache()
        associa_nwp_usina(dt_usinas, copy(dt_irrad_prev))
    }

    run_cached <- function() {
        associa_nwp_usina(dt_usinas, copy(dt_irrad_prev))
    }

    clear_haversine_cache()
    associa_nwp_usina(dt_usinas, copy(dt_irrad_prev))

    result <- bench::mark(
        uncached = run_uncached(),
        cached = run_cached(),
        check = FALSE,
        min_iterations = 5L,
        filter_gc = FALSE
    )

    cat("Results:\n")
    print(result[, c("expression", "min", "median", "mem_alloc", "n_itr")])

    speedup <- as.numeric(result$median[1]) / as.numeric(result$median[2])
    cat(sprintf("\nCache speedup: %.1fx (median)\n", speedup))
    cat("Note: speedup increases with number of plants",
        "and grid density.\n")

    clear_haversine_cache()

    invisible(result)
}

if (sys.nframe() == 0L) {
    benchmark_haversine()
}
