#' Constroi o interpretador de argumentos de linha de comando
#'
#' @return `ArgumentParser` com os argumentos suportados pelo modelo
#'
#' @export

get_parser <- function() {
    parser <- ArgumentParser(description = "Modelo de Consistencia do Melhor Historico de Geracao Solar")

    parser <- inner_parser_generic_args(parser)
    parser <- inner_parser_specific_args(parser)
    return(parser)
}

# AUXILIARES ---------------------------------------------------------------------------------------

#' Auxiliar para adicionar argumentos genericos
#'
#' Funcao interna, nao deve ser chamada diretamente pelo usuario

inner_parser_generic_args <- function(parser) {
    parser$add_argument("--mode",
        type = "character",
        default = "predict",
        help = "Modo de execucao do modelo: train | predict"
    )

    parser$add_argument("--input",
        type = "character",
        default = ".",
        help = "Caminho para a leitura dos dados de entrada [default: %(default)s]"
    )

    parser$add_argument("--output",
        type = "character",
        default = ".",
        help = "Caminho para a escrita dos dados de saida [default: %(default)s]"
    )

    parser$add_argument("--artifact",
        type = "character",
        default = ".",
        help = "Caminho para obtencao do artefato do modelo treinado [default: %(default)s]"
    )

    return(parser)
}

#' Auxiliar para adicionar argumentos especificos
#'
#' Funcao interna, nao deve ser chamada diretamente pelo usuario
#'
#' @importFrom lubridate format_ISO8601 today ddays

inner_parser_specific_args <- function(
    parser,
    fuso_horario_padrao = Sys.getenv("TZINFO", unset = "UTC"),
    numero_dias_passados_padrao = 90) {
    parser$add_argument("--data-inicio",
        type = "character",
        default = format_ISO8601(today(tzone = fuso_horario_padrao) - ddays(numero_dias_passados_padrao + 1)),
        help = "Data de inicio para calculo do melhor historico [default: %(default)s]"
    )
    parser$add_argument("--data-fim",
        type = "character",
        default = format_ISO8601(today(tzone = fuso_horario_padrao) - ddays(1)),
        help = "Data de fim para calculo do melhor historico [default: %(default)s]"
    )
    parser$add_argument("--ids-usinas",
        type = "character",
        default = NULL,
        help = "Ids de usinas a serem consideradas no processo, separados por virgula ',' [default: todas]"
    )
    parser$add_argument("--ordem-prioridade-fontes",
        type = "character",
        default = "PI,CCEE,CCEE1h",
        help = paste0(
            "Ids em ordem da prioridade das fontes de dados de geracao observada",
            ", separados por virgula ',' [default: PI,CCEE,CCEE1h]"
        )
    )
    parser$add_argument("--ordem-prioridade-modelosNWP",
        type = "character",
        default = "GFS",
        help = paste0(
            "Ids em ordem da prioridade dos modelos numericos de tempo",
            ", separados por virgula ',' [default: GFS]"
        )
    )
    parser$add_argument("--fator-tolerancia-limite-superior-geracao",
        type = "numeric",
        default = 1.1,
        help = paste0(
            "Fator de tolerancia para eliminacao de dados invalidos de geracao, ",
            "multiplicado pela capacidade instalada da usina [default: 1.1]"
        )
    )
    return(parser)
}
