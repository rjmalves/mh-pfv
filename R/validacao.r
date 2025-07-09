#' Funcao para validar o `data.table` de usinas
#'
#' @param dados `data.table` para validacao
#'

valida_usinas <- function(dados) {
    lg <- get_logger()
    lg$debug("Validando dados das usinas...")

    valida_nomes_tipos(dados, schema_nomes_usinas, schema_tipos_dados_usinas)
    valida_limites(dados, limites_colunas_usinas)

    lg$debug("Dados das usinas validados com sucesso")
}

#' Funcao para validar o `data.table` de potencia disponivel observada
#'
#' @param dados `data.table` para validacao
#'

valida_potencia_disponivel_observada <- function(dados) {
    lg <- get_logger()
    lg$debug("Validando dados de potencia disponivel observada...")

    valida_nomes_tipos(
        dados,
        schema_nomes_potencia_disponivel_observada,
        schema_tipos_dados_potencia_disponivel_observada
    )
    valida_limites(dados, limites_colunas_potencia_disponivel_observada)

    lg$debug("Dados de potencia disponivel observada validados com sucesso")
}

#' Funcao para validar o `data.table` de geracao observada
#'
#' @param dados `data.table` para validacao
#'

valida_geracao_observada <- function(dados) {
    lg <- get_logger()
    lg$debug("Validando dados de geracao observada...")

    valida_nomes_tipos(
        dados,
        schema_nomes_geracao_observada,
        schema_tipos_dados_geracao_observada
    )
    valida_limites(dados, limites_colunas_geracao_observada)

    lg$debug("Dados de geracao observada validados com sucesso")
}

#' Funcao para validar o `data.table` de corte observado
#'
#' @param dados `data.table` para validacao
#'

valida_corte_observado <- function(dados) {
    lg <- get_logger()
    lg$debug("Validando dados de corte observado...")

    valida_nomes_tipos(
        dados,
        schema_nomes_corte_observado,
        schema_tipos_dados_corte_observado
    )
    valida_limites(dados, limites_colunas_corte_observado)

    lg$debug("Dados de corte observado validados com sucesso")
}

#' Funcao para validar o `data.table` de irradiancia prevista
#'
#' @param dados `data.table` para validacao
#'

valida_irradiancia_prevista <- function(dados) {
    lg <- get_logger()
    lg$debug("Validando dados de irradiancia prevista...")

    valida_nomes_tipos(
        dados,
        schema_nomes_irradiancia_prevista,
        schema_tipos_dados_irradiancia_prevista
    )
    valida_limites(dados, limites_colunas_irradiancia_prevista)

    lg$debug("Dados de irradiancia prevista validados com sucesso")
}

#' Funcao para validar o `data.table` de melhor historico de geracao
#'
#' @param dados `data.table` para validacao
#'

valida_melhor_historico_geracao <- function(dados) {
    lg <- get_logger()
    lg$debug("Validando dados de melhor historico de geracao...")

    valida_nomes_tipos(
        dados,
        schema_nomes_melhor_historico_geracao,
        schema_tipos_dados_melhor_historico_geracao
    )
    valida_limites(dados, limites_colunas_melhor_historico_geracao)

    lg$debug("Dados de melhor historico de geracao validados com sucesso")
}

#' Funcao para validar o `data.table` de melhor historico de geracao sem cortes
#'
#' @param dados `data.table` para validacao
#'

valida_melhor_historico_geracao_sem_cortes <- function(dados) {
    lg <- get_logger()
    lg$debug("Validando dados de melhor historico de geracao sem cortes...")

    valida_nomes_tipos(
        dados,
        schema_nomes_melhor_historico_geracao,
        schema_tipos_dados_melhor_historico_geracao
    )
    valida_limites(dados, limites_colunas_melhor_historico_geracao)

    lg$debug("Dados de melhor historico de geracao sem cortes validados com sucesso")
}


# AUXILIARES ---------------------------------------------------------------------------------------

#' Auxiliar para validar um `data.table` em termos dos nomes das colunas
#'
#' @param dados `data.table` de dados para validacao
#' @param lista_nomes vetor de nomes de colunas para serem validados
#'
#' @return lista com nomes 'sucesso' e 'mensagem_erro' para tratamento externo

valida_nomes_colunas <- function(dados, lista_nomes) {
    sucesso <- all(lista_nomes %in% names(dados))
    mensagem_erro <- sprintf(
        "Arquivo nao contem todas as colunas. ESPERADAS = [%s], OBTIDAS = [%s]",
        paste(lista_nomes, collapse = ", "),
        paste(names(dados), collapse = ", ")
    )

    list(
        sucesso = sucesso,
        mensagem_erro = mensagem_erro
    )
}

#' Auxiliar para validar um `data.table` em termos dos tipos de dados das colunas
#'
#' @param dados `data.table` de dados para validacao
#' @param lista_tipos lista nomeada com os tipos de dados esperados em cada coluna
#'
#' @return lista com nomes 'sucesso' e 'mensagem_erro' para tratamento externo

valida_tipos_dados_colunas <- function(dados, lista_tipos) {
    nomes_colunas <- names(lista_tipos)

    tipos_dados <- as.list(dados[, lapply(.SD, class), .SD = nomes_colunas])

    resultado_tipos <- sapply(nomes_colunas, function(coluna) {
        tipo_coluna_schema <- lista_tipos[[coluna]]
        tipo_coluna_lido <- tipos_dados[[coluna]]

        all(tipo_coluna_schema %in% tipo_coluna_lido)
    }, USE.NAMES = TRUE)

    sucesso <- all(resultado_tipos)
    mensagem_erro <- sprintf(
        "Arquivo nao contem os tipos esperados. ESPERADOS = [%s], OBTIDOS = [%s]",
        paste(lista_tipos, collapse = ", "),
        paste(tipos_dados, collapse = ", ")
    )

    list(
        sucesso = sucesso,
        mensagem_erro = mensagem_erro
    )
}

#' Auxiliar para validacoes genericas de nomes e tipos
#'
#' @param dados `data.table` de dados para validacao
#' @param lista_nomes vetor de nomes de colunas para serem validados
#' @param lista_tipos lista nomeada com os tipos de dados esperados em cada coluna

valida_nomes_tipos <- function(dados, lista_nomes, lista_tipos) {
    resultado_validacao_nomes <- valida_nomes_colunas(dados, lista_nomes)
    if (!resultado_validacao_nomes$sucesso) {
        stop(resultado_validacao_nomes$mensagem_erro)
    }

    resultado_validacao_tipos <- valida_tipos_dados_colunas(dados, lista_tipos)
    if (!resultado_validacao_tipos$sucesso) {
        stop(resultado_validacao_tipos$mensagem_erro)
    }
}

#' Auxiliar para validar intervalo numerico
#'
#' @param dados `data.table` de dados para validacao
#' @param nome_coluna nome da coluna a ser validada
#' @param limites lista com limites inferior e superior dos dados da coluna
#'
#' @return lista com nomes 'sucesso' e 'mensagem_erro' para tratamento externo

valida_intervalo <- function(dados, nome_coluna, limites) {
    sucesso <- dados[get(nome_coluna) %between% limites, .N] == dados[!is.na(get(nome_coluna)), .N]
    mensagem_erro <- sprintf(
        "A coluna %s nao possui valores entre [%s]",
        nome_coluna,
        paste(limites, collapse = ", ")
    )

    list(
        sucesso = sucesso,
        mensagem_erro = mensagem_erro
    )
}

#' Auxiliar para validacoes genericas de colunas numericas
#'
#' @param dados `data.table` de dados para validacao
#' @param lista_limites lista nomeada com os limites de cada coluna

valida_limites <- function(dados, lista_limites) {
    nomes_colunas <- names(lista_limites)

    lapply(nomes_colunas, function(coluna) {
        intervalo <- lista_limites[[coluna]]
        resultado <- valida_intervalo(dados, coluna, intervalo)
        if (!resultado$sucesso) {
            stop(resultado$mensagem_erro)
        }
    })

    NULL
}
