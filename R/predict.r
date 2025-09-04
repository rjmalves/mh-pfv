#' Funcao Principal de Previsao de Geracao
#'
#' Executa o processamento completo de previsao de geracao observada para um conjunto de usinas, considerando diferentes fontes e modelos em ordem de prioridade.
#'
#' @param args Lista de argumentos necessarios para o processamento. Os campos esperados sao:
#' \itemize{
#'   \item \code{artifact}: caminho onde artefatos adicionais serao armazenados.
#'   \item \code{data_inicio}: string com a data inicial no formato "yyyy-mm-dd", indicando o inicio do periodo de analise.
#'   \item \code{data_fim}: string com a data final no formato "yyyy-mm-dd", indicando o fim do periodo de analise.
#'   \item \code{fator_tolerancia_limite_superior_geracao}: valor numerico que define o fator de tolerancia aplicado ao limite superior de geracao observada.
#'   \item \code{ids_usinas}: vetor com os IDs das usinas a serem processadas. Se \code{NULL}, todas as usinas disponiveis serao utilizadas.
#'   \item \code{input}: caminho para a pasta onde estao localizados os dados de entrada (ex: dados de SCADA, modelos NWP, cortes, etc.).
#'   \item \code{mode}: string que define o modo de operacao. Deve ser "predict" para rodar o fluxo de previsao.
#'   \item \code{ordem_prioridade_fontes}: string com os nomes das fontes de dados separados por virgula, indicando a ordem de prioridade para uso dos dados historicos.
#'   \item \code{ordem_prioridade_modelosNWP}: string com os nomes dos modelos NWP separados por virgula, em ordem de prioridade.
#'   \item \code{output}: caminho para a pasta onde os arquivos de saida serao escritos.
#' }
#'
#' @return Nenhum valor e retornado pela funcao. Os resultados sao gravados diretamente em arquivos na pasta de saida especificada.
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
#' @examples
#' args <- list(
#'     artifact = ".",
#'     data_fim = "2025-07-29",
#'     data_inicio = "2025-04-30",
#'     fator_tolerancia_limite_superior_geracao = 1.1,
#'     ids_usinas = NULL,
#'     input = "./data",
#'     mode = "predict",
#'     ordem_prioridade_fontes = "PI,CCEE,CCEE1h",
#'     ordem_prioridade_modelosNWP = "GFS",
#'     output = "./saida"
#' )
#' predict_main(args)
#'
#' @seealso processar_usina, get_dados_historicos, organiza_resultados, write_melhor_historico_geracao
#' 
#' @export

predict_main <- function(args) {
    # Define a ordem de prioridade das fontes a partir do argumento
    conn <- conectamock_pfv(args$input)

    fonte <- args$ordem_prioridade_fontes
    v_usinas <- args$ids_usinas
    dt_usinas <- get_usinas(conn, id_usina = v_usinas)

    dataset <- list(
        ger_obs = get_geracao_observada(conn, id_usina = v_usinas),
        corte = get_corte_observado(conn, id_usina = v_usinas, id_fonte_observacao = fonte),
        irrad_prev = get_irradiancia_prevista(conn, id_usina = v_usinas,
            id_modelo_nwp = args$ordem_prioridade_modelosNWP),
        mhg = get_melhor_historico_geracao(conn, id_usina = v_usinas),
        mhg_sem_cortes = get_melhor_historico_geracao_sem_cortes(conn, id_usina = v_usinas)
    )

    # Aplica a funcao de processamento individual a cada usina usando lapply
    resultados <- lapply(v_usinas, processar_usina,
        dt_usinas = dt_usinas,
        dt_ger_obs = dataset$ger_obs,
        dt_mhg = dataset$mhg,
        dt_mhg_sem_cortes = dataset$mhg_sem_cortes,
        dt_irrad_prev = dataset$irrad_prev,
        dt_corte_obs = dataset$corte,
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


#' Organiza Resultados de Previsao por Usina
#'
#' Agrupa os resultados processados individualmente por usina em dois data.tables: um com consideracao de cortes e outro sem.
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
#' @examples
#' library(data.table)
#' horas <- seq.POSIXt(as.POSIXct("2025-05-19 00:00"), by = "30 min", length.out = 3)
#'
#' resultado_exemplo <- lapply(
#'     list(
#'         list(usina = "BAUFI1", valor = 0),
#'         list(usina = "BAUFI2", valor = 1)
#'     ),
#'     function(x) {
#'         dados <- data.table(
#'             id_fonte_observacao = "Consis",
#'             data_hora_observacao = horas,
#'             id_usina = x$usina,
#'             valor = x$valor,
#'             status = 1
#'         )
#'         list(com_cortes = copy(dados), sem_cortes = copy(dados))
#'     }
#' )
#' head(resultado_final$com_cortes)
#' head(resultado_final$sem_cortes)
#'
#' @seealso processar_usina, predict_main

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




#' Adequa dados observados e previstos
#'
#' Aplica filtros sobre listas de dados observados e previstos de usinas,
#' retornando apenas os registros dentro das condicoes de interesse.
#'
#' @param resultados_leitura Lista de data.tables contendo os dados brutos,
#'   incluindo observados, previstos e demais dados auxiliares.
#' @param v_usinas Vetor de identificadores das usinas a serem mantidas.
#' @param fonte Vetor de identificadores de fonte de observacao a serem filtrados.
#' @param modelo_nwp Vetor de identificadores de modelos NWP a serem filtrados.
#' @param data_inicio Data inicial no formato reconhecido por as.POSIXct.
#' @param data_fim Data final no formato reconhecido por as.POSIXct.
#'
#' @return Uma lista com as mesmas estruturas de entrada, mas filtradas de acordo com
#'   os parametros de usinas, fontes, modelos e intervalo de tempo.
#'
#' @details
#' A funcao separa as listas de dados em tres grupos: observados, previstos
#' e auxiliares. Aplica filtros especificos a cada grupo e depois junta novamente
#' os resultados preservando os nomes originais.
#'
#' @examples
#' library(data.table)
#' horas <- seq.POSIXt(as.POSIXct("2025-05-26 00:00"), by = "1 hour", length.out = 4)
#' obs <- data.table(
#'     id_usina = c("U1", "U2"),
#'     id_fonte_observacao = "Consis",
#'     data_hora_observacao = rep(horas, each = 2),
#'     valor = runif(8)
#' )
#' prev <- data.table(
#'     id_modelo_nwp = "ModeloA",
#'     data_hora_previsao = horas,
#'     valor = runif(4)
#' )
#' resultados_leitura <- list(
#'     ger_obs = obs,
#'     dcorte_obs = obs,
#'     mhg = obs,
#'     mhg_sem_cortes = obs,
#'     irrad_prev = prev
#' )
#' dados_filtrados <- adequa_dados(
#'     resultados_leitura,
#'     v_usinas = "U1",
#'     fonte = "Consis",
#'     modelo_nwp = "ModeloA",
#'     data_inicio = "2025-05-26",
#'     data_fim = "2025-05-26 02:00:00"
#' )
#' lapply(dados_filtrados, head)
#'
#' @seealso adequa_dados_observados, adequa_dados_previstos
adequa_dados <- function(resultados_leitura, v_usinas, fonte, modelo_nwp, data_inicio, data_fim) {
    # lista de nomes de observados e previstos
    nomes_manter <- c("mhg", "mhg_sem_cortes")
    nomes_obs <- c("ger_obs", "dcorte_obs")
    nomes_prev <- c("irrad_prev")

    # separa listas
    lista_manter <- resultados_leitura[nomes_manter]
    lista_obs <- resultados_leitura[nomes_obs]
    lista_prev <- resultados_leitura[nomes_prev]

    # Ajusta hora de inicio/fim se vier só a data (yyyy-mm-dd)
    if (nchar(data_inicio) == 10) data_inicio <- paste0(data_inicio, " 00:00:00")
    if (nchar(data_fim) == 10) data_fim <- paste0(data_fim, " 23:30:00")

    # aplica filtros
    lista_obs_f <- adequa_dados_observados(lista_obs, v_usinas, fonte, data_inicio, data_fim)
    lista_prev_f <- adequa_dados_previstos(lista_prev, modelo_nwp, data_inicio, data_fim)

    # junta de volta e preserva nomes
    c(lista_obs_f, lista_manter, lista_prev_f)
}

#' Filtra lista de dados observados
#'
#' @param lista_obs Lista de data.tables com dados observados.
#' @param v_usinas Vetor de identificadores de usinas.
#' @param fonte Vetor de identificadores de fonte de observacao.
#' @param data_inicio Data inicial no formato reconhecido por as.POSIXct.
#' @param data_fim Data final no formato reconhecido por as.POSIXct.
#'
#' @return Lista de data.tables filtrados.
adequa_dados_observados <- function(lista_obs, v_usinas, fonte, data_inicio, data_fim) {
    lapply(lista_obs, function(dt) {
        dt[
            id_usina %in% v_usinas &
                id_fonte_observacao %in% fonte &
                data_hora_observacao >= as.POSIXct(data_inicio) &
                data_hora_observacao <= as.POSIXct(data_fim) # , tz = "UTC")
        ]
    })
}

#' Filtra lista de dados previstos
#'
#' @param lista_prev Lista de data.tables com dados previstos.
#' @param modelo_nwp Vetor de identificadores de modelos NWP.
#' @param data_inicio Data inicial no formato reconhecido por as.POSIXct.
#' @param data_fim Data final no formato reconhecido por as.POSIXct.
#'
#' @return Lista de data.tables filtrados.
adequa_dados_previstos <- function(lista_prev, modelo_nwp, data_inicio, data_fim) {
    lapply(lista_prev, function(dt) {
        dt[
            id_modelo_nwp %in% modelo_nwp &
                data_hora_previsao >= as.POSIXct(data_inicio, tz = "UTC") &
                data_hora_previsao <= as.POSIXct(data_fim, tz = "UTC")
        ]
    })
}
