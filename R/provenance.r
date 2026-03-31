#' Gera Identificador Unico de Execucao
#'
#' Produz um ID unico no formato `{mode}-{YYYYMMDD}-{HHMMSS}-{4hex}`,
#' adequado para identificar execucoes do pipeline de forma nao ambigua.
#' O sufixo hexadecimal e gerado por amostragem aleatoria do estado global
#' do RNG, reduzindo colisoes entre execucoes concorrentes no mesmo segundo.
#'
#' @param mode character escalar, `"train"` ou `"predict"`
#'
#' @return character com o run ID
#'
#' @examples
#' generate_run_id("train")
#' generate_run_id("predict")
#'
#' @export
generate_run_id <- function(mode) {
    stopifnot(is.character(mode), length(mode) == 1L)
    ts <- format(Sys.time(), "%Y%m%d-%H%M%S")
    hex <- paste0(
        sprintf("%x", sample(0:15, 4, replace = TRUE)),
        collapse = ""
    )
    paste0(mode, "-", ts, "-", hex)
}

#' Cria Registro de Proveniencia de Execucao
#'
#' Monta a estrutura completa de proveniencia para uma execucao do pipeline,
#' incluindo identificador unico, versoes do pacote e do R, hash da
#' configuracao e status inicial de cada usina.
#'
#' @param config lista com a configuracao do pipeline (deve conter
#'   `ids_usinas`)
#' @param mode character escalar, `"train"` ou `"predict"`
#' @param parallel logico, se a execucao e paralela
#'
#' @return lista com todos os campos de proveniencia:
#' \describe{
#'   \item{`run_id`}{character, identificador unico da execucao}
#'   \item{`mode`}{character, modo de execucao}
#'   \item{`package_version`}{character, versao do pacote `mhpfv`}
#'   \item{`r_version`}{character, versao do R}
#'   \item{`start_time`}{`POSIXct`, momento de inicio}
#'   \item{`end_time`}{`NULL`, preenchido na finalizacao}
#'   \item{`duration_seconds`}{`NULL`, computado na finalizacao}
#'   \item{`config_hash`}{character, SHA-256 da configuracao normalizada}
#'   \item{`n_plants`}{inteiro, numero de usinas a processar}
#'   \item{`plant_ids`}{character, vetor de IDs de usinas}
#'   \item{`plant_status`}{lista nomeada, status por usina (inicia `"pending"`)}
#'   \item{`parallel`}{logico, se execucao e paralela}
#'   \item{`status`}{character, `"running"` inicialmente}
#' }
#'
#' @examples
#' cfg <- list(ids_usinas = c("USI1", "USI2"), janela = c("2025-07-01", "2025-09-30"))
#' prov <- create_provenance(cfg, "train", FALSE)
#'
#' @export
create_provenance <- function(config, mode, parallel = FALSE) {
    run_id <- generate_run_id(mode)

    plant_ids <- config$ids_usinas
    plant_status <- as.list(rep("pending", length(plant_ids)))
    names(plant_status) <- plant_ids

    list(
        run_id = run_id,
        mode = mode,
        package_version = as.character(utils::packageVersion("mhpfv")),
        r_version = paste0(R.version$major, ".", R.version$minor),
        start_time = Sys.time(),
        end_time = NULL,
        duration_seconds = NULL,
        config_hash = digest::digest(
            normalize_config_for_hash(config),
            algo = "sha256"
        ),
        n_plants = length(plant_ids),
        plant_ids = plant_ids,
        plant_status = plant_status,
        parallel = parallel,
        status = "running"
    )
}

#' Atualiza Status de Uma Usina no Registro de Proveniencia
#'
#' Modifica o status de uma usina especifica dentro do registro de
#' proveniencia. Como listas em R sao copy-on-modify, retorna a
#' lista atualizada.
#'
#' @param provenance lista de proveniencia criada por [create_provenance()]
#' @param id_usina character escalar, identificador da usina
#' @param status character escalar: `"completed"`, `"failed"` ou `"skipped"`
#'
#' @return lista de proveniencia com o status da usina atualizado
#'
#' @examples
#' cfg <- list(ids_usinas = c("USI1", "USI2"), janela = c("2025-07-01", "2025-09-30"))
#' prov <- create_provenance(cfg, "train", FALSE)
#' prov <- update_plant_status(prov, "USI1", "completed")
#'
#' @export
update_plant_status <- function(provenance, id_usina, status) {
    valid_status <- c("completed", "failed", "skipped")
    stopifnot(
        is.list(provenance),
        is.character(id_usina), length(id_usina) == 1L,
        is.character(status), length(status) == 1L,
        status %in% valid_status
    )
    provenance$plant_status[[id_usina]] <- status
    provenance
}

#' Finaliza Registro de Proveniencia
#'
#' Marca o fim da execucao, computa a duracao e define o status final.
#'
#' @param provenance lista de proveniencia criada por [create_provenance()]
#' @param status character escalar, `"completed"` ou `"failed"`
#'
#' @return lista de proveniencia finalizada com `end_time`,
#'   `duration_seconds` e `status` preenchidos
#'
#' @examples
#' cfg <- list(ids_usinas = "USI1", janela = c("2025-07-01", "2025-09-30"))
#' prov <- create_provenance(cfg, "train", FALSE)
#' prov <- finalize_provenance(prov, "completed")
#'
#' @export
finalize_provenance <- function(provenance, status = "completed") {
    stopifnot(
        is.list(provenance),
        status %in% c("completed", "failed")
    )
    provenance$end_time <- Sys.time()
    provenance$duration_seconds <- as.numeric(
        difftime(provenance$end_time, provenance$start_time, units = "secs")
    )
    provenance$status <- status
    provenance
}

#' Escreve Registro de Proveniencia em JSON
#'
#' Serializa o registro de proveniencia como JSON e escreve em disco.
#' Converte timestamps `POSIXct` para strings ISO 8601 antes da
#' serializacao. Envolvido em `tryCatch` para nunca interromper o
#' pipeline -- falhas de escrita geram apenas um aviso no log.
#'
#' @param provenance lista de proveniencia (preferencialmente finalizada)
#' @param output_dir character, diretorio de saida
#'
#' @return caminho do arquivo escrito (invisivelmente)
#'
#' @examples
#' \dontrun{
#' cfg <- list(ids_usinas = "USI1", janela = c("2025-07-01", "2025-09-30"))
#' prov <- create_provenance(cfg, "train", FALSE)
#' prov <- finalize_provenance(prov, "completed")
#' write_provenance(prov, tempdir())
#' }
#'
#' @export
write_provenance <- function(provenance, output_dir) {
    lg <- lgr::get_logger("mhpfv")

    filename <- paste0("provenance-", provenance$run_id, ".json")
    filepath <- file.path(output_dir, filename)

    tryCatch({
        if (!dir.exists(output_dir)) {
            dir.create(output_dir, recursive = TRUE)
        }

        prov_json <- format_provenance_timestamps(provenance)
        json_str <- jsonlite::toJSON(
            prov_json, pretty = TRUE, auto_unbox = TRUE, null = "null"
        )
        writeLines(json_str, filepath)

        lg$info("Proveniencia escrita em: %s", filepath)
    }, error = function(e) {
        lg$warn(
            "Falha ao escrever proveniencia em '%s': %s",
            filepath, conditionMessage(e)
        )
    })

    invisible(filepath)
}

format_provenance_timestamps <- function(provenance) {
    provenance$start_time <- format(provenance$start_time, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    if (!is.null(provenance$end_time)) {
        provenance$end_time <- format(provenance$end_time, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    }
    provenance
}

#' Escreve Checkpoint de Execucao
#'
#' Persiste o estado atual da execucao em disco para permitir retomada em
#' caso de falha. O arquivo e escrito como `checkpoint-{run_id}.json` no
#' diretorio informado. Falhas de I/O geram apenas um aviso no log e nao
#' interrompem o pipeline.
#'
#' @param provenance lista de proveniencia criada por [create_provenance()]
#' @param output_dir character, diretorio onde o checkpoint sera gravado
#'
#' @return caminho do arquivo gravado (invisivelmente)
#'
#' @export
write_checkpoint <- function(provenance, output_dir) {
    lg <- lgr::get_logger("mhpfv")
    filename <- paste0("checkpoint-", provenance$run_id, ".json")
    filepath <- file.path(output_dir, filename)

    tryCatch({
        if (!dir.exists(output_dir)) {
            dir.create(output_dir, recursive = TRUE)
        }
        prov_json <- format_provenance_timestamps(provenance)
        json_str <- jsonlite::toJSON(
            prov_json, pretty = TRUE, auto_unbox = TRUE, null = "null"
        )
        writeLines(json_str, filepath)
    }, error = function(e) {
        lg$warn("Falha ao escrever checkpoint: %s", conditionMessage(e))
    })

    invisible(filepath)
}

#' Le Checkpoint Valido do Diretorio
#'
#' Busca o checkpoint mais recente no diretorio e valida o hash da
#' configuracao atual. Retorna `NULL` se nenhum checkpoint valido for
#' encontrado, se o arquivo estiver corrompido ou se o hash divergir.
#'
#' @param output_dir character, diretorio onde procurar checkpoints
#' @param config lista com a configuracao atual do pipeline
#'
#' @return lista de proveniencia do checkpoint, ou `NULL` se nenhum valido
#'
#' @export
read_checkpoint <- function(output_dir, config) {
    lg <- lgr::get_logger("mhpfv")

    files <- list.files(
        output_dir, pattern = "^checkpoint-.*\\.json$", full.names = TRUE
    )

    if (length(files) == 0L) return(NULL)

    newest <- files[which.max(file.mtime(files))]

    checkpoint <- tryCatch(
        jsonlite::fromJSON(newest, simplifyVector = FALSE),
        error = function(e) {
            lg$warn(
                "Checkpoint corrompido em '%s': %s",
                newest, conditionMessage(e)
            )
            NULL
        }
    )

    if (is.null(checkpoint)) return(NULL)

    current_hash <- digest::digest(
        normalize_config_for_hash(config),
        algo = "sha256"
    )

    if (!identical(checkpoint$config_hash, current_hash)) {
        lg$warn(
            paste0(
                "Checkpoint ignorado: hash da configuracao divergente ",
                "(checkpoint: %s, atual: %s)"
            ),
            checkpoint$config_hash, current_hash
        )
        return(NULL)
    }

    lg$info("Checkpoint valido encontrado: %s", checkpoint$run_id)
    checkpoint
}

#' Retorna Usinas Pendentes de um Checkpoint
#'
#' Filtra o campo `plant_status` do checkpoint e retorna os IDs das usinas
#' cujo status nao seja `"completed"`.
#'
#' @param checkpoint lista de proveniencia lida por [read_checkpoint()]
#'
#' @return character vector com os IDs das usinas pendentes
#'
#' @export
get_pending_plants <- function(checkpoint) {
    statuses <- checkpoint$plant_status
    names(statuses)[vapply(statuses, function(s) s != "completed", logical(1L))]
}

#' Salva Resultado Intermediario de Uma Usina
#'
#' Grava o resultado de processamento de uma usina como arquivo RDS para
#' permitir retomada em modo predict. Falhas de I/O geram apenas um aviso
#' no log e nao interrompem o pipeline.
#'
#' @param result lista com resultado da usina (`com_cortes`, `sem_cortes`)
#' @param id_usina character escalar, identificador da usina
#' @param output_dir character, diretorio de saida
#'
#' @return caminho do arquivo gravado (invisivelmente)
write_plant_result <- function(result, id_usina, output_dir) {
    lg <- lgr::get_logger("mhpfv")
    filepath <- file.path(output_dir, paste0("plant-result-", id_usina, ".rds"))

    tryCatch(
        saveRDS(result, filepath),
        error = function(e) {
            lg$warn(
                "Falha ao salvar resultado da usina '%s': %s",
                id_usina, conditionMessage(e)
            )
        }
    )

    invisible(filepath)
}

#' Le Resultado Intermediario de Uma Usina
#'
#' Carrega o resultado de processamento de uma usina previamente salvo por
#' [write_plant_result()]. Retorna `NULL` se o arquivo nao existir ou
#' estiver corrompido.
#'
#' @param id_usina character escalar, identificador da usina
#' @param output_dir character, diretorio de saida
#'
#' @return lista com resultado da usina, ou `NULL`
read_plant_result <- function(id_usina, output_dir) {
    lg <- lgr::get_logger("mhpfv")
    filepath <- file.path(output_dir, paste0("plant-result-", id_usina, ".rds"))

    if (!file.exists(filepath)) return(NULL)

    tryCatch(
        readRDS(filepath),
        error = function(e) {
            lg$warn(
                "Resultado intermediario corrompido para usina '%s': %s",
                id_usina, conditionMessage(e)
            )
            NULL
        }
    )
}

#' Remove Arquivos de Checkpoint e Resultados Intermediarios
#'
#' Apaga o arquivo de checkpoint e todos os arquivos `plant-result-*.rds`
#' do diretorio informado. Chamada apenas apos conclusao bem-sucedida do
#' pipeline. Falhas de remocao geram aviso no log e nao propagam erro.
#'
#' @param output_dir character, diretorio de saida
#' @param run_id character escalar, ID da execucao. Se `NULL`, remove todos
#'   os checkpoints encontrados
#'
#' @return `invisible(NULL)`
plant_error <- function(id_usina, error) {
    stopifnot(
        is.character(id_usina), length(id_usina) == 1L,
        inherits(error, "condition") || is.character(error)
    )
    msg <- if (inherits(error, "condition")) conditionMessage(error) else error
    structure(
        list(id_usina = id_usina, error = msg),
        class = "plant_error"
    )
}

is_plant_error <- function(x) {
    inherits(x, "plant_error")
}

cleanup_checkpoint <- function(output_dir, run_id = NULL) {
    lg <- lgr::get_logger("mhpfv")

    cp_pattern <- if (!is.null(run_id)) {
        paste0("^checkpoint-", run_id, "\\.json$")
    } else {
        "^checkpoint-.*\\.json$"
    }

    all_files <- c(
        list.files(output_dir, pattern = cp_pattern, full.names = TRUE),
        list.files(output_dir, pattern = "^plant-result-.*\\.rds$", full.names = TRUE)
    )

    if (length(all_files) > 0L) {
        tryCatch(
            file.remove(all_files),
            error = function(e) {
                lg$warn(
                    "Falha ao remover arquivos de checkpoint: %s",
                    conditionMessage(e)
                )
            }
        )
        lg$debug("Removidos %d arquivos de checkpoint/intermediarios", length(all_files))
    }

    invisible(NULL)
}
