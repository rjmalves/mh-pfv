#' Constroi Metadados do Artefato de Modelo
#'
#' Combina metadados extraidos da estrategia de modelo com informacoes do
#' pacote e hash da configuracao de treinamento.
#'
#' @param strategy objeto [new_model_strategy()] usado no ajuste
#' @param model modelo ajustado retornado por [fit_model()]
#' @param config lista com a configuracao de treinamento
#'
#' @return lista com metadados completos do artefato:
#' \describe{
#'   \item{`type`}{string com o tipo de modelo}
#'   \item{`n_slots`}{numero de horarios no modelo}
#'   \item{`n_valid_slots`}{numero de horarios com coeficiente valido}
#'   \item{`timestamp`}{momento da extracao (`POSIXct`)}
#'   \item{`package_version`}{versao do pacote `mhpfv`}
#'   \item{`config_hash`}{hash SHA-256 da configuracao normalizada}
#' }
#'
#' @examples
#' s <- linear_regression_strategy()
#' model <- data.frame(a = c(0.1, 0.2), b = c(0, 0), row.names = c("06:00", "06:30"))
#' cfg <- list(janela = c("2025-07-01", "2025-09-30"), ids_usinas = "USI1")
#' meta <- build_artifact_metadata(s, model, cfg)
#'
#' @export
build_artifact_metadata <- function(strategy, model, config) {
    stopifnot(inherits(strategy, "model_strategy"))
    stopifnot(is.list(config))

    meta <- model_metadata(strategy, model)
    meta$package_version <- as.character(utils::packageVersion("mhpfv"))
    meta$config_hash <- digest::digest(
        normalize_config_for_hash(config),
        algo = "sha256"
    )

    meta
}

#' Normaliza Configuracao para Hash Deterministico
#'
#' Seleciona apenas campos relevantes para o treinamento e ordena por nome
#' para garantir hash deterministico independente da ordem de insercao.
#'
#' @param config lista com a configuracao de treinamento
#'
#' @return lista filtrada e ordenada por nome
normalize_config_for_hash <- function(config) {
    relevant_keys <- get_config_hash_keys()
    matching <- intersect(relevant_keys, names(config))
    if (length(matching) == 0L) return(list())
    cfg <- config[matching]
    cfg[order(names(cfg))]
}

get_config_hash_keys <- function() {
    c(
        "janela", "ids_usinas", "ordem_prioridade_fontes",
        "ordem_prioridade_modelosNWP",
        "fator_tolerancia_limite_superior_geracao"
    )
}

#' Constroi Artefato de Modelo Enriquecido
#'
#' Monta o artefato completo de modelo contendo identificador, parametros
#' ajustados e metadados de proveniencia.
#'
#' @param id_usina character escalar, identificador da usina
#' @param parametros resultado do ajuste (ex: `data.frame` de coeficientes)
#' @param strategy objeto [new_model_strategy()]
#' @param config lista com a configuracao de treinamento
#'
#' @return lista com tres elementos:
#' \describe{
#'   \item{`id_usina`}{character com o identificador da usina}
#'   \item{`parametros`}{`data.frame` com os coeficientes do modelo}
#'   \item{`metadata`}{lista retornada por [build_artifact_metadata()]}
#' }
#'
#' @examples
#' s <- linear_regression_strategy()
#' params <- data.frame(a = c(0.1, 0.2), b = c(0, 0), row.names = c("06:00", "06:30"))
#' cfg <- list(janela = c("2025-07-01", "2025-09-30"), ids_usinas = "USI1")
#' artifact <- build_model_artifact("USI1", params, s, cfg)
#'
#' @export
build_model_artifact <- function(id_usina, parametros, strategy, config) {
    metadata <- build_artifact_metadata(strategy, parametros, config)
    list(
        id_usina = id_usina,
        parametros = parametros,
        metadata = metadata
    )
}

#' Valida Artefato de Modelo
#'
#' Verifica a estrutura de um artefato de modelo. Artefatos no formato
#' antigo (sem metadados) sao aceitos com aviso via logger.
#'
#' Todas as falhas sao coletadas antes de levantar uma unica excecao.
#'
#' @param artifact lista, artefato de modelo a ser validado
#'
#' @return `invisible(TRUE)` se o artefato e valido
#'
#' @examples
#' art <- list(
#'     id_usina = "USI1",
#'     parametros = data.frame(a = 0.1, b = 0),
#'     metadata = list(type = "linear_regression")
#' )
#' validate_artifact(art)
#'
#' @export
validate_artifact <- function(artifact) {
    if (!is.list(artifact)) {
        stop("Artefato deve ser uma lista", call. = FALSE)
    }

    errors <- character(0L)

    errors <- check_artifact_id_usina(errors, artifact)
    errors <- check_artifact_parametros(errors, artifact)

    if (length(errors) > 0L) {
        msg <- paste0(
            "Validacao do artefato falhou:\n",
            paste0("- ", errors, collapse = "\n")
        )
        stop(msg, call. = FALSE)
    }

    check_artifact_metadata(artifact)

    invisible(TRUE)
}

check_artifact_id_usina <- function(errors, artifact) {
    if (!"id_usina" %in% names(artifact)) {
        return(c(errors, "Campo obrigatorio ausente: 'id_usina'"))
    }
    if (!is.character(artifact$id_usina) || length(artifact$id_usina) != 1L) {
        return(c(errors, "'id_usina' deve ser character escalar"))
    }
    errors
}

check_artifact_parametros <- function(errors, artifact) {
    if (!"parametros" %in% names(artifact)) {
        return(c(errors, "Campo obrigatorio ausente: 'parametros'"))
    }
    if (!is.data.frame(artifact$parametros)) {
        return(c(errors, "'parametros' deve ser um data.frame"))
    }
    if (!"a" %in% names(artifact$parametros)) {
        return(c(errors, "'parametros' deve conter coluna 'a'"))
    }
    errors
}

check_artifact_metadata <- function(artifact) {
    if (!"metadata" %in% names(artifact)) {
        lg <- lgr::get_logger("mhpfv")
        lg$warn(
            "Artefato para usina '%s' sem metadados (formato antigo)",
            artifact$id_usina
        )
    }
    invisible(NULL)
}
