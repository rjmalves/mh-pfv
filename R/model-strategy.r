#' Construtor de Estrategia de Modelo
#'
#' Cria um objeto S3 representando uma estrategia de modelo plugavel para
#' ajuste e previsao. O objeto possui classe dupla `c(type, "model_strategy")`,
#' permitindo dispatch especializado por tipo de modelo.
#'
#' @param type string identificando o tipo de modelo (e.g. `"linear_regression"`)
#' @param ... parametros adicionais armazenados em `params`
#'
#' @return objeto S3 com classe `c(type, "model_strategy")` contendo:
#' \describe{
#'   \item{`type`}{string com o tipo de modelo}
#'   \item{`params`}{lista de parametros adicionais}
#' }
#'
#' @examples
#' s <- new_model_strategy("linear_regression")
#' inherits(s, "model_strategy")
#' s$type
#'
#' @export
new_model_strategy <- function(type, ...) {
    stopifnot(
        is.character(type),
        length(type) == 1L,
        nchar(type) > 0L
    )

    structure(
        list(type = type, params = list(...)),
        class = c(type, "model_strategy")
    )
}

#' Ajusta Modelo Segundo a Estrategia
#'
#' Generico S3 para ajuste de modelo. Cada subclasse de `model_strategy`
#' deve implementar seu proprio metodo de ajuste.
#'
#' @param strategy objeto `model_strategy` definindo o tipo de modelo
#' @param dty data.table com dados de geracao observada (variavel resposta)
#' @param dtx data.table com dados de irradiacao prevista (variavel explicativa)
#' @param dty_bruta data.table com dados de geracao bruta (sem cortes)
#' @param ... argumentos adicionais passados ao metodo especializado
#'
#' @return resultado do ajuste, cuja estrutura depende da implementacao
#'
#' @seealso [new_model_strategy()], [predict_model()], [model_metadata()]
#'
#' @export
fit_model <- function(strategy, dty, dtx, dty_bruta, ...) {
    UseMethod("fit_model")
}

#' @rdname fit_model
#' @export
fit_model.model_strategy <- function(strategy, dty, dtx, dty_bruta, ...) {
    stop("fit_model nao implementado para estrategia '", strategy$type, "'")
}

#' Gera Previsoes Segundo a Estrategia
#'
#' Generico S3 para previsao usando um modelo ajustado. Cada subclasse de
#' `model_strategy` deve implementar seu proprio metodo de previsao.
#'
#' @param strategy objeto `model_strategy` definindo o tipo de modelo
#' @param model modelo ajustado retornado por [fit_model()]
#' @param df_ger_usi data.table com geracao observada da usina
#' @param df_irrad_prev data.table com irradiacao prevista
#' @param lim_dados vetor numerico de comprimento 2 com limites inferior e superior
#' @param ... argumentos adicionais passados ao metodo especializado
#'
#' @return data.table com previsoes, cuja estrutura depende da implementacao
#'
#' @seealso [new_model_strategy()], [fit_model()], [model_metadata()]
#'
#' @export
predict_model <- function(strategy, model, df_ger_usi, df_irrad_prev,
    lim_dados, ...) {
    UseMethod("predict_model")
}

#' @rdname predict_model
#' @export
predict_model.model_strategy <- function(strategy, model, df_ger_usi,
    df_irrad_prev, lim_dados, ...) {
    stop("predict_model nao implementado para estrategia '", strategy$type, "'")
}

#' Extrai Metadados do Modelo Ajustado
#'
#' Generico S3 para extracao de metadados de um modelo ajustado. Cada subclasse
#' de `model_strategy` deve implementar seu proprio metodo de metadados.
#'
#' @param strategy objeto `model_strategy` definindo o tipo de modelo
#' @param model modelo ajustado retornado por [fit_model()]
#' @param ... argumentos adicionais passados ao metodo especializado
#'
#' @return lista com metadados do modelo, cuja estrutura depende da implementacao
#'
#' @seealso [new_model_strategy()], [fit_model()], [predict_model()]
#'
#' @export
model_metadata <- function(strategy, model, ...) {
    UseMethod("model_metadata")
}

#' @rdname model_metadata
#' @export
model_metadata.model_strategy <- function(strategy, model, ...) {
    stop("model_metadata nao implementado para estrategia '", strategy$type, "'")
}
