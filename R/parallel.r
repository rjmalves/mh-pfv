#' @importFrom future plan availableCores nbrOfWorkers
#' @importFrom future.apply future_lapply
NULL

#' Configura Backend de Execucao Paralela
#'
#' Inicializa o plano de execucao paralela do pacote `future` com a estrategia
#' e numero de workers especificados. O plano anterior e retornado
#' invisivelmente para permitir restauracao posterior via [reset_parallel_plan()].
#'
#' Quando `workers = NULL`, a variavel de ambiente `MHPFV_WORKERS` e consultada
#' como fallback antes de recorrer ao auto-detect via `availableCores() - 1`.
#'
#' @param workers inteiro positivo indicando o numero de workers, ou `NULL`
#'     para usar `MHPFV_WORKERS` (se definida) ou `future::availableCores() - 1`
#'     (minimo 1)
#' @param strategy character escalar com a estrategia de paralelismo. Deve ser
#'     um entre `"multisession"`, `"multicore"` ou `"sequential"`
#'
#' @return o plano anterior (invisivelmente), como retornado por `future::plan()`
#'
#' @examples
#' old <- setup_parallel_plan(workers = 2L, strategy = "multisession")
#' get_parallel_config()
#' reset_parallel_plan(old)
#'
#' @export
setup_parallel_plan <- function(workers = NULL,
    strategy = c("multisession", "multicore", "sequential")) {

    strategy <- match.arg(strategy)

    if (is.null(workers)) {
        workers <- read_env_workers_fallback()
    }

    validate_workers(workers)

    if (is.null(workers)) {
        workers <- max(1L, future::availableCores() - 1L)
    }

    lg <- lgr::get_logger("mhpfv")

    if (strategy == "sequential") {
        old_plan <- future::plan("sequential")
        lg$info("Plano paralelo configurado: strategy=sequential")
        return(invisible(old_plan))
    }

    old_plan <- future::plan(strategy, workers = workers)
    lg$info("Plano paralelo configurado: strategy=%s, workers=%d",
        strategy, workers)

    invisible(old_plan)
}

#' Restaura Plano de Execucao Paralela Anterior
#'
#' Restaura um plano de execucao paralela salvo previamente, tipicamente
#' obtido como retorno de [setup_parallel_plan()].
#'
#' @param old_plan plano anterior retornado por [setup_parallel_plan()]
#'
#' @return `invisible(NULL)`
#'
#' @examples
#' old <- setup_parallel_plan(strategy = "sequential")
#' reset_parallel_plan(old)
#'
#' @export
reset_parallel_plan <- function(old_plan) {
    future::plan(old_plan)
    invisible(NULL)
}

#' Consulta Configuracao Atual do Plano Paralelo
#'
#' Retorna a configuracao ativa do backend paralelo, incluindo o numero de
#' workers e a estrategia em uso.
#'
#' @return lista nomeada com os elementos:
#' \describe{
#'   \item{workers}{inteiro com o numero de workers ativos}
#'   \item{strategy}{character com o nome da estrategia em uso}
#' }
#'
#' @examples
#' get_parallel_config()
#'
#' @export
get_parallel_config <- function() {
    list(
        workers = future::nbrOfWorkers(),
        strategy = extract_strategy_name(future::plan())
    )
}

extract_strategy_name <- function(plan_obj) {
    known <- c("sequential", "multisession", "multicore")
    classes <- class(plan_obj)
    found <- intersect(classes, known)
    if (length(found) == 0L) return(classes[1L])
    found[1L]
}

read_env_workers_fallback <- function() {
    env_workers <- Sys.getenv("MHPFV_WORKERS", unset = "")
    if (env_workers == "") return(NULL)

    parsed <- suppressWarnings(as.integer(env_workers))
    if (is.na(parsed) || parsed < 1L) {
        lgr::get_logger("mhpfv")$warn(
            "MHPFV_WORKERS invalido: '%s'. Usando auto-detect.", env_workers
        )
        return(NULL)
    }
    parsed
}

is_valid_worker_count <- function(workers) {
    is.numeric(workers) && length(workers) == 1L &&
        !is.na(workers) && workers >= 1L && workers == as.integer(workers)
}

validate_workers <- function(workers) {
    if (is.null(workers)) return(invisible(NULL))
    if (!is_valid_worker_count(workers)) {
        stop(
            "workers deve ser NULL ou um inteiro positivo, recebido: ",
            deparse(workers),
            call. = FALSE
        )
    }
    invisible(NULL)
}
