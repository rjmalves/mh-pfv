#' Constroi o interpretador de argumentos de linha de comando
#'
#' @return `ArgumentParser` com os argumentos suportados pelo modelo
#'
#' @export

get_parser <- function() {
    parser <- ArgumentParser(description = "Modelo de Consistencia do Melhor Historico de Geracao Solar")

    parser <- inner_parser_generic_args(parser)
    return(parser)
}

# AUXILIARES ---------------------------------------------------------------------------------------

#' Auxiliar para adicionar argumentos genericos
#'
#' @param parser `ArgumentParser` a ser modificado
#'
#' Funcao interna, nao deve ser chamada diretamente pelo usuario

inner_parser_generic_args <- function(parser) {
    help_msg <- paste0(
        "Diretorio de dados para execucao do melhor historico -- Veja ",
        "https://github.com/rjmalves/mh-pfv para detalhes"
    )
    parser$add_argument("--datadir",
        type = "character",
        default = "./data",
        help = help_msg
    )
    parser$add_argument("--parallel",
        action = "store_true",
        default = FALSE,
        help = "Habilita processamento paralelo de usinas"
    )
    parser$add_argument("--resume",
        action = "store_true",
        default = FALSE,
        help = "Habilita retomada do pipeline a partir do ultimo checkpoint"
    )
    parser$add_argument("--workers",
        type = "integer",
        default = NULL,
        help = "Numero de workers paralelos (padrao: auto-detect via availableCores() - 1)"
    )

    return(parser)
}
