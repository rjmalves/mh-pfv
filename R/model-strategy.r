#' Ajusta Modelo por Estrategia
#'
#' Funcao de despacho que resolve `fit_<strategy>` no namespace do pacote
#' e delega o ajuste. Nao e um generico S3 -- o despacho e por convencao
#' de nome.
#'
#' @param strategy string escalar identificando o tipo de modelo
#'   (e.g. `"linear_regression"`)
#' @param dty data.table com dados de geracao observada (variavel resposta)
#' @param dtx data.table com dados de irradiacao prevista (variavel explicativa)
#' @param dty_bruta data.table com dados de geracao bruta (sem cortes)
#' @param ... argumentos adicionais passados a funcao de ajuste
#'
#' @return objeto com classe propria do modelo (e.g. `"linear_regression_model"`)
#'
#' @seealso [predict_model()], [model_metadata()], [fit_linear_regression()]
#'
#' @export
fit_model <- function(strategy, dty, dtx, dty_bruta, ...) {
    stopifnot(is.character(strategy), length(strategy) == 1L)
    fn_name <- paste0("fit_", strategy)
    ns <- asNamespace("mhpfv")
    fn <- get0(fn_name, envir = ns, mode = "function", inherits = FALSE)
    if (is.null(fn)) {
        stop("fit_model nao implementado para estrategia '", strategy, "'")
    }
    fn(dty = dty, dtx = dtx, dty_bruta = dty_bruta, ...)
}

#' Gera Previsoes Usando Modelo Ajustado
#'
#' Generico S3 que despacha no objeto modelo ajustado. Cada classe de modelo
#' deve implementar seu proprio metodo.
#'
#' @param model objeto modelo ajustado retornado por [fit_model()]
#' @param df_ger_usi data.table com geracao observada da usina
#' @param df_irrad_prev data.table com irradiacao prevista
#' @param lim_dados vetor numerico de comprimento 2 com limites inferior e superior
#' @param ... argumentos adicionais passados ao metodo especializado
#'
#' @return data.table com previsoes, cuja estrutura depende da implementacao
#'
#' @seealso [fit_model()], [model_metadata()]
#'
#' @export
predict_model <- function(model, ...) {
    UseMethod("predict_model")
}

#' @rdname predict_model
#' @export
predict_model.default <- function(model, ...) {
    stop("predict_model nao implementado para modelo de classe '",
        paste(class(model), collapse = "/"), "'")
}

#' Extrai Metadados do Modelo Ajustado
#'
#' Generico S3 que despacha no objeto modelo ajustado. Cada classe de modelo
#' deve implementar seu proprio metodo de metadados.
#'
#' @param model objeto modelo ajustado retornado por [fit_model()]
#' @param ... argumentos adicionais passados ao metodo especializado
#'
#' @return lista com metadados do modelo, cuja estrutura depende da implementacao
#'
#' @seealso [fit_model()], [predict_model()]
#'
#' @export
model_metadata <- function(model, ...) {
    UseMethod("model_metadata")
}

#' @rdname model_metadata
#' @export
model_metadata.default <- function(model, ...) {
    stop("model_metadata nao implementado para modelo de classe '",
        paste(class(model), collapse = "/"), "'")
}
