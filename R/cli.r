#' Le variavel de ambiente booleana
#'
#' Interpreta o valor de uma variavel de ambiente como logico. Aceita
#' `"true"`, `"1"`, `"yes"` como `TRUE` e `"false"`, `"0"`, `"no"` como
#' `FALSE`. Valores invalidos emitem aviso e retornam o padrao.
#'
#' @param name nome da variavel de ambiente
#' @param default valor logico retornado quando a variavel nao esta definida
#'     ou possui valor invalido. Padrao: `FALSE`
#'
#' @return `TRUE` ou `FALSE`

read_env_flag <- function(name, default = FALSE) {
    val <- Sys.getenv(name, unset = "")
    if (val == "") return(default)

    val_lower <- tolower(trimws(val))
    if (val_lower %in% c("true", "1", "yes")) return(TRUE)
    if (val_lower %in% c("false", "0", "no")) return(FALSE)

    lg <- lgr::get_logger("mhpfv")
    lg$warn(
        "Valor invalido para %s: '%s'. Usando padrao: %s",
        name, val, default
    )
    default
}

#' Le variavel de ambiente como inteiro positivo
#'
#' Interpreta o valor de uma variavel de ambiente como inteiro positivo.
#' Valores invalidos (nao numericos, zero ou negativos) emitem aviso e
#' retornam o padrao.
#'
#' @param name nome da variavel de ambiente
#' @param default valor retornado quando a variavel nao esta definida ou
#'     possui valor invalido. Padrao: `NULL`
#'
#' @return inteiro positivo ou `NULL`

read_env_integer <- function(name, default = NULL) {
    val <- Sys.getenv(name, unset = "")
    if (val == "") return(default)

    parsed <- suppressWarnings(as.integer(val))
    if (is.na(parsed) || parsed < 1L) {
        lg <- lgr::get_logger("mhpfv")
        lg$warn(
            "Valor invalido para %s: '%s'. Deve ser inteiro positivo. Usando padrao.",
            name, val
        )
        return(default)
    }
    parsed
}

#' Funcao Principal de Linha de Comando
#'
#' Ponto de entrada principal do pacote **mhpfv**. Carrega configuracao,
#' valida parametros e despacha para o modo de execucao adequado
#' (treinamento ou previsao).
#'
#' A resolucao de prioridade de cada parametro segue a ordem:
#' **argumento explicito** > **variavel de ambiente** > **valor padrao**.
#'
#' | Parametro  | Flag CLI      | Variavel de Ambiente | Padrao  |
#' |------------|---------------|----------------------|---------|
#' | `parallel` | `--parallel`  | `MHPFV_PARALLEL`     | `FALSE` |
#' | `resume`   | `--resume`    | `MHPFV_RESUME`       | `FALSE` |
#' | `workers`  | `--workers N` | `MHPFV_WORKERS`      | `NULL`  |
#'
#' @param datadir caminho para o diretorio de dados de entrada
#' @param parallel logico; habilita processamento paralelo de usinas.
#'     Quando `FALSE` (padrao), a variavel `MHPFV_PARALLEL` e consultada
#' @param resume logico; habilita retomada do pipeline a partir do ultimo
#'     checkpoint. Quando `FALSE` (padrao), a variavel `MHPFV_RESUME` e consultada
#' @param workers inteiro positivo com o numero de workers paralelos, ou `NULL`
#'     para auto-detect. Quando `NULL`, a variavel `MHPFV_WORKERS` e consultada
#'
#' @return `0L` de forma invisivel em caso de sucesso; levanta erro em caso de falha
#'
#' @seealso [train_main()], [predict_main()], [parse_config()], [get_parser()],
#'     [setup_parallel_plan()]
#'
#' @export
cli_main <- function(datadir = "./data", parallel = FALSE, resume = FALSE,
    workers = NULL) {

    lg <- get_pkg_logger()

    if (!isTRUE(parallel)) {
        parallel <- read_env_flag("MHPFV_PARALLEL", FALSE)
    }
    if (!isTRUE(resume)) {
        resume <- read_env_flag("MHPFV_RESUME", FALSE)
    }
    if (is.null(workers)) {
        workers <- read_env_integer("MHPFV_WORKERS", NULL)
    }

    if (!parallel && !is.null(workers)) {
        lg$warn("--workers ignorado quando --parallel nao esta habilitado")
        workers <- NULL
    }

    if (!is.null(workers)) {
        old_workers <- Sys.getenv("MHPFV_WORKERS", unset = NA)
        Sys.setenv(MHPFV_WORKERS = as.character(workers))
        on.exit({
            if (is.na(old_workers)) {
                Sys.unsetenv("MHPFV_WORKERS")
            } else {
                Sys.setenv(MHPFV_WORKERS = old_workers)
            }
        }, add = TRUE)
    }

    lg$info(
        paste0(
            "Parametros resolvidos: parallel=%s, resume=%s, workers=%s | ",
            "ENV: MHPFV_PARALLEL='%s', MHPFV_RESUME='%s', MHPFV_WORKERS='%s'"
        ),
        parallel, resume,
        if (is.null(workers)) "auto" else workers,
        Sys.getenv("MHPFV_PARALLEL", unset = ""),
        Sys.getenv("MHPFV_RESUME", unset = ""),
        Sys.getenv("MHPFV_WORKERS", unset = "")
    )

    conn <- conectamock_pfv(datadir)
    config <- get_config(conn)
    config <- parse_config(config, conn)

    if (config$mode == "train") {
        train_main(config, parallel = parallel, resume = resume)
    } else if (config$mode == "predict") {
        predict_main(config, parallel = parallel, resume = resume)
    } else {
        stop(
            "Modo invalido. Apenas os modos 'train' e 'predict'",
            " estao disponiveis para esse modelo."
        )
    }

    invisible(0L)
}
