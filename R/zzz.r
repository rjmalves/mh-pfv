
.onLoad <- function(libname, pkgname) {
    lg <- logger_setup()
    assign("lg", lg, asNamespace("melhorhistoricosolar"))
}

.onUnload <- function(libname, pkgname) {
    rm(lg, envir = asNamespace("melhorhistoricosolar"))
}