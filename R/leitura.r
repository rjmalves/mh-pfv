#' Leitura De Dados Das Usinas
#'
#' Wrapper para leitura de dados das usinas e subset por usinas
#'
#' @param usina vetor de codigos das usina que devem ser buscadas
#'
#' @return `data.table` de dados das usinas padronizado nas colunas:
#'     * `id_usina`: string indicando codigo da usina
#'     * `latitude`: latutide da usina
#'     * `longitude`: longitude da usina
#'     * `capacidade_instalada_MW`: capacidade instalada da usina
#'     * `data_inicio_operacao_comercial`: POSIX UTC indicando inicio entrada em operacao

get_usinas <- function(usina = NULL, input_dir = NULL) {
    lg <- get_logger()
    lg$debug("Lendo dados das usinas...")

    dt <- inner_reader(usina, NULL, "usinas", input_dir)
    valida_usinas(dt)

    lg$debug("Dados das usinas lidos com sucesso")
    return(dt)
}



#' Leitura dos dados
#'
#' Wrapper para leitura dos dados
#'
#' @param usina vetor de codigos das usina que devem ser buscadas
#' @param fonte vetor de fontes de dados a serem buscados
#'
#' @return `data.table` de geracao observada padronizado nas colunas:
#'     * `id_fonte_observacao`: string indicando a fonte de dados
#'     * `id_usina`: string indicando codigo da usina
#'     * `data_hora_observacao`: POSIX em UTC indicando horario da observacao
#'     * `valor`: valor da geracao observada
#'     * `status`: vazio, nao existe para este dado

get_dados_historicos <- function(v_usinas, fonte, input_dir, modelo_nwp) {
    # Carrega os dados de entrada
    dt_ger_obs <- get_geracao_observada(v_usinas, fonte, input_dir = args$input)
    dt_mhg <- get_melhor_historico_geracao(v_usinas, input_dir = args$input)
    dt_mhg_sem_cortes <- get_melhor_historico_geracao_sem_cortes(v_usinas, input_dir = args$input)
    dt_irrad_prev <- get_irradiancia_prevista(modelo_nwp = args$ordem_prioridade_modelosNWP, input_dir = args$input)
    dt_corte_obs <- get_corte_observado(v_usinas, input_dir = args$input)

    # Retorna a lista com os resultados das leituras
    return(list(
        ger_obs = dt_ger_obs,
        mhg = dt_mhg,
        mhg_sem_cortes = dt_mhg_sem_cortes,
        irrad_prev = dt_irrad_prev,
        dcorte_obs = dt_corte_obs
    ))
}


#' Leitura De Geracao Observada
#'
#' Wrapper para leitura de geracao observada e subsets por usina ou fonte de dados
#'
#' @param usina vetor de codigos das usina que devem ser buscadas
#' @param fonte vetor de fontes de dados a serem buscados
#'
#' @return `data.table` de geracao observada padronizado nas colunas:
#'     * `id_fonte_observacao`: string indicando a fonte de dados
#'     * `id_usina`: string indicando codigo da usina
#'     * `data_hora_observacao`: POSIX em UTC indicando horario da observacao
#'     * `valor`: valor da geracao observada
#'     * `status`: vazio, nao existe para este dado

get_geracao_observada <- function(usina = NULL, fonte = NULL, input_dir = NULL) {
    lg <- get_logger()
    lg$debug("Lendo dados de geracao observada...")

    dt <- inner_reader(usina, fonte, "geracao_observada", input_dir)
    valida_geracao_observada(dt)

    lg$debug("Dados de geracao observada lidos com sucesso")
    return(dt)
}

#' Leitura De Potencia Disponivel Observada
#'
#' Wrapper para leitura de potencia disponivel observada e subsets por usina ou fonte de dados
#'
#' @param usina vetor de codigos das usina que devem ser buscadas
#' @param fonte vetor de fontes de dados a serem buscados
#'
#' @return `data.table` de potencia disponivel observada padronizado nas colunas:
#'     * `id_fonte_observacao`: string indicando a fonte de dados
#'     * `id_usina`: string indicando codigo da usina
#'     * `data_hora_observacao`: POSIX em UTC indicando horario da observacao
#'     * `valor`: valor da potencia disponivel observada
#'     * `status`: vazio, nao existe para este dado

get_potencia_disponivel_observada <- function(usina = NULL, fonte = NULL, input_dir = NULL) {
    lg <- get_logger()
    lg$debug("Lendo dados de potencia disponivel observada...")

    dt <- inner_reader(usina, fonte, "potencia_disponivel_observada", input_dir)
    valida_potencia_disponivel_observada(dt)

    lg$debug("Dados de potencia disponivel observada lidos com sucesso")
    return(dt)
}


#' Leitura De Corte Observado
#'
#' Wrapper para leitura de corte observado e subsets por usina ou fonte de dados
#'
#' @param usina vetor de codigos das usina que devem ser buscadas
#' @param fonte vetor de fontes de dados a serem buscados
#'
#' @return `data.table` de corte observado padronizado nas colunas:
#'     * `id_fonte_observacao`: string indicando a fonte de dados
#'     * `id_usina`: string indicando codigo da usina
#'     * `data_hora_observacao`: POSIX em UTC indicando horario da observacao
#'     * `valor`: valor da corte observado
#'     * `status`: vazio, nao existe para este dado

get_corte_observado <- function(usina = NULL, fonte = NULL, input_dir = NULL) {
    lg <- get_logger()
    lg$debug("Lendo dados de corte observado...")

    dt <- inner_reader(usina, fonte, "corte_observado", input_dir)
    valida_corte_observado(dt)

    lg$debug("Dados de corte observado lidos com sucesso")
    return(dt)
}

#' Leitura De Irradiancia Prevista
#'
#' Wrapper para leitura de irradiancia prevista e subsets por modelo
#'
#' @param modelo_nwp vetor de modelos a serem buscados
#'
#' @return `data.table` de irradiancia prevista padronizado nas colunas:
#'     * `id_modelo_nwp`: string indicando o modelo de previsao
#'     * `latitude`: latutide da usina
#'     * `longitude`: longitude da usina
#'     * `data_hora_rodada`: POSIX em UTC indicando horario da rodada do modelo
#'     * `data_hora_previsao`: POSIX em UTC indicando horario da previsao
#'     * `valor`: valor da irradiancia prevista

get_irradiancia_prevista <- function(modelo_nwp = NULL, input_dir = NULL) {
    lg <- get_logger()
    lg$debug("Lendo dados de irradiancia prevista...")

    dt <- inner_reader_nwp(modelo_nwp, "irradiancia_prevista", input_dir)
    valida_irradiancia_prevista(dt)

    lg$debug("Dados de irradiancia prevista lidos com sucesso")
    return(dt)
}


#' Leitura De Melhor Historico de Geracao
#'
#' Wrapper para leitura de melhor historico de geracao e subsets por usina ou modelo
#'
#' @param usina vetor de codigos das usina que devem ser buscadas
#' @param fonte vetor de fontes de dados a serem buscados
#'
#' @return `data.table` de potencia disponivel observada padronizado nas colunas:
#'     * `id_fonte_observacao`: string indicando a fonte de dados
#'     * `id_usina`: string indicando codigo da usina
#'     * `data_hora_observacao`: POSIX em UTC indicando horario da observacao
#'     * `valor`: valor da potencia disponivel observada
#'     * `status`: vazio, nao existe para este dado

get_melhor_historico_geracao <- function(usina = NULL, fonte = NULL, input_dir = NULL) {
    lg <- get_logger()
    lg$debug("Lendo dados de melhor historico de geracao...")

    dt <- inner_reader(usina, fonte, "melhor_historico_geracao", input_dir)
    valida_melhor_historico_geracao(dt)

    lg$debug("Dados de melhor historico de geracao lidos com sucesso")
    return(dt)
}

#' Leitura De Melhor Historico de Geracao sem Cortes
#'
#' Wrapper para leitura de melhor historico de geracao sem cortes e subsets por usina ou modelo
#'
#' @param usina vetor de codigos das usina que devem ser buscadas
#' @param fonte vetor de fontes de dados a serem buscados
#'
#' @return `data.table` de potencia disponivel observada padronizado nas colunas:
#'     * `id_fonte_observacao`: string indicando a fonte de dados
#'     * `id_usina`: string indicando codigo da usina
#'     * `data_hora_observacao`: POSIX em UTC indicando horario da observacao
#'     * `valor`: valor da potencia disponivel observada
#'     * `status`: vazio, nao existe para este dado

get_melhor_historico_geracao_sem_cortes <- function(usina = NULL, fonte = NULL, input_dir = NULL) {
    lg <- get_logger()
    lg$debug("Lendo dados de melhor historico de geracao sem cortes...")

    dt <- inner_reader(usina, fonte, "melhor_historico_geracao_sem_cortes", input_dir)
    valida_melhor_historico_geracao_sem_cortes(dt)

    lg$debug("Dados de melhor historico de geracao sem cortes lidos com sucesso")
    return(dt)
}


# AUXILIARES ---------------------------------------------------------------------------------------

#' Auxiliar Para Leitura De Dados
#'
#' Funcao interna, nao deve ser chamada diretamente pelo usuario

inner_reader <- function(usina = NULL, fonte = NULL, table = "", input_dir = ".") {
    arq <- file.path(input_dir, paste0(table, ".csv"))
    dt <- fread(arq)
    if (!is.null(usina)) dt <- dt[id_usina %in% usina]
    if (!is.null(fonte)) dt <- dt[id_fonte_observacao %in% fonte]

    return(dt)
}

inner_reader_nwp <- function(modelo_nwp = NULL, table = "", input_dir = ".") {
    arq <- file.path(input_dir, paste0(table, ".csv"))
    dt <- fread(arq)
    if (!is.null(modelo_nwp)) dt <- dt[id_modelo_nwp %in% modelo_nwp]

    return(dt)
}
