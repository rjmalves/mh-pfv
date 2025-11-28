#' Escrita de Melhor Historico de Geracao
#'
#' Salva os dados de melhor historico de geracao em disco, formatados e validados
#'
#' @param dt `data.table` com os dados a serem salvos
#' @param output_dir diretorio de saida onde sera salvo o arquivo CSV
#'
#' @return vazio, apenas escreve arquivo
write_melhor_historico_geracao <- function(dt, output_dir = ".") {
    lg <- get_pkg_logger()
    lg$debug("Escrevendo dados de melhor historico de geracao...")

    pfvIO:::valida_dado_singular_completo(
        dt,
        pfvIO:::guess_col_names("melhor_historico_geracao"),
        pfvIO:::guess_col_types("melhor_historico_geracao"),
        pfvIO:::guess_col_limits("melhor_historico_geracao")
    )

    write_dataset(dt, "melhor_historico_geracao.parquet", output_dir)

    lg$debug("Dados de melhor historico de geracao salvos com sucesso")
}


#' Escrita de Melhor Historico de Geracao sem Cortes
#'
#' Salva os dados de melhor historico de geracao sem cortes em disco, formatados e validados
#'
#' @param dt `data.table` com os dados a serem salvos
#' @param output_dir diretorio de saida onde sera salvo o arquivo CSV
#'
#' @return vazio, apenas escreve arquivo
write_melhor_historico_geracao_sem_cortes <- function(dt, output_dir = ".") {
    lg <- get_pkg_logger()
    lg$debug("Escrevendo dados de melhor historico de geracao sem cortes...")

    pfvIO:::valida_dado_singular_completo(
        dt,
        pfvIO:::guess_col_names("melhor_historico_geracao_sem_cortes"),
        pfvIO:::guess_col_types("melhor_historico_geracao_sem_cortes"),
        pfvIO:::guess_col_limits("melhor_historico_geracao_sem_cortes")
    )

    write_dataset(dt, "melhor_historico_geracao_sem_cortes.parquet", output_dir)

    lg$debug("Dados de melhor historico de geracao sem cortes salvos com sucesso")
}
