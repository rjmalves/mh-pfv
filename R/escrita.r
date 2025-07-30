#' Escrita de Melhor Historico de Geracao
#'
#' Salva os dados de melhor historico de geracao em disco, formatados e validados
#'
#' @param dt `data.table` com os dados a serem salvos
#' @param output_dir diretorio de saida onde sera salvo o arquivo CSV
#'
#' @return Caminho completo do arquivo salvo
write_melhor_historico_geracao <- function(dt, output_dir = ".") {
    lg <- get_pkg_logger()
    lg$debug("Escrevendo dados de melhor historico de geracao...")

    valida_melhor_historico_geracao(dt)

    arq <- inner_writer(dt, "melhor_historico_geracao", output_dir)

    lg$debug("Dados de melhor historico de geracao salvos com sucesso")
    return(arq)
}


#' Escrita de Melhor Historico de Geracao sem Cortes
#'
#' Salva os dados de melhor historico de geracao sem cortes em disco, formatados e validados
#'
#' @param dt `data.table` com os dados a serem salvos
#' @param output_dir diretorio de saida onde sera salvo o arquivo CSV
#'
#' @return Caminho completo do arquivo salvo
write_melhor_historico_geracao_sem_cortes <- function(dt, output_dir = ".") {
    lg <- get_pkg_logger()
    lg$debug("Escrevendo dados de melhor historico de geracao sem cortes...")

    valida_melhor_historico_geracao_sem_cortes(dt)

    arq <- inner_writer(dt, "melhor_historico_geracao_sem_cortes", output_dir)

    lg$debug("Dados de melhor historico de geracao sem cortes salvos com sucesso")
    return(arq)
}



# AUXILIARES ---------------------------------------------------------------------------------------

#' Auxiliar Para Escrita de Dados
#'
#' Funcao interna para salvar data.tables em CSV. Nao deve ser chamada diretamente pelo usuario.
#'
#' @param dt `data.table` a ser salvo
#' @param table nome-base da tabela (sem extensao .csv)
#' @param output_dir diretorio onde o arquivo sera salvo
#'
#' @return Caminho do arquivo salvo
inner_writer <- function(dt, table = "", output_dir = ".") {
    arq <- file.path(output_dir, paste0(table, ".csv"))
    # Escreve o arquivo CSV
    fwrite(dt, arq)

    return(arq)
}
