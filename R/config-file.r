
#' Interpreta Arquivo De Configuracao
#' 
#' @param config lista nomeada de 
#' 
#' @return lista de argumentos interpretados

parse_config <- function(config) {
    # validar elementos da lista
    # parse de 'janela'
    #     gerar elementos 'data_inicio' e 'data_fim'
    # retorna config pronto
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
    nomes <- c("mode", "input", "output", "artifact", "janela", "id_usinas",
        "ordem_prioridade_fontes", "ordem_prioridade_modelosNWP",
        "fator_tolerancia_limite_superior_geracao")

    has_all <- all(nomes %in% names(config))

    if (!has_all) {
        falta <- nomes[!(nomes %in% names(config))]
        falta <- paste0(falta, collapse = ",")
        msg <- paste0("Arquivo de configuracao nao possui chaves (", falta, ")")
        stop(msg)
    }

    invisible(NULL)
}

#' Valida Tipos Das Chaves Do Arquivo De Configuracao
#' 
#' Checa se valores das chaves no arquivo lido sao dos tipos corretos
#' 
#' @param config lista de configuracoes
#' 
#' @return NULL se config possui todos os tipos corretos; levanta erro do contrario

valida_tipos_config <- function(config) {
    tipos <- list("character", "character", "character", "character", list("integer", "character"),
        "character", "character", "character", "numeric")
}

#' Validacao Singular De Uma Chave
#' 
#' Funcao interna auxiliar de [`valida_tipos_config`]
#' 
#' Tanto `l` quanto `tipos` podem ser escalares ou listas. No caso de `l`, cada elemento sera checado
#' individualmente. Se `tipos` for uma lista, `l` sera checado contra cada um dos tipos e retorna
#' `TRUE` se ao menos um deles for valido
#' 
#' @param l valor de uma chave do arquivo de configuracao, escalar ou lista
#' @param tipos tipos esperados de `l`, escalar ou lista
#' 
#' @return booleano indicando se validacao encerrou com sucesso ou nao

valid_tipos <- function(l, tipos) do.call(all, list(sapply(l, valid_tipos_unit, tipos = tipos)))

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

parsearg_janela <- function(x) UseMethod("parsearg_janela")

parsearg_janela.numeric <- function(x) Sys.Date() - c(x + 1, 1)

parsearg_janela.character <- function(x) as.Date(x)