#' Trata E Combina Dados De Geracao
#'
#' Condensa um dado de geracao observada com multiplas fontes em uma unica, combinada
#'
#' @param dados_usina `data.table` de dados das usinas com apenas a linha da usina a ser tratada
#' @param geracao_usina `data.table` de geracao observada apenas da usina a ser tratada
#'
#' @return `geracao_usina` consolidado em apenas uma fonte denominada `"Consis"`

consiste_geracao_unit <- function(dados_usina, geracao_usina, ordem_prioridade, limite_dados) {
  # checa valores faltantes por fonte
  geracao_usina_preenchido <- checa_valores_faltantes(
    dt = geracao_usina
  )

  # checa valores congelados
  geracao_usina_limpos <- checa_valores_congelados(
    dt = copy(geracao_usina_preenchido),
    v_n_valores = c(5,8),
    v_limiar = c(0.01,0.1)
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


checa_valores_congelados <- function(dt, v_n_valores = 10, v_limiar = 0.01) {
  # ---------------------------------------------------------
  # Funcao que remove dados congelados para todas as fontes

  # Garante que é data.table
  if (!is.data.table(dt)) dt <- as.data.table(dt)

  # Garante que coluna valor é numérica
  dt[, valor := as.numeric(valor)]

  # Ordena os dados para garantir sequência correta
  setorder(dt, id_fonte_observacao, data_hora_observacao)

  # Aplica para cada fonte de observação
#  dt=dt[id_fonte_observacao == "PI"]
  dt[, valor := remove_congelados(valor, n_valores = v_n_valores[1], limiar = v_limiar[1]),
    by = id_fonte_observacao
  ]

  dt[, valor := remove_congelados(valor, n_valores = v_n_valores[2], limiar = v_limiar[2]),
    by = id_fonte_observacao
  ]

  return(dt[])
}

remove_congelados <- function(v, n_valores, limiar) {
  # ---------------------------------------------------------
  # Funcao que remove dados congelados por fonte

  # Vetor lógico para marcar posições que serão substituídas por NA
  flag_na <- rep(FALSE, length(v))

  # Percorre a série com uma janela deslizante
  for (i in seq_len(length(v) - n_valores + 1)) {
    # Define a janela atual
    janela <- v[i:(i + n_valores - 1)]

    # Verifica se todos os valores da janela estão suficientemente próximos do primeiro valor
    if (all(abs(janela - janela[1]) <= limiar, na.rm = TRUE) && all(!is.na(janela), na.rm = TRUE) && all(janela != 0, na.rm = TRUE)) {
      # Marca como congelados todos os elementos da janela, exceto o primeiro
      flag_na[(i + 1):(i + n_valores - 1)] <- TRUE

      # if(i>2850 && i<2870){
      #   pare=1
      # }
    }
  }

  # Substitui os valores marcados por NA
  v[flag_na] <- NA_real_

  # Retorna o vetor processado
  return(v)
}

checa_valores_overbound <- function(dt, limites = c(0, Inf)) {
  # ---------------------------------------------------------
  # Funcao que elimina dados fora de limites pré-estabelecidos

  limite_inferior <- limites[1]
  limite_superior <- limites[2]

  # Verifica e aplica NA onde os valores estão fora dos limites
  dt[, valor := fifelse(
    valor < limite_inferior | valor > limite_superior,
    NA_real_,
    valor
  )]

  return(dt)
}

combina_fontes <- function(dt, grandeza, ordem) {
  # ---------------------------------------------------------
  # Funcao para combinar dados de diferentes fontes
  # dependendo da grandeza informada

  # Se a grandeza for geracao_observada, apenas combina os dados
  if (grandeza == "geracao_observada") {
    geracao_combinada <- combina_dados(dt, ordem)
    dt_comb <- geracao_combinada
  }

  # Se a grandeza for velocidade_vento_observada
  if (grandeza == "velocidade_vento_observada") {
    # Passo 1 - Ajusta as regressões entre a referencia e as demais fontes
    model_reg <- ajusta_regressao_fontes_vento(dt, ordem)

    # Passo 2 - Remove as fontes que o ajuste não é bom
    dt_dados_bom_ajuste <- elimina_dados_por_R2(
      dt = dt,
      ordem = ordem,
      model_reg = model_reg,
      tol = 0.7
    )

    # Passo 3 - Remove pontos que estao distantes da regressao (outliers)
    dt_pontos_proximos <- elimina_pontos_distantes(
      dt = dt,
      ordem = ordem,
      model_reg = model_reg,
      distancia_limite = 0.5
    )

    # Passo 4 - Ajusta as fontes para estarem na mesma escala da referencia
    dt_fontes_ajustadas <- ajusta_fontes_vento(
      dt = dt_pontos_proximos,
      ordem = ordem,
      model_reg = model_reg
    )

    # Passo 5 - Combina os dados ajustados das fontes
    vento_combinado <- combina_dados(
      dt = dt_fontes_ajustadas,
      ordem = ordem
    )

    dt_comb <- vento_combinado
  }

  # Retorna o data.table combinado
  return(dt_comb)
}


combina_dados <- function(dt, ordem) {
  # ---------------------------------------------------------
  # Funcao que mescla dados de diferentes fontes

  # Cria uma cópia local
  dt_local <- copy(dt)

  # Cria índice de prioridade
  dt_local[, ordem_prioridade := match(id_fonte_observacao, ordem)]

  # Identifica todas as combinações de data_hora_observacao e id_usina existentes
  combinacoes <- unique(dt_local[, .(data_hora_observacao, id_usina)])

  # Filtra linhas onde valor não é NA (para escolher prioridade corretamente)
  dt_validos <- dt_local[!is.na(valor)]

  # Seleciona linhas de maior prioridade (onde existe dado não-NA)
  dt_resultado <- dt_validos[
    order(data_hora_observacao, id_usina, ordem_prioridade)
  ][
    , .SD[1],
    by = .(data_hora_observacao, id_usina)
  ]

  # Junta com todas as combinações para garantir cobertura total
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

  # Garante a ordem das colunas igual à do dt original
  setcolorder(dt_resultado, names(dt))

  return(dt_resultado[])
}

ajusta_regressao_fontes_vento <- function(dt, ordem) {
  # ---------------------------------------------------------
  # Funcao que ajusta regressao linear entre fontes

  # Cria uma cópia local
  dt_local <- copy(dt)

  # Filtra o primeiro da ordem como variável independente (x)
  fonte_ref <- ordem[1]

  dt_ref <- dt_local[
    id_fonte_observacao == fonte_ref,
    .(data_hora_observacao, valor_ref = valor)
  ]

  # Lista para armazenar os resultados
  reg_par <- list()

  # Loop sobre os demais elementos da ordem
  for (fonte in ordem[-1]) {
    # Nomeia o resultado como "fonte_ref_fonte"
    nome_reg <- paste0(fonte_ref, "_", fonte)

    dt_fonte <- dt_local[
      id_fonte_observacao == fonte,
      .(data_hora_observacao, valor_fonte = valor)
    ]

    # Faz o merge pelo timestamp
    dt_merge <- merge(dt_ref, dt_fonte, by = "data_hora_observacao", all = FALSE)

    # Remove NAs
    dt_merge <- dt_merge[complete.cases(dt_merge)]

    if (nrow(dt_merge) > 2) { # Só faz a regressão se houver dados suficientes

      modelo <- lm(valor_ref ~ valor_fonte, data = dt_merge)

      a <- coef(modelo)[["valor_fonte"]]
      b <- coef(modelo)[["(Intercept)"]]
      R2 <- summary(modelo)$r.squared

      reg_par[[nome_reg]] <- c(a = a, b = b, R2 = R2)
    } else {
      reg_par[[nome_reg]] <- rep(NA, 3)
    }
  }
  return(reg_par)
}

elimina_dados_por_R2 <- function(dt, ordem, model_reg, tol) {
  # ---------------------------------------------------------
  # Funcao para eliminar dados de fontes com baixo ajuste,
  # baseado no R2 do modelo de regressao.
  #
  # Se o R2 de uma fonte for menor que o limite 'tol',
  # os valores dessa fonte sao substituidos por NA.

  # Cria uma copia local para nao alterar o dt original
  dt_local <- copy(dt)

  # Define a fonte de referencia (primeiro elemento da ordem)
  fonte_ref <- ordem[1]

  # Loop sobre as demais fontes da ordem
  for (fonte in ordem[-1]) {
    # Nome do modelo na lista
    nome_modelo <- paste0(fonte_ref, "_", fonte)

    # Verifica se o modelo existe na lista
    if (!nome_modelo %in% names(model_reg) || is.na(model_reg[[nome_modelo]][[1]])) {
      warning(paste("Modelo nao encontrado para:", nome_modelo))
      next
    }

    # Extrai o valor de R2
    R2 <- model_reg[[nome_modelo]][["R2"]]

    # Se o R2 for maior que o limite, substitui por NA
    if (!is.na(R2) && R2 < tol) {
      dt_local[id_fonte_observacao == fonte, valor := NA]
    }
  }

  # Retorna os dados com os valores removidos
  return(dt_local[])
}

elimina_pontos_distantes <- function(dt, ordem, model_reg, distancia_limite = 1.5) {
  # ---------------------------------------------------------
  # Funcao que elimina dados distantes da regressao linear

  # Cria uma cópia local
  dt_local <- copy(dt)

  # Define a fonte de referência (primeiro da ordem)
  fonte_ref <- ordem[1]

  # Loop sobre os demais elementos da ordem
  for (fonte in ordem[-1]) {
    nome_modelo <- paste0(fonte_ref, "_", fonte)

    if (!nome_modelo %in% names(model_reg) || is.na(model_reg[[nome_modelo]][[1]])) {
      warning(paste("Modelo não encontrado para:", nome_modelo))
      next
    }

    a <- model_reg[[nome_modelo]][["a"]]
    b <- model_reg[[nome_modelo]][["b"]]

    # Seleciona dados da referência e da fonte
    dt_ref <- dt_local[
      id_fonte_observacao == fonte_ref,
      .(data_hora_observacao, valor_ref = valor)
    ]

    dt_fonte <- dt_local[
      id_fonte_observacao == fonte,
      .(data_hora_observacao, valor_fonte = valor)
    ]

    # Merge para alinhar pelo tempo
    dt_merged <- merge(dt_ref, dt_fonte, by = "data_hora_observacao", all = FALSE)

    # Calcula distância dos pontos para a reta de regressão
    x <- dt_merged$valor_fonte
    y <- dt_merged$valor_ref

    distancias <- abs(a * x - y + b) / sqrt(a^2 + 1)

    # Identifica pontos fora do limite
    pontos_fora <- dt_merged[distancias > distancia_limite, data_hora_observacao]

    # Substitui os valores por NA onde a distância é maior que o limite
    dt_local[
      id_fonte_observacao == fonte & data_hora_observacao %in% pontos_fora,
      valor := NA
    ]

    # ---- Prepara dados para plot ----
    dt_ref <- dt_local[
      id_fonte_observacao == fonte_ref,
      .(data_hora_observacao, valor_ref = valor)
    ]

    dt_fonte_orig <- dt[
      id_fonte_observacao == fonte,
      .(data_hora_observacao, valor_orig = valor)
    ]

    dt_fonte_ajust <- dt_local[
      id_fonte_observacao == fonte,
      .(data_hora_observacao, valor_ajust = valor)
    ]

    scatter_plot_model(dt_ref, dt_fonte_orig, dt_fonte_ajust, model = model_reg[[nome_modelo]])
  }

  return(dt_local[])
}

ajusta_fontes_vento <- function(dt, ordem, model_reg) {
  # ---------------------------------------------------------
  # Funcao para ajustar os valores das fontes de vento
  # utilizando modelos de regressao lineares

  # Cria uma copia local para nao alterar o dt original
  dt_local <- copy(dt)

  # Define a fonte de referencia (primeiro elemento da ordem)
  fonte_ref <- ordem[1]

  # Loop sobre os demais elementos da ordem
  for (fonte in ordem[-1]) {
    # Nome do modelo na lista
    nome_modelo <- paste0(fonte_ref, "_", fonte)

    # Verifica se o modelo existe na lista
    if (!nome_modelo %in% names(model_reg) || is.na(model_reg[[nome_modelo]][[1]])) {
      warning(paste("Modelo nao encontrado para:", nome_modelo))
      next
    }

    # Extrai os parametros da regressao
    a <- model_reg[[nome_modelo]][["a"]]
    b <- model_reg[[nome_modelo]][["b"]]

    # Aplica o ajuste na fonte
    dt_local[
      id_fonte_observacao == fonte,
      valor := b + a * valor
    ]

    # Prepara dados para plot
    dt_ref <- dt_local[
      id_fonte_observacao == fonte_ref,
      .(data_hora_observacao, valor_ref = valor)
    ]

    dt_fonte_orig <- dt[
      id_fonte_observacao == fonte,
      .(data_hora_observacao, valor_orig = valor)
    ]

    dt_fonte_ajust <- dt_local[
      id_fonte_observacao == fonte,
      .(data_hora_observacao, valor_ajust = valor)
    ]

    # Faz o plot dos pontos e da regressao
    scatter_plot_model(
      dt_ref,
      dt_fonte_orig,
      dt_fonte_ajust,
      model = model_reg[[nome_modelo]]
    )
  }

  # Retorna o data.table ajustado
  return(dt_local[])
}
