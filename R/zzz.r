.onLoad <- function(libname, pkgname) {
    lg <- logger_setup()
    assign("lg", lg, asNamespace("mhpfv"))
}

.onUnload <- function(libname, pkgname) {
    ns <- asNamespace("mhpfv")
    if (exists("lg", envir = ns, inherits = FALSE)) {
        try(rm(lg, envir = ns), silent = TRUE)
    }
}

utils::globalVariables(c(
    ".", "a", "chave", "data_hora_observacao", "data_hora_previsao",
    "data_hora_rodada", "distancia", "ger_est", "hora_dec", "hora_min",
    "i.valor", "id_fonte_observacao", "id_modelo_nwp", "id_usina",
    "latitude", "longitude", "data_inicio_operacao_comercial",
    "ordem_prioridade", "passo_prev", "status", "status_dt1", "status_dt2",
    "valor", "valor_dt1", "valor_dt2"
))
