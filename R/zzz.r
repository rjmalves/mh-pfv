.onLoad <- function(libname, pkgname) {
    lg <- logger_setup()
    assign("lg", lg, asNamespace("melhorhistoricosolar"))
}

.onUnload <- function(libname, pkgname) {
    ns <- asNamespace("melhorhistoricosolar")
    if (exists("lg", envir = ns, inherits = FALSE)) {
        try(rm(lg, envir = ns), silent = TRUE)
    }
}
