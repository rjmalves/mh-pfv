#' Construtor de Estrategia de Regressao Linear
#'
#' Cria um objeto `model_strategy` especializado para regressao linear,
#' com classe dupla `c("linear_regression", "model_strategy")`.
#' Os metodos [fit_model()], [predict_model()] e [model_metadata()] delegam
#' para as funcoes existentes [ajusta_regressao_ger_irrad()] e
#' [substitui_por_estimativas()].
#'
#' @param ... parametros adicionais repassados a [new_model_strategy()]
#'
#' @return objeto S3 com classe `c("linear_regression", "model_strategy")`
#'
#' @examples
#' s <- linear_regression_strategy()
#' inherits(s, "linear_regression")
#' inherits(s, "model_strategy")
#'
#' @seealso [new_model_strategy()], [fit_model()], [predict_model()],
#'   [model_metadata()]
#'
#' @export
linear_regression_strategy <- function(...) {
    new_model_strategy("linear_regression", ...)
}

#' @rdname fit_model
#'
#' @details
#' ## Metodo `linear_regression`
#'
#' Delega para [ajusta_regressao_ger_irrad()], ajustando regressoes lineares
#' sem intercepto por horario de meia hora entre geracao observada e
#' irradiacao prevista. O resultado e um `data.frame` com coeficientes
#' `a` (angular) e `b` (sempre zero) indexados por horario `"HH:MM"`.
#'
#' @export
fit_model.linear_regression <- function(strategy, dty, dtx, dty_bruta, ...) {
    ajusta_regressao_ger_irrad(dty = dty, dtx = dtx, dty_bruta = dty_bruta)
}

#' @rdname predict_model
#'
#' @details
#' ## Metodo `linear_regression`
#'
#' Delega para [substitui_por_estimativas()], preenchendo valores ausentes
#' na geracao observada usando irradiacao prevista corrigida pelos
#' coeficientes de regressao do modelo ajustado.
#'
#' O parametro `model` corresponde ao argumento `regressoes` da funcao
#' original.
#'
#' @export
predict_model.linear_regression <- function(strategy, model, df_ger_usi,
    df_irrad_prev, lim_dados, ...) {
    substitui_por_estimativas(
        df_ger_usi = df_ger_usi,
        df_irrad_prev = df_irrad_prev,
        regressoes = model,
        lim_dados = lim_dados
    )
}

#' @rdname model_metadata
#'
#' @details
#' ## Metodo `linear_regression`
#'
#' Extrai metadados do modelo de regressao linear ajustado. Valida que
#' `model` e um `data.frame` contendo a coluna `a` (coeficientes angulares).
#'
#' @return Para `linear_regression`, lista com:
#' \describe{
#'   \item{`type`}{`"linear_regression"`}
#'   \item{`n_slots`}{numero total de horarios no modelo}
#'   \item{`n_valid_slots`}{numero de horarios com coeficiente `a` nao-`NA`}
#'   \item{`mean_coefficient`}{media dos coeficientes `a` validos}
#'   \item{`timestamp`}{momento da extracao (`Sys.time()`)}
#' }
#'
#' @export
model_metadata.linear_regression <- function(strategy, model, ...) {
    stopifnot(
        is.data.frame(model),
        "a" %in% names(model)
    )

    valid_a <- model$a[!is.na(model$a)]

    list(
        type = "linear_regression",
        n_slots = nrow(model),
        n_valid_slots = length(valid_a),
        mean_coefficient = if (length(valid_a) > 0L) mean(valid_a) else NA_real_,
        timestamp = Sys.time()
    )
}
