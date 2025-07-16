checa_valores_faltantes <- function(dt) {
  if (!is.data.table(dt)) dt <- as.data.table(dt)

  dt[valor == "NaN" | is.nan(valor) | valor == 999, valor := NA]

  # Salvar a ordem original das colunas
  colunas_ordem_original <- names(dt)

  # Aplicar o preenchimento por grupo
  dt_resultado <- dt[,
    {
      seq_tempo <- seq(
        from = min(data_hora_observacao),
        to   = max(data_hora_observacao),
        by   = "30 mins"
      )

      dt_completo <- data.table(data_hora_observacao = seq_tempo)

      dt_merged <- merge(
        dt_completo,
        .SD,
        by = "data_hora_observacao",
        all.x = TRUE,
        sort = TRUE
      )

      # Preencher id_usina se for único no grupo
      id_usina_unico <- unique(na.omit(id_usina))
      if (length(id_usina_unico) == 1) {
        dt_merged[, id_usina := id_usina_unico]
      }

      dt_merged
    },
    by = .(id_fonte_observacao)
  ]

  # Ordenar as colunas na ordem original
  setcolorder(dt_resultado, colunas_ordem_original)

  return(dt_resultado[])
}



combina_dados_tempo <- function(dt1, dt2) {

  # Garante que são data.tables
  dt1 <- as.data.table(dt1)
  dt2 <- as.data.table(dt2)

  # Força tipos corretos
  dt1[, valor := as.numeric(valor)]
  dt2[, valor := as.numeric(valor)]

  dt1[, status := as.integer(status)]
  dt2[, status := as.integer(status)]

  # Identifica todos os id_usina presentes
  usinas <- unique(c(dt1$id_usina, dt2$id_usina))

  # Define o intervalo de datas
  data_min <- min(c(dt1$data_hora_observacao, dt2$data_hora_observacao), na.rm = TRUE)
  data_max <- max(c(dt1$data_hora_observacao, dt2$data_hora_observacao), na.rm = TRUE)

  # Cria grade completa
  grade <- CJ(
    data_hora_observacao = seq(data_min, data_max, by = "30 mins"),
    id_usina = usinas
  )

  # Merge com dt1 (base)
  base <- merge(
    grade,
    dt1[, .(data_hora_observacao, id_usina, valor, status)],
    by = c("data_hora_observacao", "id_usina"),
    all.x = TRUE,
    sort = TRUE
  )

  # Merge com dt2 (sobreposição)
  dt2_reduzido <- dt2[, .(data_hora_observacao, id_usina, valor, status)]

  base_final <- merge(
    base,
    dt2_reduzido,
    by = c("data_hora_observacao", "id_usina"),
    all.x = TRUE,
    suffixes = c("_dt1", "_dt2")
  )

  # Aplica sobreposição
  base_final[, valor := fifelse(!is.na(valor_dt2), valor_dt2, valor_dt1)]
  base_final[, status := fifelse(!is.na(status_dt2), status_dt2, status_dt1)]

  # Adiciona id_fonte_observacao = "Consis"
  base_final[, id_fonte_observacao := "Consis"]

  # Seleciona colunas finais
  resultado <- base_final[
    ,
    .(id_fonte_observacao, id_usina, data_hora_observacao, valor, status)
  ][order(id_usina, data_hora_observacao)]

  return(resultado[])
}





# Função usando distância euclidiana
associa_NWP_Usina <- function(dt_usinas, dt_irrad_prev) {
  
  # Coordenadas únicas da previsão
  coord_prev <- unique(dt_irrad_prev[, .(latitude, longitude)])
  
  # Lista para armazenar os resultados
  lista_filtrados <- list()
  
  # Loop sobre cada usina
  for (i in 1:nrow(dt_usinas)) {
    usina <- dt_usinas[i]
    
    # Calcula a distância euclidiana entre a usina e todas as coordenadas da previsão
    coord_prev[, distancia := sqrt((latitude - usina$latitude)^2 + (longitude - usina$longitude)^2)]
    
    # Pega a coordenada mais próxima
    coord_mais_proxima <- coord_prev[which.min(distancia)]
    
    # Filtra os dados da previsão para essa coordenada
    dt_filt <- dt_irrad_prev[latitude == coord_mais_proxima$latitude &
                             longitude == coord_mais_proxima$longitude]
    
    # Adiciona o id_usina
    dt_filt[, id_usina := usina$id_usina]
    
    # Adiciona à lista
    lista_filtrados[[i]] <- dt_filt
  }
  
  # Junta tudo
  dt_irrad_prev_filt <- rbindlist(lista_filtrados)
  
   # Reorganiza para id_usina ser a 2ª coluna
  setcolorder(dt_irrad_prev_filt, c("id_modelo_nwp", "id_usina", 
                                    setdiff(names(dt_irrad_prev_filt), c("id_modelo_nwp", "id_usina"))))
 
  return(dt_irrad_prev_filt)
}



adicionar_passo_previsao <- function(dt_irrad_prev_filt) {
  # Garante que as colunas são do tipo POSIXct
  dt_irrad_prev_filt[, data_hora_rodada := as.POSIXct(data_hora_rodada)]
  dt_irrad_prev_filt[, data_hora_previsao := as.POSIXct(data_hora_previsao)]
  
  # Calcula a diferença de dias entre as datas (ignorando horário)
  dt_irrad_prev_filt[, passo_prev := paste0("D+", as.integer(as.Date(data_hora_previsao) - as.Date(data_hora_rodada)))]
  
  return(dt_irrad_prev_filt)
}

