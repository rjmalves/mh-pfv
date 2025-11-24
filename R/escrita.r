#' Escrita do artefato de modelo treinado para uso em previsao
#'
#' Salva o conteudo do objeto do modelo em um arquivo RDS
#'
#' @param model objeto em R representando o modelo treinado
#' @param iu ID da usina, usado para nomear o arquivo
#' @param artifact_dir diretorio de saida onde sera salvo o artefato
#'
#' @return Caminho completo do arquivo salvo
write_model_artifact <- function(model, iu, artifact_dir = ".") {
    lg <- get_pkg_logger()
    lg$debug("Escrevendo modelo treinado...")

    arq <- file.path(artifact_dir, paste0(iu, ".rds"))
    saveRDS(model, arq)

    lg$debug("Modelo treinado salvo com sucesso")
    return(arq)
}

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

    pfvIO:::valida_dado_singular_completo(
        dt,
        pfvIO:::guess_col_names("melhor_historico_geracao"),
        pfvIO:::guess_col_types("melhor_historico_geracao"),
        pfvIO:::guess_col_limits("melhor_historico_geracao")
    )

    arq <- inner_writer(dt,
        "melhor_historico_geracao",
        output_dir,
        output_type = "parquet"
    )

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

    pfvIO:::valida_dado_singular_completo(
        dt,
        pfvIO:::guess_col_names("melhor_historico_geracao_sem_cortes"),
        pfvIO:::guess_col_types("melhor_historico_geracao_sem_cortes"),
        pfvIO:::guess_col_limits("melhor_historico_geracao_sem_cortes")
    )

    arq <- inner_writer(dt,
        "melhor_historico_geracao_sem_cortes",
        output_dir,
        output_type = "parquet"
    )

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
inner_writer <- function(dt, table = "", output_dir = ".", output_type = "csv") {
    if (output_type == "csv") {
        arq <- file.path(output_dir, paste0(table, ".csv"))
        # Escreve o arquivo CSV
        fwrite(dt, arq)
    } else if (output_type == "parquet") {
        arq <- file.path(output_dir, paste0(table, ".parquet"))
        # Escreve o arquivo parquet
        write_parquet(dt, arq)
    }
    return(arq)
}
