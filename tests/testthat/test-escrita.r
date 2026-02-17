test_that("write_melhor_historico_geracao writes parquet file", {
    out_dir <- withr::local_tempdir()

    dt <- data.table::data.table(
        id_fonte_observacao = rep("Consis", 4),
        id_usina = rep("USI1", 4),
        data_hora_observacao = as.POSIXct(
            c(
                "2025-01-01 00:00:00", "2025-01-01 00:30:00",
                "2025-01-01 01:00:00", "2025-01-01 01:30:00"
            ),
            tz = "UTC"
        ),
        valor = c(0.0, 1.5, 3.0, 2.0),
        status = c(1L, 2L, 1L, 3L)
    )

    expect_no_error(write_melhor_historico_geracao(dt, out_dir))

    outfile <- file.path(out_dir, "melhor_historico_geracao.parquet")
    expect_true(file.exists(outfile))
    expect_true(file.size(outfile) > 0)
})

test_that("write_melhor_historico_geracao validates schema", {
    out_dir <- withr::local_tempdir()

    dt_bad <- data.table::data.table(
        wrong_col = "bad",
        valor = 1.0
    )

    expect_error(write_melhor_historico_geracao(dt_bad, out_dir))
})

test_that("write_melhor_historico_geracao_sem_cortes writes parquet file", {
    out_dir <- withr::local_tempdir()

    dt <- data.table::data.table(
        id_fonte_observacao = rep("Consis", 4),
        id_usina = rep("USI1", 4),
        data_hora_observacao = as.POSIXct(
            c(
                "2025-01-01 00:00:00", "2025-01-01 00:30:00",
                "2025-01-01 01:00:00", "2025-01-01 01:30:00"
            ),
            tz = "UTC"
        ),
        valor = c(0.0, 1.5, 3.0, 2.0),
        status = c(1L, 2L, 1L, 3L)
    )

    expect_no_error(write_melhor_historico_geracao_sem_cortes(dt, out_dir))

    outfile <- file.path(out_dir, "melhor_historico_geracao_sem_cortes.parquet")
    expect_true(file.exists(outfile))
    expect_true(file.size(outfile) > 0)
})

test_that("write_melhor_historico_geracao_sem_cortes validates schema", {
    out_dir <- withr::local_tempdir()

    dt_bad <- data.table::data.table(
        wrong_col = "bad",
        valor = 1.0
    )

    expect_error(write_melhor_historico_geracao_sem_cortes(dt_bad, out_dir))
})
