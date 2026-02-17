#' Funcao Principal de Linha de Comando
#'
#' Ponto de entrada principal do pacote **mhpfv**. Carrega configuracao,
#' valida parametros e despacha para o modo de execucao adequado
#' (treinamento ou previsao).
#'
#' @param datadir caminho para o diretorio de dados de entrada
#'
#' @return `0L` de forma invisivel em caso de sucesso; levanta erro em caso de falha
#'
#' @seealso [train_main()], [predict_main()], [parse_config()], [get_parser()]
#'
#' @export
cli_main <- function(datadir = "./data") {
    lg <- get_pkg_logger()

    conn <- conectamock_pfv(datadir)
    config <- get_config(conn)
    config <- parse_config(config, conn)

    if (config$mode == "train") {
        train_main(config)
    } else if (config$mode == "predict") {
        predict_main(config)
    } else {
        stop(
            "Modo invalido. Apenas os modos 'train' e 'predict'",
            " estao disponiveis para esse modelo."
        )
    }

    invisible(0L)
}
