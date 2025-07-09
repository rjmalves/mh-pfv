
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

get_usinas <- function(usina = NULL) {
    inner_reader(usina, NULL, "usinas")
}

#' Leitura De Geracao Observada
get_geracao_observada <- function(usina = NULL, fonte = NULL) {
    inner_reader(usina, fonte, "geracao_observada")
}

#' Leitura De Velocidade Do Vento Observada
get_velocidade_vento_observada <- function(usina = NULL, fonte = NULL) {
    inner_reader(usina, fonte, "velocidade_vento_observada")
}

#' Leitura De Melhor Historico De Geracao
get_melhor_historico_geracao <- function(usina = NULL) {
    inner_reader(usina, NULL, "melhor_historico_geracao")
}

#' Leitura De Melhor Historico De Geracao sem cortes
melhor_historico_geracao_sem_cortes <- function(usina = NULL) {
    inner_reader(usina, NULL, "melhor_historico_geracao_sem_cortes")
}


#' Leitura De Melhor Historico De Velocidade Do Vento
get_melhor_historico_vento <- function(usina = NULL) {
    inner_reader(usina, NULL, "melhor_historico_velocidade_vento")
}


#' Leitura dados de irradiancia
get_irradiancia_prevista <- function(usina = NULL) {
    inner_reader(usina, NULL, "irradiancia_prevista")
}

#' Leitura dados de irradiancia
get_corte_observado <- function(usina = NULL) {
    inner_reader(usina, NULL, "corte_observado")
}

# AUXILIARES ---------------------------------------------------------------------------------------

#' Auxiliar Para Leitura De Dados
#' 
#' Funcao interna, nao deve ser chamada diretamente pelo usuario

inner_reader <- function(usina = NULL, fonte = NULL, table = "") {
    arq <- file.path("data", paste0(table, ".csv"))
    dt <- fread(arq)
    if (!is.null(usina)) dt <- dt[id_usina %in% usina]
    if (!is.null(fonte)) dt <- dt[id_fonte_observacao %in% fonte]

    return(dt)
}


inner_reader_nwp <- function(usina = NULL, fonte = NULL,n_quad=1, table = "") {
    arq <- file.path("data", paste0(table, ".csv"))
    dt <- fread(arq)
    if (!is.null(usina)) dt <- dt[id_usina %in% usina]
    if (!is.null(fonte)) dt <- dt[id_fonte_observacao %in% fonte]

    return(dt)
}