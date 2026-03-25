gen_config <- function(mode = "train", ...) {
    defaults <- list(
        mode = mode,
        input = "./data",
        output = "./out",
        artifact = ".",
        janela = 90,
        ids_usinas = list(),
        ordem_prioridade_fontes = list("PI", "CCEE", "CCEE1h"),
        ordem_prioridade_modelosNWP = list("GFS"),
        fator_tolerancia_limite_superior_geracao = 1.1
    )
    overrides <- list(...)
    defaults[names(overrides)] <- overrides
    defaults
}

gen_default_datas <- function(n_days = 7L, start = "2025-07-01") {
    start_posix <- as.POSIXct(start, tz = "UTC")
    end_posix <- start_posix + (n_days * 86400) - 1800
    seq(start_posix, end_posix, by = "30 mins")
}

gen_usinas <- function(n = 2L, ids = NULL) {
    stopifnot(is.null(ids) || is.character(ids))
    if (is.null(ids)) ids <- paste0("USI", seq_len(n))
    n <- length(ids)
    data.table::data.table(
        id_usina = ids,
        latitude = seq(-12, -25, length.out = n),
        longitude = seq(-38, -50, length.out = n),
        capacidade_instalada_MW = rep(28.0, n),
        data_inicio_operacao_comercial = rep(
            as.POSIXct("2017-08-05", tz = "UTC"), n
        )
    )
}

gen_solar_curve <- function(hours, capacity = 28.0) {
    solar_val <- ifelse(
        hours >= 5.0 & hours <= 18.5,
        capacity * sin(pi * (hours - 5.0) / 13.5),
        0.0
    )
    pmax(solar_val, 0.0)
}

gen_geracao_observada <- function(ids = "USI1", datas = NULL,
    fontes = c("PI"), pattern = "normal", capacity = 28.0, seed = 42L) {

    stopifnot(is.character(ids))
    valid_patterns <- c("normal", "frozen", "missing", "all_na")
    stopifnot(pattern %in% valid_patterns)
    if (is.null(datas)) datas <- gen_default_datas()

    grid <- data.table::CJ(
        id_fonte_observacao = fontes,
        id_usina = ids,
        data_hora_observacao = datas,
        sorted = FALSE
    )

    hours <- data.table::hour(grid$data_hora_observacao) +
        data.table::minute(grid$data_hora_observacao) / 60

    grid[, valor := gen_solar_curve(hours, capacity)]
    grid[, status := 0L]

    gen_geracao_apply_pattern(grid, pattern, seed)
}

gen_geracao_apply_pattern <- function(dt, pattern, seed, ...) {
    mc <- match.call()
    fun <- as.name(paste0("gen_geracao_apply_pattern_", pattern))
    mc[[1]] <- fun
    eval(mc, parent.frame())
}

gen_geracao_apply_pattern_normal <- function(dt, pattern, seed, ...) {
    set.seed(seed)
    dt[valor > 0, valor := valor * (1 + stats::rnorm(.N, 0, 0.05))]
    dt[valor < 0, valor := 0]
    dt[]
}

gen_geracao_apply_pattern_frozen <- function(dt, pattern, seed, ...) {
    is_day <- data.table::hour(dt$data_hora_observacao) >= 5 &
        data.table::hour(dt$data_hora_observacao) <= 18
    dt[is_day, valor := 10.0]
    dt[!is_day, valor := 0.0]
    dt[]
}

gen_geracao_apply_pattern_missing <- function(dt, pattern, seed, ...) {
    set.seed(seed)
    dt[valor > 0, valor := valor * (1 + stats::rnorm(.N, 0, 0.05))]
    dt[valor < 0, valor := 0]
    na_mask <- stats::runif(nrow(dt)) < 0.3
    dt[na_mask, valor := NA_real_]
    dt[]
}

gen_geracao_apply_pattern_all_na <- function(dt, pattern, seed, ...) {
    dt[, valor := NA_real_]
    dt[]
}

gen_irradiancia_prevista <- function(ids = "USI1", datas = NULL,
    modelo_nwp = "GFS") {

    stopifnot(is.character(ids))
    if (is.null(datas)) datas <- gen_default_datas()

    usinas_ref <- gen_usinas(n = length(ids), ids = ids)

    grids <- lapply(seq_along(ids), function(i) {
        usi <- usinas_ref[i]
        dt <- data.table::data.table(
            id_modelo_nwp = modelo_nwp,
            latitude = usi$latitude,
            longitude = usi$longitude,
            data_hora_rodada = datas,
            data_hora_previsao = datas,
            valor = gen_irrad_curve(datas)
        )
        dt
    })

    data.table::rbindlist(grids)
}

gen_irrad_curve <- function(datas) {
    hours <- data.table::hour(datas) +
        data.table::minute(datas) / 60
    ifelse(
        hours >= 5.0 & hours <= 18.5,
        1000 * sin(pi * (hours - 5.0) / 13.5),
        0.0
    )
}

gen_corte_observado <- function(ids = "USI1", datas = NULL,
    frac_corte = 0.05, seed = 42L) {

    stopifnot(is.character(ids))
    if (is.null(datas)) datas <- gen_default_datas()

    grid <- data.table::CJ(
        id_usina = ids,
        data_hora_observacao = datas,
        sorted = FALSE
    )

    set.seed(seed)
    grid[, valor := as.integer(stats::runif(.N) < frac_corte)]
    grid[]
}

gen_mhg <- function(ids = "USI1", datas = NULL, capacity = 28.0,
    seed = 42L) {

    stopifnot(is.character(ids))
    if (is.null(datas)) datas <- gen_default_datas()

    grid <- data.table::CJ(
        id_fonte_observacao = "Consis",
        id_usina = ids,
        data_hora_observacao = datas,
        sorted = FALSE
    )

    hours <- data.table::hour(grid$data_hora_observacao) +
        data.table::minute(grid$data_hora_observacao) / 60

    set.seed(seed)
    grid[, valor := gen_solar_curve(hours, capacity)]
    grid[valor > 0, valor := valor * (1 + stats::rnorm(.N, 0, 0.03))]
    grid[valor < 0, valor := 0]
    grid[, status := sample(1L:4L, .N, replace = TRUE)]
    grid[]
}

gen_model_artifact <- function(id_usina = "USI1") {
    hour_names <- sprintf(
        "%02d:%02d",
        rep(5:18, each = 2),
        rep(c(0, 30), times = 14)
    )
    a_values <- seq(0.01, 0.05, length.out = length(hour_names))
    parametros <- data.frame(
        a = a_values,
        b = rep(0, length(hour_names)),
        row.names = hour_names
    )
    metadata <- list(
        type = "linear_regression",
        n_slots = length(hour_names),
        n_valid_slots = length(hour_names),
        timestamp = as.POSIXct("2025-07-01 00:00:00", tz = "UTC"),
        package_version = as.character(utils::packageVersion("mhpfv")),
        config_hash = "test-hash-placeholder"
    )
    list(id_usina = id_usina, parametros = parametros, metadata = metadata)
}

gen_model_artifact_legacy <- function(id_usina = "USI1") {
    hour_names <- sprintf(
        "%02d:%02d",
        rep(5:18, each = 2),
        rep(c(0, 30), times = 14)
    )
    a_values <- seq(0.01, 0.05, length.out = length(hour_names))
    parametros <- data.frame(
        a = a_values,
        b = rep(0, length(hour_names)),
        row.names = hour_names
    )
    list(id_usina = id_usina, parametros = parametros)
}
