# Suppress lgr logging during test runs to keep output clean
Sys.setenv(LOG_LEVEL = "off")
lgr::get_logger("mhpfv")$set_threshold("off")
lgr::get_logger("mhpfv")$set_propagate(FALSE)

# Helper: skip tests requiring arrow zstd codec (mock data uses zstd parquet)
skip_if_no_zstd <- function() {
    available <- tryCatch(
        arrow::codec_is_available("zstd"),
        error = function(e) FALSE
    )
    testthat::skip_if_not(available, "arrow not compiled with zstd support")
}
