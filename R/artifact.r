#' Constroi Artefato de Modelo Enriquecido
#'
#' Monta o artefato completo de modelo contendo identificador, modelo ajustado
#' com classe e metadados de proveniencia.
#'
#' @param id_usina character escalar, identificador da usina
#' @param model objeto modelo ajustado retornado por [fit_model()], com classe
#'   propria (e.g. `"linear_regression_model"`)
#' @param config lista com a configuracao de treinamento
#'
#' @return lista com tres elementos:
#' \describe{
#'   \item{`id_usina`}{character com o identificador da usina}
#'   \item{`model`}{objeto modelo com classe S3 preservada}
#'   \item{`metadata`}{lista com metadados do modelo, versao do pacote e hash}
#' }
#'
#' @examples
#' model <- fit_linear_regression(
#'     dty = data.table::data.table(id_usina = "U1",
#'         data_hora_observacao = Sys.time(), valor = 1),
#'     dtx = data.table::data.table(id_usina = "U1",
#'         data_hora_previsao = Sys.time(), valor = 1),
#'     dty_bruta = data.table::data.table(id_usina = "U1",
#'         data_hora_observacao = Sys.time(), valor = 1)
#' )
#' cfg <- list(janela = c("2025-07-01", "2025-09-30"), ids_usinas = "USI1")
#' artifact <- build_model_artifact("USI1", model, cfg)
#'
#' @export
build_model_artifact <- function(id_usina, model, config) {
    metadata <- model_metadata(model)
    metadata$package_version <- as.character(utils::packageVersion("mhpfv"))
    metadata$config_hash <- digest::digest(
        normalize_config_for_hash(config),
        algo = "sha256"
    )
    list(
        id_usina = id_usina,
        model = model,
        metadata = metadata
    )
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

#' Valida Artefato de Modelo
#'
#' Verifica a estrutura de um artefato de modelo. Artefatos sem metadados
#' sao aceitos com aviso via logger.
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
#'     model = structure(list(parametros = data.frame(a = 0.1, b = 0)),
#'         class = "linear_regression_model"),
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
    errors <- check_artifact_model(errors, artifact)

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

check_artifact_model <- function(errors, artifact) {
    if (!"model" %in% names(artifact)) {
        return(c(errors, "Campo obrigatorio ausente: 'model'"))
    }
    if (!is.list(artifact$model)) {
        return(c(errors, "'model' deve ser uma lista com classe S3"))
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
