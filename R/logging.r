
logger_setup <- function() {
    lg <- get_logger()
    lg$set_threshold(Sys.getenv("LOG_LEVEL", unset = "info"))
    layout <- LayoutFormat$new(timestamp_fmt = "%Y-%m-%d %H:%M:%S")
    lg$appenders$console$set_layout(layout)

    lg
}

#' Getter Do Objeto Logger
#' 
#' Funcao auxiliar para acesso do logger do pacote 
#' 
#' @return objeto `Logger` como retornado por `lgr::get_logger()`
#' 
#' @export

get_pkg_logger <- function() {
    get("lg", envir = asNamespace("melhorhistoricosolar"))
}