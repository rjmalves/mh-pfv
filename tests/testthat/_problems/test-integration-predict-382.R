# Extracted from test-integration-predict.r:382

# test -------------------------------------------------------------------------
temp_output <- withr::local_tempdir()
config <- gen_config(
        mode = "predict",
        ids_usinas = c("USI1", "USI_FAIL", "USI3"),
        janela = list("2025-07-01", "2025-09-30")
    )
config$output <- temp_output
config$input <- temp_output
config$artifact <- temp_output
datas <- gen_default_datas(n_days = 3L)
make_result <- function(iu) {
        n <- length(datas)
        list(
            com_cortes = data.table::data.table(
                id_fonte_observacao = "Consis", id_usina = iu,
                data_hora_observacao = datas, valor = rep(10.0, n),
                status = rep(0L, n)
            ),
            sem_cortes = data.table::data.table(
                id_fonte_observacao = "Consis", id_usina = iu,
                data_hora_observacao = datas, valor = rep(10.0, n),
                status = rep(0L, n)
            )
        )
    }
mockery::stub(predict_main, "conectamock_pfv", function(...) NULL)
mockery::stub(predict_main, "get_usinas",
        function(...) gen_usinas(ids = c("USI1", "USI_FAIL", "USI3")))
mockery::stub(predict_main, "get_dataset", function(...) list(
        ger_obs = data.table::data.table(),
        corte = data.table::data.table(),
        irrad_prev = data.table::data.table(),
        mhg = data.table::data.table(),
        mhg_sem_cortes = data.table::data.table()))
mockery::stub(predict_main, "associa_nwp_usina",
        function(...) data.table::data.table())
mockery::stub(predict_main, "adicionar_passo_previsao",
        function(x, ...) x)
mockery::stub(predict_main, "processar_usina", function(iu, ...) {
        if (iu == "USI_FAIL") stop("simulated failure")
        make_result(iu)
    })
mockery::stub(predict_main, "write_melhor_historico_geracao",
        function(...) invisible(NULL))
mockery::stub(predict_main, "write_melhor_historico_geracao_sem_cortes",
        function(...) invisible(NULL))
mockery::stub(predict_main, "coloca_na_antes_inicio",
        function(dt, ...) dt)
expect_no_error(predict_main(config))
prov_files <- list.files(temp_output, "^provenance-.*\\.json$",
        full.names = TRUE)
expect_equal(length(prov_files), 1L)
parsed <- jsonlite::fromJSON(prov_files[1], simplifyVector = FALSE)
expect_equal(parsed$plant_status$USI1, "completed")
expect_equal(parsed$plant_status$USI_FAIL, "failed")
expect_equal(parsed$plant_status$USI3, "completed")
expect_equal(parsed$status, "failed")
report_files <- list.files(temp_output, "^health-report-.*\\.json$",
        full.names = TRUE)
expect_equal(length(report_files), 1L)
