#' Ajusta Modelo de Regressao Linear
#'
#' Ajusta regressoes lineares sem intercepto por horario de meia hora entre
#' geracao observada e irradiacao prevista. Retorna objeto com classe
#' `"linear_regression_model"`.
#'
#' @param dty data.table com dados de geracao observada (variavel resposta)
#' @param dtx data.table com dados de irradiacao prevista (variavel explicativa)
#' @param dty_bruta data.table com dados de geracao bruta (sem cortes)
#' @param ... argumentos adicionais (ignorados)
#'
#' @return objeto S3 com classe `"linear_regression_model"` contendo:
#' \describe{
#'   \item{`parametros`}{`data.frame` com coeficientes `a` (angular) e `b`
#'     (sempre zero) indexados por horario `"HH:MM"`}
#' }
#'
#' @seealso [fit_model()], [predict_model.linear_regression_model()],
#'   [model_metadata.linear_regression_model()]
#'
#' @export
fit_linear_regression <- function(dty, dtx, dty_bruta, ...) {
    params <- ajusta_regressao_ger_irrad(dty = dty, dtx = dtx, dty_bruta = dty_bruta)
    structure(
        list(parametros = params),
        class = "linear_regression_model"
    )
}

#' @rdname predict_model
#'
#' @details
#' ## Metodo `linear_regression_model`
#'
#' Delega para [substitui_por_estimativas()], usando `model$parametros`
#' como coeficientes de regressao para preencher valores ausentes na
#' geracao observada.
#'
#' @export
predict_model.linear_regression_model <- function(model, df_ger_usi,
    df_irrad_prev, lim_dados, ...) {
    substitui_por_estimativas(
        df_ger_usi = df_ger_usi,
        df_irrad_prev = df_irrad_prev,
        regressoes = model$parametros,
        lim_dados = lim_dados
    )
}

#' @rdname model_metadata
#'
#' @details
#' ## Metodo `linear_regression_model`
#'
#' Extrai metadados do modelo de regressao linear ajustado. Valida que
#' `model$parametros` e um `data.frame` contendo a coluna `a` (coeficientes
#' angulares).
#'
#' @return Para `linear_regression_model`, lista com:
#' \describe{
#'   \item{`type`}{`"linear_regression"`}
#'   \item{`n_slots`}{numero total de horarios no modelo}
#'   \item{`n_valid_slots`}{numero de horarios com coeficiente `a` nao-`NA`}
#'   \item{`timestamp`}{momento da extracao (`Sys.time()`)}
#' }
#'
#' @export
model_metadata.linear_regression_model <- function(model, ...) {
    params <- model$parametros
    stopifnot(
        is.data.frame(params),
        "a" %in% names(params)
    )

    list(
        type = "linear_regression",
        n_slots = nrow(params),
        n_valid_slots = sum(!is.na(params$a)),
        timestamp = Sys.time()
    )
}
