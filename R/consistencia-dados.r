#' Trata E Combina Dados De Geracao
#'
#' Condensa um dado de geracao observada com multiplas fontes em uma unica, combinada
#'
#' @param dados_usina `data.table` de dados das usinas com apenas a linha da usina a ser tratada
#' @param geracao_usina `data.table` de geracao observada apenas da usina a ser tratada
#' @param corte_obs `data.table` com os cortes observados, contendo coluna
#' @param ordem_prioridade lista de fontes em ordem de prioridade para combinacao
#' @param limite_dados lista com limites fisicos para validacao dos dados (min, max)
#'
#' @return `geracao_usina` consolidado em apenas uma fonte denominada `"Consis"`

consiste_geracao_unit <- function(dados_usina, geracao_usina, corte_obs, ordem_prioridade, limite_dados) {
    # checa valores faltantes por fonte
    geracao_usina_preenchido <- checa_valores_faltantes(
        dt = geracao_usina
    )

    # checa valores congelados
    geracao_usina_limpos <- checa_valores_congelados(
        dt = copy(geracao_usina_preenchido),
        v_n_valores = c(5, 8),
        v_limiar = c(0.01, 0.1)
    )

    # retorna com a geracao verificada quando ha
    geracao_usina_limpos <- manter_geracao_congelada_em_cortes(
        geracao_usina_limpos,
        geracao_usina,
        corte_obs
    )

    # checa valores valores fora de limites fisicos
    geracao_usina_sem_overbound <- checa_valores_overbound(
        dt = copy(geracao_usina_limpos),
        limites = limite_dados
    )

    # combina entre fontes para cada meia hora
    geracao_usina_combinada <- combina_fontes(
        dt = copy(geracao_usina_sem_overbound),
        grandeza = "geracao_observada",
        ordem = ordem_prioridade
    )

    geracao_usina_combinada$id_fonte_observacao <- "Consis"

    return(geracao_usina_combinada)
}


# AUXILIARES ---------------------------------------------------------------------------------------

#' Remove Valores Congelados da Geracao Observada
#'
#' Detecta e trata valores "congelados" (sem variacao) nos dados de geracao observada,
#' aplicando filtros sequenciais para cada fonte de observacao com base em limiares de repeticao.
#'
#' @param dt `data.table` contendo as colunas `id_fonte_observacao`, `data_hora_observacao` e `valor`.
#'           Representa os dados de geracao observada de uma ou mais fontes.
#' @param v_n_valores Vetor numerico de tamanho `n` indicando os tamanhos das janelas para deteccao de repeticao.
#'                    Valor defaut: `c(5, 8)`.
#'                    Pode ser de qualquer dimensao, porem "limiar" deve ter a mesma dimensao.
#' @param v_limiar Vetor numerico de tamanho `n` indicando os limiares maximos de variacao dentro da janela.
#'                 Valor defaut: `c(0.01, 0.1)`.
#'
#' @return O mesmo `data.table`, com a coluna `valor` ajustada: valores considerados congelados
#'         sao substituidos por `NA`.
#'
#' @details A funcao aplica a funcao `remove_congelados()` duas vezes por grupo (`id_fonte_observacao`),
#'          com diferentes parametros de janela e limiar, permitindo uma filtragem mais robusta de dados
#'          suspeitos de congelamento.
#'
#' @seealso [remove_congelados()]
#'
checa_valores_congelados <- function(dt, v_n_valores = c(5, 8), v_limiar = c(0.01, 0.1)) {
    # Validacao: os vetores devem ter o mesmo comprimento
    if (length(v_n_valores) != length(v_limiar)) {
        stop("v_n_valores e v_limiar devem ter o mesmo comprimento.")
    }

    # Garante que coluna 'valor' e numerica
    dt[, valor := as.numeric(valor)]

    # Ordena os dados por fonte e horário
    setorder(dt, id_fonte_observacao, data_hora_observacao)

    # Aplica sequencialmente remove_congelados para cada par de parâmetros
    for (i in seq_along(v_n_valores)) {
        dt[, valor := remove_congelados(valor, n_valores = v_n_valores[i], limiar = v_limiar[i]),
            by = id_fonte_observacao
        ]
    }

    # Se apenas um valor ficar diferente de NA substitui por NA
    dt[, valor := if (.N - sum(is.na(valor)) == 1) NA_real_ else valor, by = id_fonte_observacao]

    return(dt[])
}


#' Remove Valores Congelados de um Vetor Numerico
#'
#' Identifica e substitui por NA os trechos de dados considerados "congelados",
#' ou seja, sequencias de valores com variacao insignificante dentro de uma janela deslizante.
#'
#' @param v Vetor numerico com os dados de geracao observada.
#' @param n_valores Numero de valores consecutivos considerados para a janela de deteccao.
#'                  Define o tamanho da sequencia minima a ser avaliada como "congelada".
#' @param limiar Variacao maxima permitida entre os valores dentro da janela.
#'               Se a variacao dentro da janela for menor ou igual a esse valor, ela sera considerada congelada.
#'
#' @return Vetor numerico com os mesmos valores de entrada, mas com os trechos identificados como
#'         congelados substituidos por NA.
#'
#' @details
#' A funcao percorre o vetor original com uma janela deslizante de tamanho n_valores.
#' Para cada janela, calcula-se a diferenca entre o valor maximo e o minimo.
#' Se essa diferenca for menor ou igual ao limiar, os valores dentro da janela sao marcados como
#' congelados e substituidos por NA.
#'
#' @seealso checa_valores_congelados
#'
remove_congelados <- function(v, n_valores, limiar) {
    # Vetor logico para marcar posicoes que serao substituidas por NA
    flag_na <- rep(FALSE, length(v))

    # Percorre a serie com uma janela deslizante
    for (i in seq_len(length(v) - n_valores + 1)) {
        # Define a janela atual
        janela <- v[i:(i + n_valores - 1)]

        # Verifica se todos os valores da janela estao suficientemente proximos do primeiro valor
        if (
            all(abs(janela - janela[1]) <= limiar, na.rm = TRUE) &&
                all(!is.na(janela), na.rm = TRUE) &&
                all(janela != 0, na.rm = TRUE)
        ) {
            # Marca como congelados todos os elementos da janela, exceto o primeiro
            flag_na[(i + 1):(i + n_valores - 1)] <- TRUE
        }
    }

    # Substitui os valores marcados por NA
    v[flag_na] <- NA_real_

    # Retorna o vetor processado
    return(v)
}


#' Nao elimina valores congelados quando ha corte
#'
#' Atualiza os valores de geracao limpa (geracao_usina_limpos) com base nas
#' posicoes de corte indicadas em corte_obs. Para cada posicao onde
#' corte_obs$valor == 1, o valor correspondente de geracao_usina e retornado
#' para geracao_usina_limpos.
#'
#' @param geracao_usina_limpos data.table com os dados de geracao tratados,
#'   que sera atualizado conforme os cortes.
#' @param geracao_usina data.table com os dados originais de geracao da usina.
#' @param corte_obs data.table com os cortes observados, contendo coluna
#'   valor que indica posicoes de corte (1 = corte, 0 = nao corte).
#'
#' @return data.table atualizado de geracao_usina_limpos, com os valores
#'   substituidos em todas as posicoes de corte.
#'
manter_geracao_congelada_em_cortes <- function(geracao_usina_limpos, geracao_usina, corte_obs) {
    # junta apenas as posicoes de corte (valor == 1) com os valores de geracao_usina
    cortes_valores <- merge(
        corte_obs[valor == 1, .(id_usina, data_hora_observacao)],
        geracao_usina[, .(id_usina, data_hora_observacao, valor)],
        by = c("id_usina", "data_hora_observacao"),
        all.x = TRUE
    )

    # atualiza os valores de geracao_usina_limpos nessas posicoes
    geracao_usina_limpos[cortes_valores,
        on = .(id_usina, data_hora_observacao),
        valor := i.valor
    ]

    return(geracao_usina_limpos)
}


#' Remove Valores Fora de Limites Pre-Estabelecidos
#'
#' Verifica e substitui por NA os valores que estao fora de um intervalo definido de limites inferior e superior.
#'
#' @param dt Um data.table contendo ao menos uma coluna chamada valor, com os dados numericos a serem verificados.
#' @param limites Vetor numerico de comprimento 2, indicando o limite inferior e superior permitidos, respectivamente.
#'                Valores fora desse intervalo serao considerados invalidos e substituidos por NA.
#'
#' @return O mesmo data.table de entrada, com os valores da coluna valor fora dos limites substituidos por NA.
#'
#' @details
#' A funcao aplica uma verificacao simples nos dados numericos da coluna valor.
#' Todo valor menor que o limite inferior ou maior que o limite superior definido no argumento limites
#' e substituido por NA.
#'
#' @seealso remove_congelados, checa_valores_congelados
#'
checa_valores_overbound <- function(dt, limites = c(0, Inf)) {
    limite_inferior <- limites[1]
    limite_superior <- limites[2]

    # Verifica e aplica NA onde os valores estao fora dos limites
    dt[, valor := fifelse(
        valor < limite_inferior | valor > limite_superior,
        NA_real_,
        valor
    )]

    return(dt)
}


#' Combina Dados de Diferentes Fontes com Base na Grandeza
#'
#' Aplica combinacao de dados a partir de diferentes fontes, com base na grandeza informada.
#' Atualmente, trata apenas o caso de geracao observada.
#'
#' @param dt Um data.table contendo os dados a serem combinados. Deve conter colunas como id_fonte_observacao,
#'           id_usina, data_hora_observacao e valor.
#' @param grandeza String que indica qual tipo de dado sera processado. Atualmente, apenas "geracao_observada"
#'                 esta implementado.
#' @param ordem Vetor de caracteres indicando a ordem de prioridade das fontes (valores da coluna id_fonte_observacao).
#'              Fontes mais prioritarias devem vir primeiro.
#'
#' @return Um data.table com os dados combinados de acordo com a grandeza especificada e a
#'         ordem de prioridade das fontes.
#'
#' @details
#' Esta funcao atua como uma interface para combinacao de dados dependendo da grandeza. Para "geracao_observada",
#' utiliza a funcao combina_dados para selecionar, por usina e horario, os dados nao ausentes de maior prioridade.
#' Outros tipos de grandeza (ex. irradiancia) podem ser implementados no futuro.
#'
#' @seealso combina_dados
#'
combina_fontes <- function(dt, grandeza, ordem) {
    # Se a grandeza for geracao_observada, apenas combina os dados
    if (grandeza == "geracao_observada") {
        geracao_combinada <- combina_dados(dt, ordem)
        dt_comb <- geracao_combinada
    }

    # Retorna o data.table combinado
    return(dt_comb)
}


#' Combina Dados de Diferentes Fontes com Prioridade
#'
#' Seleciona valores nao ausentes a partir de multiplas fontes de dados,
#' com base em uma ordem de prioridade definida pelo usuario.
#'
#' @param dt Um data.table contendo colunas obrigatorias: id_fonte_observacao, id_usina, data_hora_observacao e valor.
#' @param ordem Vetor de caracteres indicando a ordem de prioridade das fontes (valores da coluna id_fonte_observacao).
#'              Fontes mais prioritarias devem aparecer antes no vetor.
#'
#' @return Um data.table com as mesmas colunas do objeto de entrada, contendo apenas um valor por combinacao de id_usina
#'         e data_hora_observacao, escolhido de acordo com a prioridade definida. Fontes com valor NA sao descartadas.
#'         A coluna id_fonte_observacao e substituida por "Consis" para indicar dado combinado, e a coluna status recebe
#'         o indice de prioridade.
#'
#' @details
#' A funcao filtra os dados validos (valores nao NA) e seleciona, para cada combinacao de id_usina e
#' data_hora_observacao, apenas o valor da fonte mais prioritaria. Em seguida, garante que todas as combinacoes de
#' usina e horario estejam presentes no resultado final, mesmo que com valor NA. A coluna de origem e substituida por
#' "Consis" e o status indica a posicao da fonte usada segundo o vetor de prioridade fornecido.
#'
combina_dados <- function(dt, ordem) {
    # Cria uma copia local
    dt_local <- copy(dt)

    # Cria indice de prioridade
    dt_local[, ordem_prioridade := match(id_fonte_observacao, ordem)]

    # Identifica todas as combinacoes de data_hora_observacao e id_usina existentes
    combinacoes <- unique(dt_local[, .(data_hora_observacao, id_usina)])

    # Filtra linhas onde valor nao e NA (para escolher prioridade corretamente)
    dt_validos <- dt_local[!is.na(valor)]

    # Seleciona linhas de maior prioridade (onde existe dado nao-NA)
    dt_resultado <- dt_validos[
        order(data_hora_observacao, id_usina, ordem_prioridade)
    ][
        , .SD[1],
        by = .(data_hora_observacao, id_usina)
    ]

    # Junta com todas as combinacoes para garantir cobertura total
    dt_resultado <- merge(
        combinacoes,
        dt_resultado,
        by = c("data_hora_observacao", "id_usina"),
        all.x = TRUE
    )

    # Atualiza os campos conforme solicitado
    dt_resultado[
        , id_fonte_observacao := fifelse(!is.na(ordem_prioridade), "Consis", NA_character_)
    ]

    dt_resultado[
        , status := ordem_prioridade
    ]

    # Remove coluna auxiliar
    dt_resultado[, ordem_prioridade := NULL]

    # Garante a ordem das colunas igual a do dt original
    setcolorder(dt_resultado, names(dt))

    return(dt_resultado[])
}
