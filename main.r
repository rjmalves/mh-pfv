rm(list = ls())

# setwd("C:/Users/pnascimento/Documents/GitHub/timeseries-mlops-container-examples")

source("R/mini-MH.r")

lg <- logger_setup()

train_main <- function(args) {
    fonte <- strsplit(args$ordem_prioridade_fontes, ",")[[1]]

    dt_usinas <- get_usinas(input_dir = args$input)
    v_usinas <- dt_usinas$id_usina
    dt_ger_obs <- get_geracao_observada(v_usinas, fonte, input_dir = args$input)
    dt_mhg <- get_melhor_historico_geracao(v_usinas, input_dir = args$input)
    dt_mhg_sem_cortes <- get_melhor_historico_geracao_sem_cortes(v_usinas, input_dir = args$input)
    dt_irrad_prev <- get_irradiancia_prevista(modelo_nwp = args$ordem_prioridade_modelosNWP, input_dir = args$input)
    dt_corte_obs <- get_corte_observado(v_usinas, input_dir = args$input)

    for (iu in v_usinas[1]) {
        # consiste geração
        dad_usi <- dt_usinas[id_usina == iu]
        ger_usi <- dt_ger_obs[id_usina == iu]
        corte_obs <- dt_corte_obs[id_usina == iu]
        mhg <- dt_mhg[id_usina == iu]
        mhg_sc <- dt_mhg_sem_cortes[id_usina == iu]
        Pinst <- dad_usi$capacidade_instalada_MW

        
        dt_irrad_prev_filt <- associa_NWP_Usina(dt_usinas, dt_irrad_prev)

        dt_irrad_prev_filt_n <- adicionar_passo_previsao(dt_irrad_prev_filt)

        irrad_prev <- dt_irrad_prev_filt_n[id_usina == iu & passo_prev == "D+0"]

        geracao_usina_consis <- consiste_geracao_unit(
            dados_usina = dad_usi,
            geracao_usina = ger_usi,
            ordem_prioridade = fonte,
            limite_dados = c(0, Pinst * args$fator_tolerancia_limite_superior_geracao)
        )

        df_modelo <- data.frame(
            usina = iu,
            leitura = file.path(args$artifact, paste0("modelo_", iu, "_v1.rds")),
            escrita = file.path(args$output, paste0("modelo_", iu, "_v1.rds")),
            execucao = "train",
            stringsAsFactors = FALSE
        )

        geracao_usina_preenchida <- preenche_geracao_unit(
            dados_usina = dad_usi,
            geracao_usina = geracao_usina_consis,
            irrad_prev = irrad_prev,
            mhg_prev = mhg,
            cortes = NULL,
            limite_dados = c(0, Pinst * args$fator_tolerancia_limite_superior_geracao),
            df_modelo = df_modelo
        )

        dat_min <- min(geracao_usina_consis$data_hora_observacao)
        dat_max <- max(geracao_usina_consis$data_hora_observacao)
        df_modelo$execucao <- "predict"


        geracao_usina_preenchida_sem_cortes <- preenche_geracao_unit(
            dados_usina = dad_usi,
            geracao_usina = geracao_usina_preenchida[data_hora_observacao >= dat_min & data_hora_observacao <= dat_max],
            irrad_prev = irrad_prev,
            mhg_prev = mhg_sc,
            cortes = corte_obs,
            limite_dados = c(0, Pinst * args$fator_tolerancia_limite_superior_geracao),
            df_modelo = df_modelo
        )

        # Identificar posições onde preenchida > preenchida_sem_cortes
        idx_maior <- geracao_usina_preenchida$valor > geracao_usina_preenchida_sem_cortes$valor

        # Substituir nesses pontos
        geracao_usina_preenchida_sem_cortes[idx_maior, `:=`(
            valor = geracao_usina_preenchida[idx_maior, valor],
            status = geracao_usina_preenchida[idx_maior, status]
        )]
    }
}
predict_main <- function(args) {}


tryCatch(
    {
        parser <- get_parser()
        args <- parser$parse_args()
        if (args$mode == "train") {
            train_main(args)
        } else if (args$mode == "predict") {
            predict_main(args)
        } else {
            stop("Modo invalido. Use 'train' ou 'predict'.")
        }
        q(status = 0)
    },
    error = function(e) {
        lg$error(e)
        q(status = 1)
    }
)
