#' Previsao De Melhor Historico Solar
#'
#' Funcao principal para realizacao dos melhores historicos de solar fotovoltaica
#'
#' @param args lista de argumentos para execucao do melhor historico. Veja Detalhes
#'
#' @return escreve no diretorio determinado em `args` os historicos produzidos
#'
#' @export

predict_main <- function(args) {
    # Define a ordem de prioridade das fontes a partir do argumento
    fonte <- strsplit(args$ordem_prioridade_fontes, ",")[[1]]

    # Carrega os dados de entrada das usinas
    dt_usinas <- get_usinas(input_dir = args$input)
    v_usinas <- dt_usinas$id_usina

    # Carrega os dados historicos
    resultados_leitura <- get_dados_historicos(
        v_usinas = v_usinas,
        fonte = fonte,
        input_dir = args$input,
        modelo_nwp = args$ordem_prioridade_modelosNWP
    )


    # Aplica a funcao de processamento individual a cada usina usando lapply
    resultados <- lapply(v_usinas, processar_usina,
        dt_usinas = dt_usinas,
        dt_ger_obs = resultados_leitura$ger_obs,
        dt_mhg = resultados_leitura$mhg,
        dt_mhg_sem_cortes = resultados_leitura$mhg_sem_cortes,
        dt_irrad_prev = resultados_leitura$irrad_prev,
        dt_corte_obs = resultados_leitura$dcorte_obs,
        fonte = fonte,
        fator_tolerancia = args$fator_tolerancia_limite_superior_geracao
    )

    # Organiza os resultados com e sem consideracao de cortes
    resultados_organizados <- organiza_resultados(
        resultados = resultados,
        v_usinas = v_usinas
    )

    # Escreve o MH sem considerar efeitos dos cortes
    write_melhor_historico_geracao(
        dt = resultados_organizados$com_cortes,
        output_dir = args$output
    )

    # Escreve o MH  considerarando efeitos dos cortes
    write_melhor_historico_geracao_sem_cortes(
        dt = resultados_organizados$sem_cortes,
        output_dir = args$output
    )
}



# Esta funcao processa uma unica usina individualmente
processar_usina <- function(
    iu, dt_usinas, dt_ger_obs, dt_mhg, dt_mhg_sem_cortes,
    dt_irrad_prev, dt_corte_obs, fonte, fator_tolerancia) {
    # Filtra os dados referentes a usina atual
    dad_usi <- dt_usinas[id_usina == iu]
    ger_usi <- dt_ger_obs[id_usina == iu]
    corte_obs <- dt_corte_obs[id_usina == iu]
    mhg <- dt_mhg[id_usina == iu]
    mhg_sc <- dt_mhg_sem_cortes[id_usina == iu]
    potencia_instalada <- dad_usi$capacidade_instalada_MW

    # Associa os dados NWP a usina e adiciona o passo de previsao
    dt_irrad_prev_filt <- associa_nwp_usina(dt_usinas, dt_irrad_prev)
    dt_irrad_prev_filt_n <- adicionar_passo_previsao(dt_irrad_prev_filt)
    irrad_prev <- dt_irrad_prev_filt_n[id_usina == iu & passo_prev == "D+0"]

    # Consistencia da geracao observada com base nos limites definidos
    geracao_usina_consis <- consiste_geracao_unit(
        dados_usina = dad_usi,
        geracao_usina = ger_usi,
        ordem_prioridade = fonte,
        limite_dados = c(0, potencia_instalada * fator_tolerancia)
    )

    # Preenche a serie de geracao usando dados previstos e MHG com cortes
    geracao_usina_preenchida <- preenche_geracao_unit(
        dados_usina = dad_usi,
        geracao_usina = geracao_usina_consis,
        irrad_prev = irrad_prev,
        mhg_prev = mhg,
        cortes = NULL,
        limite_dados = c(0, potencia_instalada * fator_tolerancia)
    )

    # Determina o intervalo de datas valido
    dat_min <- min(geracao_usina_consis$data_hora_observacao)
    dat_max <- max(geracao_usina_consis$data_hora_observacao)

    # Preenche novamente com cortes e MHG sem cortes
    geracao_usina_preenchida_sem_cortes <- preenche_geracao_unit(
        dados_usina = dad_usi,
        geracao_usina = geracao_usina_preenchida[
            data_hora_observacao >= dat_min & data_hora_observacao <= dat_max
        ],
        irrad_prev = irrad_prev,
        mhg_prev = mhg_sc,
        cortes = corte_obs,
        limite_dados = c(0, potencia_instalada * fator_tolerancia)
    )

    # Identifica pontos onde o preenchimento com cortes resultou em valor menor
    idx_maior <- geracao_usina_preenchida$valor > geracao_usina_preenchida_sem_cortes$valor

    # Substitui os valores nos pontos onde sem cortes foi menor
    geracao_usina_preenchida_sem_cortes[idx_maior, `:=`(
        valor = geracao_usina_preenchida[idx_maior, valor],
        status = geracao_usina_preenchida[idx_maior, status]
    )]


    # Retorna a lista com os resultados por usina
    return(list(
        com_cortes = geracao_usina_preenchida,
        sem_cortes = geracao_usina_preenchida_sem_cortes
    ))
}


# Esta organiza os dois data.frames
organiza_resultados <- function(resultados, v_usinas) {
    # Adiciona coluna id_usina e empacota resultados em dois data.tables
    dt_com_cortes <- data.table::rbindlist(lapply(seq_along(resultados), function(i) {
        res <- resultados[[i]]$com_cortes
        res[, id_usina := v_usinas[i]]
        return(res)
    }), fill = TRUE)

    dt_sem_cortes <- data.table::rbindlist(lapply(seq_along(resultados), function(i) {
        res <- resultados[[i]]$sem_cortes
        res[, id_usina := v_usinas[i]]
        return(res)
    }), fill = TRUE)

    # Retorna a lista com os resultados organizados
    return(list(
        com_cortes = dt_com_cortes,
        sem_cortes = dt_sem_cortes
    ))
}
