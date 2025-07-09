logger_setup <- function() {
    lg <- get_logger()
    lg$set_threshold(nivel_logging)
    layout <- LayoutFormat$new(timestamp_fmt = "%Y-%m-%d %H:%M:%S")
    lg$appenders$console$set_layout(layout)

    lg
}
