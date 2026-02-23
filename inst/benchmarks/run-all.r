library(data.table)

print_benchmark_summary <- function(results) {
    for (name in names(results)) {
        if (is.null(results[[name]])) {
            cat(sprintf("%-12s: SKIPPED (data unavailable)\n", name))
            next
        }
        res <- results[[name]]
        medians <- vapply(res$median, as.numeric, numeric(1))
        labels <- as.character(res$expression)
        cat(sprintf("%-12s:\n", name))
        for (j in seq_along(labels)) {
            cat(sprintf("  %-15s median = %.3f ms\n",
                    labels[j], medians[j] * 1000))
        }
    }
}

generate_benchmark_report <- function(results) {
    report_lines <- c(
        "mhpfv Performance Benchmark Report",
        paste("Generated:", format(Sys.time())),
        paste("R version:", R.version.string),
        paste("Platform:", Sys.info()[["sysname"]], Sys.info()[["release"]]),
        paste("CPU cores:", parallel::detectCores()),
        ""
    )
    for (name in names(results)) {
        if (is.null(results[[name]])) {
            report_lines <- c(report_lines,
                paste0(name, ": SKIPPED"), "")
            next
        }
        res <- results[[name]]
        medians <- vapply(res$median, as.numeric, numeric(1))
        labels <- as.character(res$expression)
        report_lines <- c(report_lines, paste0(name, ":"))
        for (j in seq_along(labels)) {
            report_lines <- c(report_lines,
                sprintf("  %-15s median = %.3f ms", labels[j],
                    medians[j] * 1000))
        }
        report_lines <- c(report_lines, "")
    }
    report_lines
}

run_all_benchmarks <- function(data_dir = NULL) {
    pkg_root <- pkgload::pkg_path()
    pkgload::load_all(pkg_root, quiet = TRUE)

    bench_dir <- file.path(pkg_root, "inst", "benchmarks")
    timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    output_dir <- file.path(tempdir(), paste0("bench_", timestamp))
    dir.create(output_dir, showWarnings = FALSE)

    cat("============================================\n")
    cat("  mhpfv Performance Benchmarks\n")
    cat("============================================\n\n")
    cat("Timestamp:", format(Sys.time()), "\n")
    cat("R version:", R.version.string, "\n")
    cat("Platform:", Sys.info()[["sysname"]], Sys.info()[["release"]], "\n")
    cat("CPU cores:", parallel::detectCores(), "\n")
    cat("Output:", output_dir, "\n\n")

    results <- list()

    cat("--------------------------------------------\n")
    source(file.path(bench_dir, "benchmark-haversine.r"), local = TRUE)
    results$haversine <- benchmark_haversine()
    cat("\n")

    cat("--------------------------------------------\n")
    source(file.path(bench_dir, "benchmark-train.r"), local = TRUE)
    results$train <- benchmark_train(data_dir)
    cat("\n")

    cat("--------------------------------------------\n")
    source(file.path(bench_dir, "benchmark-predict.r"), local = TRUE)
    results$predict <- benchmark_predict(data_dir)
    cat("\n")

    cat("============================================\n")
    cat("  Summary\n")
    cat("============================================\n\n")

    print_benchmark_summary(results)

    rds_path <- file.path(output_dir, "benchmark_results.rds")
    saveRDS(results, rds_path)
    cat("\nRDS saved to:", rds_path, "\n")

    report_path <- file.path(output_dir, "benchmark_report.txt")
    report_lines <- generate_benchmark_report(results)
    writeLines(report_lines, report_path)
    cat("Report saved to:", report_path, "\n")

    invisible(results)
}

if (sys.nframe() == 0L) {
    args <- commandArgs(trailingOnly = TRUE)
    data_dir <- if (length(args) > 0L) args[1L] else NULL
    run_all_benchmarks(data_dir)
}
