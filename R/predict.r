#' Funcao Principal de Consolidacao dos dados
#'
#' Executa o processamento completo de consistencia dos dados observados para um conjunto de usinas,
#' considerando diferentes fontes e modelos em ordem de prioridade.
#'
#' @param args Lista de argumentos necessarios para o processamento. Os campos esperados sao:
#' \itemize{
#'   \item \code{artifact}: caminho onde artefatos adicionais serao armazenados.
#'   \item \code{data_inicio}: string com a data inicial no formato "yyyy-mm-dd",
#'                             indicando o inicio do periodo de analise.
#'   \item \code{data_fim}: string com a data final no formato "yyyy-mm-dd", indicando o fim do periodo de analise.
#'   \item \code{fator_tolerancia_limite_superior_geracao}: valor numerico que define o fator de tolerancia
#'                                                          aplicado ao limite superior de geracao observada.
#'   \item \code{ids_usinas}: vetor com os IDs das usinas a serem processadas. Se \code{NULL}, todas as usinas
#'                            disponiveis serao utilizadas.
#'   \item \code{input}: caminho para a pasta onde estao localizados os dados de entrada
#'                       (ex: dados de SCADA, modelos NWP, cortes, etc.).
#'   \item \code{mode}: string que define o modo de operacao. Deve ser "predict" para rodar o fluxo de consistencia.
#'   \item \code{ordem_prioridade_fontes}: string com os nomes das fontes de dados separados por virgula,
#'                                         indicando a ordem de prioridade para uso dos dados historicos.
#'   \item \code{ordem_prioridade_modelosNWP}: string com os nomes dos modelos NWP separados por virgula,
#'                                             em ordem de prioridade.
#'   \item \code{output}: caminho para a pasta onde os arquivos de saida serao escritos.
#' }
#'
#' @return Nenhum valor e retornado pela funcao. Os resultados sao gravados diretamente em arquivos
#'         na pasta de saida especificada.
#'
#' @details
#' A funcao executa o fluxo completo para cada usina:
#' \enumerate{
#'   \item Leitura da configuracao e dados de entrada (usinas, geracao observada, modelos NWP, cortes, etc).
#'   \item Aplicacao da funcao \code{processar_usina} para cada usina de forma individual.
#'   \item Organizacao dos resultados com e sem consideracao de cortes.
#'   \item Escrita dos melhores historicos de geracao observada nos formatos de saida esperados.
#' }
#'
#' @seealso processar_usina, get_dados_historicos, organiza_resultados, write_melhor_historico_geracao
#'
#' @export
#'
predict_main <- function(args) {
    # Define a ordem de prioridade das fontes a partir do argumento
    conn <- conectamock_pfv(args$input)

    v_usinas <- args$ids_usinas
    dt_usinas <- get_usinas(conn, id_usina = v_usinas)

    dataset <- get_dataset(args, conn)

    # Aplica a funcao de processamento individual a cada usina usando lapply
    resultados <- lapply(v_usinas, processar_usina,
        dt_usinas = dt_usinas,
        dt_ger_obs = dataset$ger_obs,
        dt_mhg = dataset$mhg,
        dt_mhg_sem_cortes = dataset$mhg_sem_cortes,
        dt_irrad_prev = dataset$irrad_prev,
        dt_corte_obs = dataset$corte,
        fonte = args$ordem_prioridade_fontes,
        fator_tolerancia = args$fator_tolerancia_limite_superior_geracao,
        artifact_dir = args$artifact
    )

    # Organiza os resultados com e sem consideracao de cortes
    resultados_organizados <- organiza_resultados(
        resultados = resultados,
        v_usinas = v_usinas
    )

    # remove valores de antes da entrada em operacao comercial da usina
    geracao_usina_preenchida_com_cortes <- coloca_na_antes_inicio(
        dt = copy(resultados_organizados$com_cortes),
        dados_usina = dt_usinas
    )

    # remove valores de antes da entrada em operacao comercial da usina
    geracao_usina_preenchida_sem_cortes <- coloca_na_antes_inicio(
        dt = copy(resultados_organizados$sem_cortes),
        dados_usina = dt_usinas
    )

    # Escreve o MH sem considerar efeitos dos cortes
    write_melhor_historico_geracao(
        dt = geracao_usina_preenchida_com_cortes,
        output_dir = args$output
    )

    # Escreve o MH  considerarando efeitos dos cortes
    write_melhor_historico_geracao_sem_cortes(
        dt = geracao_usina_preenchida_sem_cortes,
        output_dir = args$output
    )
}

get_dataset <- function(args, conn) {
    janela <- paste0(args$janela[1], "/", args$janela[2])

    ger_obs <- get_geracao_observada(conn,
        id_usina = args$ids_usinas,
        data_hora_observacao = janela
    )
    corte <- get_corte_observado(conn,
        id_usina = args$ids_usinas,
        id_fonte_observacao = args$ordem_prioridade_fontes, data_hora_observacao = janela
    )
    irrad_prev <- get_irradiancia_prevista(conn,
        id_usina = args$ids_usinas,
        id_modelo_nwp = args$ordem_prioridade_modelosNWP, data_hora_previsao = janela
    )
    mhg <- get_melhor_historico_geracao(conn, id_usina = args$ids_usinas)
    mhg_sem_cortes <- get_melhor_historico_geracao_sem_cortes(conn, id_usina = args$ids_usinas)

    out <- list(ger_obs, corte, irrad_prev, mhg, mhg_sem_cortes)
    names(out) <- c("ger_obs", "corte", "irrad_prev", "mhg", "mhg_sem_cortes")

    return(out)
}

# Esta funcao processa uma unica usina individualmente
processar_usina <- function(
    iu, dt_usinas, dt_ger_obs, dt_mhg, dt_mhg_sem_cortes,
    dt_irrad_prev, dt_corte_obs, fonte, fator_tolerancia,
    artifact_dir
) {
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

    irrad_prev <- interpolar_30min(irrad_prev)

    # Consistencia da geracao observada com base nos limites definidos
    geracao_usina_consis <- consiste_geracao_unit(
        dados_usina = dad_usi,
        geracao_usina = ger_usi,
        corte_obs = corte_obs,
        ordem_prioridade = fonte,
        limite_dados = c(0, potencia_instalada * fator_tolerancia)
    )

    # Leitura dos modelos de estimacao
    model <- pfvIO:::get_model_artifact(iu, artifact_dir)

    # Preenche a serie de geracao usando dados previstos e MHG com cortes
    geracao_usina_preenchida <- preenche_geracao_unit(
        geracao_usina = geracao_usina_consis,
        irrad_prev = irrad_prev,
        mhg_prev = mhg,
        cortes = NULL,
        limite_dados = c(0, potencia_instalada * fator_tolerancia),
        model = model
    )

    # Define o intervalo de datas
    datas <- lubridate::as_datetime(geracao_usina_consis$data_hora_observacao, tz = "UTC")

    dat_min <- min(datas, na.rm = TRUE)
    dat_max <- max(datas, na.rm = TRUE)

    # Preenche novamente com cortes e MHG sem cortes
    geracao_usina_preenchida_sem_cortes <- preenche_geracao_unit(
        geracao_usina = geracao_usina_preenchida[
            data_hora_observacao >= dat_min & data_hora_observacao <= dat_max
        ],
        irrad_prev = irrad_prev,
        mhg_prev = mhg_sc,
        cortes = corte_obs,
        limite_dados = c(0, potencia_instalada * fator_tolerancia),
        model = model
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


#' Organiza Resultados de Previsao por Usina
#'
#' Agrupa os resultados processados individualmente por usina em dois data.tables:
#' um com consideracao de cortes e outro sem.
#'
#' @param resultados Lista contendo, para cada usina, um sub-lista com dois elementos:
#'   \itemize{
#'     \item \code{com_cortes}: data.table com os dados considerando os efeitos de corte.
#'     \item \code{sem_cortes}: data.table com os dados sem considerar os cortes.
#'   }
#' @param v_usinas Vetor de caracteres com os IDs das usinas, na mesma ordem da lista \code{resultados}.
#'
#' @return Uma lista com dois data.tables:
#'   \itemize{
#'     \item \code{com_cortes}: dados de todas as usinas, concatenados e com a coluna \code{id_usina} preenchida.
#'     \item \code{sem_cortes}: dados das mesmas usinas sem considerar cortes, tambem com \code{id_usina}.
#'   }
#'
#' @details
#' A funcao percorre os elementos da lista \code{resultados}, adiciona a identificacao da usina correspondente,
#' e empacota os dados finais em dois data.tables: um com cortes e outro sem. Util para consolidar os resultados
#' apos o processamento individual de cada usina.
#'
#' @seealso processar_usina, predict_main
#'
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
