#' Coloca NA antes do inicio de operacao
#'
#' Esta funcao substitui os valores de uma tabela de observacoes por NA
#' sempre que a data e hora da observacao ocorrer antes da data de inicio
#' de operacao comercial da usina.
#'
#' @param dt Data table com as observacoes. Deve conter as colunas:
#'   id_usina, data_hora_observacao e valor.
#' @param dados_usina Data table contendo pelo menos as colunas:
#'   id_usina e data_inicio_operacao_comercial.
#'
#' @return A mesma data table dt, mas com valores substituidos por NA
#'   quando a observacao ocorre antes do inicio de operacao.
#'
#' @details
#' A funcao realiza um merge entre a tabela de observacoes e a tabela de dados
#' das usinas para obter a data de inicio de operacao comercial. Em seguida,
#' identifica todas as linhas em que a data e hora da observacao eh anterior
#' ao inicio de operacao e substitui o valor por NA_real_. A operacao mantem
#' o restante da estrutura da tabela inalterada.
#'
coloca_na_antes_inicio <- function(dt, dados_usina) {
    dt <- merge(
        dt,
        dados_usina[, .(id_usina, data_inicio_operacao_comercial)],
        by = "id_usina",
        all.x = TRUE
    )

    dt[
        data_hora_observacao < data_inicio_operacao_comercial,
        valor := NA_real_
    ]

    dt[, data_inicio_operacao_comercial := NULL]
    dt[]
}


#' Checa  Valores Faltantes
#'
#' Detecta e trata valores faltantes nos dados de geracao observada.
#' Valores considerados como faltantes sao "NaN", 999 ou NaN numerico.
#' A funcao preenche a serie temporal para cada fonte de observacao,
#' garantindo intervalos regulares de 30 minutos.
#'
#' @param dt data.table contendo pelo menos as colunas
#'        `id_fonte_observacao`, `data_hora_observacao`, `valor`
#'        e opcionalmente `id_usina`.
#'
#' @return Um data.table contendo as mesmas colunas de entrada,
#' com serie temporal completa a cada 30 minutos para cada fonte,
#' e valores faltantes substituidos por NA.
#'
#' @details
#' A funcao cria uma sequencia completa de tempo de 30 em 30 minutos
#' entre a menor e a maior data por grupo de `id_fonte_observacao`.
#' Caso o campo `id_usina` tenha um unico valor no grupo,
#' ele e replicado em todas as linhas.
#'
checa_valores_faltantes <- function(dt) {
    if (!is.data.table(dt)) dt <- as.data.table(dt)

    dt[valor == "NaN" | is.nan(valor) | valor == 999, valor := NA]

    colunas_ordem_original <- names(dt)

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

            id_usina_unico <- unique(na.omit(id_usina))
            if (length(id_usina_unico) == 1) {
                dt_merged[, id_usina := id_usina_unico]
            }

            dt_merged
        },
        by = .(id_fonte_observacao)
    ]

    setcolorder(dt_resultado, colunas_ordem_original)
    dt_resultado[]
}


#' Combina Dados em Serie Temporal
#'
#' Combina dois data.tables , alinhando a serie temporal
#' em intervalos de 30 minutos e aplicando sobreposicao de valores.
#' Caso existam valores em `dt2`, eles sobrescrevem os de `dt1`.
#'
#' @param dt1 data.table contendo pelo menos as colunas `id_usina`,
#'        `data_hora_observacao`, `valor` e `status`.
#'        Representa a base de dados principal.
#' @param dt2 data.table contendo as mesmas colunas que `dt1`.
#'        Representa os dados que devem sobrepor a base.
#'
#' @return Um data.table com as colunas:
#'         - `id_fonte_observacao`: sempre preenchido com "Consis"
#'         - `id_usina`
#'         - `data_hora_observacao`
#'         - `valor`
#'         - `status`
#'         Os dados estao ordenados por `id_usina` e `data_hora_observacao`.
#'
#' @details
#' A funcao cria uma grade temporal completa entre a menor e a maior
#' data das duas entradas, com intervalo de 30 minutos, para todos os
#' usinas presentes em `dt1` e `dt2`. Em seguida:
#' 1. Faz merge com `dt1` como base.
#' 2. Faz merge com `dt2` e aplica sobreposicao dos valores e status.
#' 3. Adiciona a coluna `id_fonte_observacao` com valor "Consis".
#'
combina_dados_tempo <- function(dt1, dt2) {
    dt1 <- as.data.table(dt1)
    dt2 <- as.data.table(dt2)

    dt1[, valor := as.numeric(valor)]
    dt2[, valor := as.numeric(valor)]
    dt1[, status := as.integer(status)]
    dt2[, status := as.integer(status)]

    usinas <- unique(c(dt1$id_usina, dt2$id_usina))

    datas <- c(
        lubridate::as_datetime(dt1$data_hora_observacao, tz = "UTC"),
        lubridate::as_datetime(dt2$data_hora_observacao, tz = "UTC")
    )
    data_min <- min(datas, na.rm = TRUE)
    data_max <- max(datas, na.rm = TRUE)

    grade <- CJ(
        data_hora_observacao = seq(data_min, data_max, by = "30 mins"),
        id_usina = usinas
    )

    base <- merge(
        grade,
        dt1[, .(data_hora_observacao, id_usina, valor, status)],
        by = c("data_hora_observacao", "id_usina"),
        all.x = TRUE,
        sort = TRUE
    )

    base_final <- merge(
        base,
        dt2[, .(data_hora_observacao, id_usina, valor, status)],
        by = c("data_hora_observacao", "id_usina"),
        all.x = TRUE,
        suffixes = c("_dt1", "_dt2")
    )

    base_final[, valor := fifelse(!is.na(valor_dt2), valor_dt2, valor_dt1)]
    base_final[, status := fifelse(!is.na(status_dt2), status_dt2, status_dt1)]
    base_final[, id_fonte_observacao := "Consis"]

    base_final[
        ,
        .(id_fonte_observacao, id_usina, data_hora_observacao, valor, status)
    ][order(id_usina, data_hora_observacao)]
}


.haversine_cache <- new.env(parent = emptyenv())


make_coord_key <- function(dt_usinas, coord_prev) {
    plant_part <- paste(
        dt_usinas$id_usina, dt_usinas$latitude, dt_usinas$longitude,
        collapse = "|"
    )
    nwp_part <- paste(
        sort(paste(coord_prev$latitude, coord_prev$longitude)),
        collapse = "|"
    )
    paste(plant_part, nwp_part, sep = "##")
}


#' Encontra Coordenadas NWP Mais Proximas para Cada Usina
#'
#' Calcula a distancia Haversine entre cada usina e todas as coordenadas
#' NWP disponiveis, retornando a coordenada mais proxima para cada usina.
#' Resultados sao armazenados em cache para evitar recomputacao.
#'
#' @param dt_usinas data.table contendo pelo menos as colunas:
#'     `id_usina`, `latitude` e `longitude`.
#' @param coord_prev data.table com colunas `latitude` e `longitude`
#'     representando as coordenadas unicas do grid NWP.
#'
#' @return data.table com colunas `id_usina`, `nearest_latitude` e
#'     `nearest_longitude`, contendo o mapeamento de cada usina para
#'     sua coordenada NWP mais proxima.
#'
find_nearest_nwp_coords <- function(dt_usinas, coord_prev) {
    cache_key <- make_coord_key(dt_usinas, coord_prev)

    if (exists(cache_key, envir = .haversine_cache, inherits = FALSE)) {
        return(get(cache_key, envir = .haversine_cache, inherits = FALSE))
    }

    raio_km <- 6371

    mapping <- rbindlist(lapply(seq_len(nrow(dt_usinas)), function(i) {
        usina <- dt_usinas[i]
        coords <- copy(coord_prev)

        coords[, distancia := 2 * raio_km * asin(sqrt(
            sin(((latitude - usina$latitude) * pi / 180) / 2)^2 +
                cos(usina$latitude * pi / 180) * cos(latitude * pi / 180) *
                    sin(((longitude - usina$longitude) * pi / 180) / 2)^2
        ))]

        nearest <- coords[which.min(distancia)]

        data.table(
            id_usina = usina$id_usina,
            nearest_latitude = nearest$latitude,
            nearest_longitude = nearest$longitude
        )
    }))

    assign(cache_key, mapping, envir = .haversine_cache)
    mapping
}


#' Associa Coordenadas de Previsao NWP a Cada Usina
#'
#' Para cada usina em `dt_usinas`, encontra a coordenada mais proxima
#' na previsao NWP (`dt_irrad_prev`) usando distancia Haversine e filtra
#' os dados correspondentes. Retorna os dados de irradiancia previstos
#' com a coluna `id_usina` associada.
#'
#' @param dt_usinas data.table contendo pelo menos as colunas:
#'     `id_usina`, `latitude` e `longitude`.
#' @param dt_irrad_prev data.table contendo previsoes de irradiancia,
#'     com colunas `latitude` e `longitude` (alem de outras colunas de dados).
#'
#' @return data.table com todos os registros de `dt_irrad_prev` filtrados
#'     para a coordenada mais proxima de cada usina e com a coluna
#'     `id_usina` adicionada.
#'
#' @details
#' A funcao:
#' 1. Calcula a distancia Haversine entre cada usina e todas as coordenadas
#'    unicas da previsao (com memoizacao por coordenadas).
#' 2. Seleciona a coordenada mais proxima para cada usina.
#' 3. Filtra os dados da previsao para essa coordenada.
#' 4. Adiciona `id_usina` e reorganiza as colunas.
#'
associa_nwp_usina <- function(dt_usinas, dt_irrad_prev) {
    coord_prev <- unique(dt_irrad_prev[, .(latitude, longitude)])
    mapping <- find_nearest_nwp_coords(dt_usinas, coord_prev)

    lista_filtrados <- lapply(seq_len(nrow(mapping)), function(i) {
        row <- mapping[i]
        dt_filt <- dt_irrad_prev[
            latitude == row$nearest_latitude &
                longitude == row$nearest_longitude
        ]
        dt_filt[, id_usina := row$id_usina]
        dt_filt
    })

    dt_irrad_prev_filt <- rbindlist(lista_filtrados)

    setcolorder(dt_irrad_prev_filt, c(
        "id_modelo_nwp", "id_usina",
        setdiff(names(dt_irrad_prev_filt), c("id_modelo_nwp", "id_usina"))
    ))

    dt_irrad_prev_filt
}


#' Limpa Cache de Distancias Haversine
#'
#' Remove todos os mapeamentos de coordenadas NWP-usina armazenados em cache.
#' Use quando as coordenadas das usinas ou do grid NWP mudarem.
#'
#' @return `invisible(NULL)`
#'
#' @export
clear_haversine_cache <- function() {
    rm(list = ls(.haversine_cache), envir = .haversine_cache)
    invisible(NULL)
}


#' Adiciona a coluna passo_prev com base na diferenca entre datas de rodada e previsao
#'
#' Esta funcao calcula o passo de previsao (em dias) entre as colunas
#' `data_hora_rodada` e `data_hora_previsao` e adiciona a coluna `passo_prev`
#' no formato "D+N", onde N e o numero inteiro de dias de diferenca.
#'
#' @param dt_irrad_prev_filt Um data.table contendo pelo menos as colunas
#'   `data_hora_rodada` e `data_hora_previsao`. As colunas podem estar em
#'   qualquer formato que possa ser convertido para POSIXct.
#'
#' @return O mesmo data.table de entrada, com uma nova coluna `passo_prev`
#'   indicando o passo de previsao em dias (exemplo: "D+0", "D+1", etc).
#'
#' @details
#' A funcao converte as colunas `data_hora_rodada` e `data_hora_previsao` para
#' o tipo POSIXct, garantindo consistencia no calculo de diferencas de datas.
#' Em seguida, calcula a diferenca de dias inteiros entre as duas colunas e
#' gera a string do passo de previsao.
#'
adicionar_passo_previsao <- function(dt_irrad_prev_filt) {
    dt_irrad_prev_filt[, data_hora_rodada := as.POSIXct(data_hora_rodada)]
    dt_irrad_prev_filt[, data_hora_previsao := as.POSIXct(data_hora_previsao)]

    dt_irrad_prev_filt[, passo_prev := paste0(
        "D+",
        as.integer(as.Date(data_hora_previsao) - as.Date(data_hora_rodada))
    )]

    dt_irrad_prev_filt
}


#' Interpolar valores para intervalos de 30 minutos
#'
#' Esta funcao realiza a interpolacao linear de valores em uma tabela de previsao,
#' gerando novas observacoes a cada 30 minutos dentro do intervalo de datas de cada grupo.
#' O agrupamento e feito por `id_modelo_nwp`, `id_usina` e `passo_prev`.
#'
#' @param dt Um data.table contendo as colunas:
#'   - `id_modelo_nwp` (character): identificador do modelo NWP
#'   - `id_usina` (character): identificador da usina
#'   - `latitude` (numeric): latitude da usina
#'   - `longitude` (numeric): longitude da usina
#'   - `data_hora_rodada` (POSIXct): data e hora da rodada do modelo
#'   - `data_hora_previsao` (POSIXct): data e hora da previsao
#'   - `valor` (numeric): valor previsto
#'   - `passo_prev` (character): passo da previsao (ex: "D+1")
#'
#' @return Um `data.table` com os mesmos campos de entrada, porem com novos registros
#'   interpolados em intervalos de 30 minutos. As colunas permanecem na mesma ordem do
#'   objeto original.
#'
#' @details
#' A funcao realiza a interpolacao linear com base na funcao `approx`, garantindo que
#' o intervalo entre `min(data_hora_previsao)` e `max(data_hora_previsao)` de cada grupo
#' seja preenchido com valores a cada 30 minutos. As colunas de identificacao e
#' coordenadas sao mantidas fixas conforme o primeiro registro de cada grupo.
#'
interpolar_30min <- function(dt) {
    dt <- as.data.table(dt)
    col_order <- names(dt)
    setorder(dt, id_modelo_nwp, id_usina, data_hora_previsao)

    dt_interp <- dt[,
        {
            nova_seq <- seq(min(data_hora_previsao), max(data_hora_previsao), by = "30 min")

            valor_interp <- approx(
                x = as.numeric(data_hora_previsao),
                y = valor,
                xout = as.numeric(nova_seq),
                method = "linear"
            )$y

            list(
                latitude = first(latitude),
                longitude = first(longitude),
                data_hora_rodada = first(data_hora_rodada),
                data_hora_previsao = nova_seq,
                valor = valor_interp
            )
        },
        by = .(id_modelo_nwp, id_usina, passo_prev)
    ]

    setcolorder(dt_interp, col_order)
    dt_interp[]
}
