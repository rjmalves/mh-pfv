#' Valida Dados de Entrada
#'
#' Valida um `data.table` contra um schema nomeado. Verifica presenca de colunas
#' obrigatorias, tipos corretos e ausencia de `NA` em colunas-chave. Todos os erros
#' encontrados sao coletados e reportados em uma unica mensagem.
#'
#' Colunas extras presentes no `data.table` que nao fazem parte do schema sao
#' aceitas sem erro. `data.tables` vazios (0 linhas) passam na validacao.
#'
#' @param dt `data.table` a ser validado
#' @param schema_name character escalar com o nome do schema de validacao
#'
#' @return `invisible(TRUE)` se o `data.table` e valido
#'
#' @export
validate_input <- function(dt, schema_name) {
    stopifnot(data.table::is.data.table(dt))
    stopifnot(is.character(schema_name), length(schema_name) == 1L)

    schema <- get_schema(schema_name)
    errors <- character(0L)

    errors <- check_required_columns(errors, dt, schema)
    errors <- check_column_types(errors, dt, schema)
    errors <- check_key_nas(errors, dt, schema)

    if (length(errors) > 0L) {
        msg <- paste0(
            "Validacao do schema '", schema_name, "' falhou:\n",
            paste0("- ", errors, collapse = "\n")
        )
        stop(msg, call. = FALSE)
    }

    invisible(TRUE)
}

#' Valida Todos os Dados de Entrada
#'
#' Valida a lista completa retornada por `get_dataset()` e o `data.table`
#' de usinas contra seus respectivos schemas.
#'
#' @param dataset lista nomeada com os componentes do dataset
#'     (`ger_obs`, `corte`, `irrad_prev`, `mhg`, `mhg_sem_cortes`)
#' @param dt_usinas `data.table` com os dados de usinas
#'
#' @return `invisible(TRUE)` se todos os dados sao validos
#'
#' @export
validate_all_inputs <- function(dataset, dt_usinas) {
    validate_input(dt_usinas, "usinas")
    validate_input(dataset$ger_obs, "geracao_observada")
    validate_input(dataset$irrad_prev, "irradiancia_prevista")
    validate_input(dataset$corte, "corte_observado")
    validate_input(dataset$mhg, "melhor_historico_geracao")
    validate_input(dataset$mhg_sem_cortes, "melhor_historico_geracao")

    invisible(TRUE)
}

# SCHEMAS ------------------------------------------------------------------------------------------

get_schema <- function(name) {
    schemas <- get_all_schemas()
    if (!name %in% names(schemas)) {
        stop("Schema desconhecido: '", name, "'", call. = FALSE)
    }
    schemas[[name]]
}

get_all_schemas <- function() {
    list(
        geracao_observada = list(
            columns = list(
                id_fonte_observacao = "character",
                id_usina = "character",
                data_hora_observacao = "POSIXct",
                valor = "numeric"
            ),
            keys = c("id_usina", "data_hora_observacao")
        ),
        irradiancia_prevista = list(
            columns = list(
                id_modelo_nwp = "character",
                latitude = "numeric",
                longitude = "numeric",
                data_hora_rodada = "POSIXct",
                data_hora_previsao = "POSIXct",
                valor = "numeric"
            ),
            keys = c("data_hora_previsao")
        ),
        corte_observado = list(
            columns = list(
                id_usina = "character",
                data_hora_observacao = "POSIXct",
                valor = "numeric"
            ),
            keys = c("id_usina", "data_hora_observacao")
        ),
        usinas = list(
            columns = list(
                id_usina = "character",
                latitude = "numeric",
                longitude = "numeric",
                capacidade_instalada_MW = "numeric",
                data_inicio_operacao_comercial = "POSIXct"
            ),
            keys = c("id_usina")
        ),
        melhor_historico_geracao = list(
            columns = list(
                id_fonte_observacao = "character",
                id_usina = "character",
                data_hora_observacao = "POSIXct",
                valor = "numeric",
                status = "integer"
            ),
            keys = c("id_usina", "data_hora_observacao")
        )
    )
}

# CHECAGENS INTERNAS -------------------------------------------------------------------------------

check_required_columns <- function(errors, dt, schema) {
    required <- names(schema$columns)
    present <- names(dt)
    missing_cols <- setdiff(required, present)

    if (length(missing_cols) > 0L) {
        msg <- paste0(
            "Colunas obrigatorias ausentes: ",
            paste0("'", missing_cols, "'", collapse = ", ")
        )
        errors <- c(errors, msg)
    }

    errors
}

check_column_types <- function(errors, dt, schema) {
    required <- names(schema$columns)
    present <- intersect(required, names(dt))

    for (col_name in present) {
        expected_type <- schema$columns[[col_name]]
        col_values <- dt[[col_name]]
        if (!check_type(col_values, expected_type)) {
            actual_type <- paste0(class(col_values), collapse = "/")
            msg <- paste0(
                "Coluna '", col_name, "': esperado tipo '",
                expected_type, "', encontrado '", actual_type, "'"
            )
            errors <- c(errors, msg)
        }
    }

    errors
}

check_key_nas <- function(errors, dt, schema) {
    if (nrow(dt) == 0L) return(errors)

    key_cols <- intersect(schema$keys, names(dt))

    for (col_name in key_cols) {
        if (anyNA(dt[[col_name]])) {
            n_na <- sum(is.na(dt[[col_name]]))
            msg <- paste0(
                "Coluna-chave '", col_name, "' contem ",
                n_na, " valor(es) NA"
            )
            errors <- c(errors, msg)
        }
    }

    errors
}

check_type <- function(x, expected) {
    switch(expected,
        numeric = is.numeric(x),
        character = is.character(x),
        POSIXct = inherits(x, "POSIXct"),
        integer = is.integer(x) || is.numeric(x),
        stop("Tipo desconhecido no schema: '", expected, "'", call. = FALSE)
    )
}
