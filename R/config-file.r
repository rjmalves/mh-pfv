#' Interpreta Arquivo De Configuracao
#'
#' @param config lista nomeada de
#' @param conn objeto de conexao com um banco
#'
#' @return lista de argumentos interpretados
#'
#' @export
parse_config <- function(config, conn) {
    valida_nomes_config(config)
    valida_tipos_config(config)
    config <- resolve_config_paths(config, attr(conn, "uri"))
    config$janela <- parsearg_janela(unlist(config$janela))
    config$ids_usinas <- parsearg_ids_usinas(config$ids_usinas, conn)
    config$ordem_prioridade_fontes <- unlist(config$ordem_prioridade_fontes)
    return(config)
}

# RESOLUCAO DE CAMINHOS ---------------------------------------------------------------------------

#' Resolve Caminhos Relativos no Config
#'
#' Normaliza `input`, `output` e `artifact` em relacao ao diretorio do config.
#' Caminhos absolutos sao mantidos; caminhos relativos sao resolvidos a partir
#' de `base_dir`. Diretorios de saida (`output`, `artifact`) sao criados se nao
#' existirem. Erro se `input` nao existir.
#'
#' @param config lista de configuracoes
#' @param base_dir diretorio base para resolver caminhos relativos (tipicamente
#'     o diretorio contendo o config.json)
#'
#' @return `config` com caminhos normalizados
resolve_config_paths <- function(config, base_dir) {
    lg <- lgr::get_logger("mhpfv")
    base_dir <- normalizePath(base_dir, mustWork = TRUE)
    path_keys <- c("input", "output", "artifact")

    for (key in path_keys) {
        raw_path <- config[[key]]
        if (is_relative_path(raw_path)) {
            config[[key]] <- normalizePath(
                file.path(base_dir, raw_path), mustWork = FALSE
            )
            lg$info(
                "Caminho relativo '%s' em '%s' resolvido para '%s'",
                raw_path, key, config[[key]]
            )
        }
    }

    if (!dir.exists(config$input)) {
        stop(sprintf(
            "Diretorio de entrada nao encontrado: '%s'", config$input
        ))
    }

    for (key in c("output", "artifact")) {
        if (!dir.exists(config[[key]])) {
            dir.create(config[[key]], recursive = TRUE)
            lg$info("Diretorio '%s' criado: %s", key, config[[key]])
        }
        config[[key]] <- normalizePath(config[[key]])
    }

    config
}

is_relative_path <- function(path) {
    !startsWith(path, "/") &&
        !startsWith(path, "s3://") &&
        !startsWith(path, "~")
}

# VALIDACOES DE CONFIG -----------------------------------------------------------------------------

#' Valida Chaves Do Arquivo De Configuracao
#'
#' Checa se um arquivo de configuracao lido possui todas as chaves necessarias
#'
#' @param config lista de configuracoes
#'
#' @return NULL se config possui todas as chaves; levanta erro do contrario
valida_nomes_config <- function(config) {
    nomes <- config_names()

    has_all <- all(nomes %in% names(config))

    if (!has_all) {
        falta <- nomes[!(nomes %in% names(config))]
        falta <- paste0(falta, collapse = ",")
        msg <- paste0("Arquivo de configuracao nao possui chaves (", falta, ")")
        stop(msg)
    }

    invisible(NULL)
}

config_names <- function() {
    c(
        "mode", "input", "output", "artifact", "janela", "ids_usinas",
        "ordem_prioridade_fontes", "ordem_prioridade_modelosNWP",
        "fator_tolerancia_limite_superior_geracao"
    )
}

#' Valida Tipos Das Chaves Do Arquivo De Configuracao
#'
#' Checa se valores das chaves no arquivo lido sao dos tipos corretos
#'
#' @param config lista de configuracoes
#'
#' @return NULL se config possui todos os tipos corretos; levanta erro do contrario
valida_tipos_config <- function(config) {
    tipos <- config_types()

    config <- config[names(tipos)]
    valid <- vapply(
        seq_along(config),
        function(i) valid_tipos(config[[i]], tipos[[i]]),
        logical(1L)
    )
    names(valid) <- names(config)
    all_valid <- all(valid)

    if (!all_valid) {
        invalid <- names(config)[!valid]
        invalid <- paste0(invalid, collapse = ",")
        msg <- paste0("Chaves (", invalid, ") nao possuem os tipos corretos")
        stop(msg)
    }

    invisible(NULL)
}

config_types <- function() {
    structure(
        list(
            "character", "character", "character", "character", list("integer", "numeric", "character"),
            list("character", "NULL"), "character", "character", "numeric"
        ),
        names = config_names()
    )
}

#' Validacao Singular De Uma Chave
#'
#' Funcao interna auxiliar de `valida_tipos_config()`
#'
#' Tanto `l` quanto `tipos` podem ser escalares ou listas. No caso de `l`, cada elemento sera checado
#' individualmente. Se `tipos` for uma lista, `l` sera checado contra cada um dos tipos e retorna
#' `TRUE` se ao menos um deles for valido
#'
#' @param l valor de uma chave do arquivo de configuracao, escalar ou lista
#' @param tipos tipos esperados de `l`, escalar ou lista
#'
#' @return booleano indicando se validacao encerrou com sucesso ou nao
valid_tipos <- function(l, tipos) all(vapply(l, valid_tipos_unit, logical(1L), tipos = tipos))

#' Auxiliar De `valid_tipos`
#'
#' Funcao interna para isolar o loop ao longo de `l` em `valid_tipos`
#'
#' @param x escalar, elemento de uma chave do arquivo de configuracao
#' @param tipos tipos esperados de `x`, escalar ou lista
#'
#' @return booleano indicando se validacao encerrou com sucesso ou nao
valid_tipos_unit <- function(x, tipos) Reduce("|", lapply(tipos, inherits, x = x))

# PARSERS ------------------------------------------------------------------------------------------

#' Interpretador De Chave `janela`
#'
#' Funcao interna de `parse_config()` para interpretar o parametro `janela` da configuracao
#'
#' @param x valor da chave `janela`; numerico ou vetor de duas strings de data
#'
#' @return vetor `Date` de duas posicoes indicando inicio e fim da janela de melhor historico
parsearg_janela <- function(x) UseMethod("parsearg_janela")

#' @rdname parsearg_janela
parsearg_janela.numeric <- function(x) Sys.Date() - c(x + 1, 1)

#' @rdname parsearg_janela
parsearg_janela.character <- function(x) as.Date(x)

#' Interpretador De Chave `ids_usinas`
#'
#' Funcao interna de `parse_config()` para interpretar o parametro `ids_usinas` da configuracao
#'
#' @param x valor da chave `ids_usinas`; lista vazia ou de codigos de usinas
#' @param conn objeto de conexao com um banco
#'
#' @return se `x` era uma lista vazia, retorna um vetor com todos os ids no banco `conn`; do
#'     contrario retorna `x` vetorizado
parsearg_ids_usinas <- function(x, conn) {
    if (length(x) == 0) x <- get_usinas(conn)$id_usina else x <- unlist(x)
    return(unique(x))
}
