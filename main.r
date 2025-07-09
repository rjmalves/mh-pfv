rm(list = ls())

# setwd("C:/Users/pnascimento/Documents/GitHub/timeseries-mlops-container-examples")

source("R/mini-MH.R")


# definicao de variaveis
font_dad_ger <- c("PI", "CCEE", "CCEE1h")
font_dad_nwpr <- c("GFS", "ECMWF")

# leitura dos dados
dt_usinas <- get_usinas(usina = NULL)
v_usinas <- dt_usinas$id_usina

dt_ger_obs <- get_geracao_observada(usina = v_usinas, fonte = font_dad_ger)

dt_mhg <- get_melhor_historico_geracao(usina = v_usinas)

dt_mhg_sem_cortes <- melhor_historico_geracao_sem_cortes(usina = v_usinas)

dt_irrad_prev <- get_irradiancia_prevista(usina = v_usinas)
# dt_irrad_prev <- get_irradiancia_prevista(usina =  dt_usinas[, .(id_usina, latitude, longitude)], fonte = font_dad_nwpr, nquad=1, horiz=1)

dt_corte_obs <- get_corte_observado(usina = v_usinas)



# gera primeira etapa de dados consistidos
# for (iu in v_usinas) {
for (iu in v_usinas[1]) {
  # consiste geração
  dad_usi <- dt_usinas[id_usina == iu]
  ger_usi <- dt_ger_obs[id_usina == iu]
  corte_obs <- dt_corte_obs[id_usina == iu]
  mhg <- dt_mhg[id_usina == iu]
  mhg_sc <- dt_mhg_sem_cortes[id_usina == iu]
  Pinst <- dad_usi$capacidade_instalada_MW

  irrad_prev <- dt_irrad_prev[id_usina == iu]


  geracao_usina_consis <- consiste_geracao_unit(
    dados_usina = dad_usi,
    geracao_usina = ger_usi,
    ordem_prioridade = font_dad_ger,
    limite_dados = c(0, Pinst * 1.1)
  )


  df_modelo <- data.frame(
    usina = iu,
    leitura = file.path("C:/Users/pnascimento/Documents/GitHub/MH solar Vs teste/saida/modelos/", paste0("modelo_", iu, "_v1.rds")),
    escrita = file.path("C:/Users/pnascimento/Documents/GitHub/MH solar Vs teste/saida/modelos/", paste0("modelo_", iu, "_v1.rds")),
    execucao = "train",
    stringsAsFactors = FALSE
  )

  geracao_usina_preenchida <- preenche_geracao_unit(
    dados_usina = dad_usi,
    geracao_usina = geracao_usina_consis,
    irrad_prev = irrad_prev,
    mhg_prev = mhg,
    cortes = NULL,
    limite_dados = c(0, Pinst * 1.1),
    df_modelo = df_modelo
  )


  dat_min <- min(geracao_usina_consis$data_hora_observacao)
  dat_max <- max(geracao_usina_consis$data_hora_observacao)
  df_modelo$execucao <- "predict"

  # pos_na <- which(corte_obs$valor==1)
  # geracao_usina_completo_s_cortes = copy(geracao_usina_completo)
  # geracao_usina_completo_s_cortes[pos_na, valor := NA]


  geracao_usina_preenchida_sem_cortes <- preenche_geracao_unit(
    dados_usina = dad_usi,
    geracao_usina = geracao_usina_preenchida[data_hora_observacao >= dat_min & data_hora_observacao <= dat_max],
    irrad_prev = irrad_prev,
    mhg_prev = mhg_sc,
    cortes = corte_obs,
    limite_dados = c(0, Pinst * 1.1),
    df_modelo = df_modelo
  )

  # Identificar posições onde preenchida > preenchida_sem_cortes
  idx_maior <-  geracao_usina_preenchida$valor >  geracao_usina_preenchida_sem_cortes$valor

  # Substituir nesses pontos
   geracao_usina_preenchida_sem_cortes[idx_maior, `:=`(
    valor =  geracao_usina_preenchida[idx_maior, valor],
    status =  geracao_usina_preenchida[idx_maior, status]
  )]


  pare <- 1
}
