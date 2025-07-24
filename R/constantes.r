# Schemas para validacao das entradas

# usinas.csv
schema_nomes_usinas <- c(
    "id_usina",
    "latitude",
    "longitude",
    "capacidade_instalada_MW",
    "data_inicio_operacao_comercial"
)
schema_tipos_dados_usinas <- list(
    id_usina = "character",
    latitude = "numeric",
    longitude = "numeric",
    capacidade_instalada_MW = "numeric",
    data_inicio_operacao_comercial = "POSIXct"
)
limites_colunas_usinas <- list(
    latitude = c(-90, 90),
    longitude = c(-180, 180),
    capacidade_instalada_MW = c(0, Inf)
)

# potencia_disponivel_observada.csv
schema_nomes_potencia_disponivel_observada <- c(
    "id_fonte_observacao",
    "id_usina",
    "data_hora_observacao",
    "valor",
    "status"
)
schema_tipos_dados_potencia_disponivel_observada <- list(
    id_fonte_observacao = "character",
    id_usina = "character",
    data_hora_observacao = "POSIXct",
    valor = "numeric",
    status = "integer"
)
limites_colunas_potencia_disponivel_observada <- list(
    valor = c(0, Inf)
)

# geracao_observada.csv
schema_nomes_geracao_observada <- c(
    "id_fonte_observacao",
    "id_usina",
    "data_hora_observacao",
    "valor",
    "status"
)
schema_tipos_dados_geracao_observada <- list(
    id_fonte_observacao = "character",
    id_usina = "character",
    data_hora_observacao = "POSIXct",
    valor = "numeric",
    status = "integer"
)
limites_colunas_geracao_observada <- list(
    valor = c(0, Inf)
)

# corte_observado.csv
schema_nomes_corte_observado <- c(
    "id_fonte_observacao",
    "id_usina",
    "data_hora_observacao",
    "valor",
    "status"
)
schema_tipos_dados_corte_observado <- list(
    id_fonte_observacao = "character",
    id_usina = "character",
    data_hora_observacao = "POSIXct",
    valor = "integer",
    status = "integer"
)
limites_colunas_corte_observado <- list(
    valor = c(0, 1)
)

# irradiancia_prevista.csv
schema_nomes_irradiancia_prevista <- c(
    "id_modelo_nwp",
    "latitude",
    "longitude",
    "data_hora_rodada",
    "data_hora_previsao",
    "valor"
)
schema_tipos_dados_irradiancia_prevista <- list(
    id_modelo_nwp = "character",
    latitude = "numeric",
    longitude = "numeric",
    data_hora_rodada = "POSIXct",
    data_hora_previsao = "POSIXct",
    valor = "numeric"
)
limites_colunas_irradiancia_prevista <- list(
    latitude = c(-90, 90),
    longitude = c(-180, 180),
    valor = c(0, Inf)
)

# melhor_historico_velocidade_vento.csv
schema_nomes_melhor_historico_vento <- c(
    "id_fonte_observacao",
    "id_usina",
    "data_hora_observacao",
    "valor",
    "status"
)
schema_tipos_dados_melhor_historico_vento <- list(
    id_fonte_observacao = "character",
    id_usina = "character",
    data_hora_observacao = "POSIXct",
    valor = "numeric",
    status = "integer"
)
limites_colunas_melhor_historico_vento <- list(
    valor = c(0, Inf)
)

# melhor_historico_geracao.csv
schema_nomes_melhor_historico_geracao <- c(
    "id_fonte_observacao",
    "id_usina",
    "data_hora_observacao",
    "valor",
    "status"
)
schema_tipos_dados_melhor_historico_geracao <- list(
    id_fonte_observacao = "character",
    id_usina = "character",
    data_hora_observacao = "POSIXct",
    valor = "numeric",
    status = "integer"
)
limites_colunas_melhor_historico_geracao <- list(
    valor = c(0, Inf)
)
