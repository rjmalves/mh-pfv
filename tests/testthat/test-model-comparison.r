test_that("compare_artifacts", {
    f <- compare_artifacts
    expect_true(is.function(f))

    test_that("artefatos identicos produzem diff zero", {
        art <- gen_model_artifact()
        result <- f(art, art)

        expect_equal(result$id_usina_a, "USI1")
        expect_equal(result$id_usina_b, "USI1")
        expect_true(all(result$coefficient_diff$diff == 0))
        expect_equal(result$summary$n_changed_slots, 0L)
        expect_equal(length(result$metadata_diff), 0L)
    })

    test_that("coeficientes diferentes sao detectados", {
        art_a <- gen_model_artifact()
        art_b <- gen_model_artifact()
        art_b$parametros$a <- art_b$parametros$a * 1.5

        result <- f(art_a, art_b)

        expect_true(all(result$coefficient_diff$diff != 0))
        expect_equal(
            result$summary$n_changed_slots,
            nrow(art_a$parametros)
        )
        expect_true(result$summary$mean_diff > 0)
        expect_true(result$summary$max_diff > 0)
    })

    test_that("novos NAs sao contabilizados", {
        art_a <- gen_model_artifact()
        art_b <- gen_model_artifact()
        art_b$parametros$a[1:3] <- NA

        result <- f(art_a, art_b)

        expect_equal(result$summary$n_new_na, 3L)
    })

    test_that("slots recuperados sao contabilizados", {
        art_a <- gen_model_artifact()
        art_b <- gen_model_artifact()
        art_a$parametros$a[c(2, 5)] <- NA

        result <- f(art_a, art_b)

        expect_equal(result$summary$n_recovered, 2L)
    })

    test_that("diferencas de metadados sao listadas", {
        art_a <- gen_model_artifact()
        art_b <- gen_model_artifact()
        art_b$metadata$config_hash <- "hash-diferente"

        result <- f(art_a, art_b)

        diff_fields <- vapply(
            result$metadata_diff, `[[`, character(1L), "field"
        )
        expect_true("config_hash" %in% diff_fields)
    })

    test_that("artefato legado sem metadata gera nota", {
        art_legacy <- gen_model_artifact_legacy()
        art_new <- gen_model_artifact()

        result <- f(art_legacy, art_new)

        expect_true(grepl("nao disponiveis", result$metadata_diff$note))
        expect_true(is.data.table(result$coefficient_diff))
        expect_true(nrow(result$coefficient_diff) > 0L)
    })

    test_that("tipos diferentes geram warning", {
        art_a <- gen_model_artifact()
        art_b <- gen_model_artifact()
        art_b$metadata$type <- "outro_modelo"

        expect_warning(f(art_a, art_b), "tipos diferentes")
    })

    test_that("grids de horarios diferentes fazem outer join", {
        art_a <- gen_model_artifact()
        art_b <- gen_model_artifact()

        extra_row <- data.frame(a = 0.99, b = 0, row.names = "19:00")
        art_b$parametros <- rbind(art_b$parametros, extra_row)

        result <- f(art_a, art_b)

        expect_true("19:00" %in% result$coefficient_diff$slot)
        row_19 <- result$coefficient_diff[slot == "19:00"]
        expect_true(is.na(row_19$a_artifact_a))
        expect_equal(row_19$a_artifact_b, 0.99)
    })

    test_that("pct_change e NA quando base e zero", {
        art_a <- gen_model_artifact()
        art_b <- gen_model_artifact()
        art_a$parametros$a[1] <- 0

        result <- f(art_a, art_b)

        row_zero <- result$coefficient_diff[slot == rownames(art_a$parametros)[1]]
        expect_true(is.na(row_zero$pct_change))
    })

    test_that("rejeita entrada nao-lista", {
        expect_error(f("nao_lista", gen_model_artifact()), "lista")
        expect_error(f(gen_model_artifact(), 42), "lista")
    })

    test_that("rejeita artefato sem parametros", {
        expect_error(
            f(list(id_usina = "X"), gen_model_artifact()),
            "parametros"
        )
    })
})

test_that("compare_artifact_files", {
    f <- compare_artifact_files
    expect_true(is.function(f))

    test_that("roundtrip via arquivos RDS produz resultado identico", {
        tmpdir <- withr::local_tempdir()
        art_a <- gen_model_artifact("USIA")
        art_b <- gen_model_artifact("USIB")
        art_b$parametros$a <- art_b$parametros$a * 2

        path_a <- file.path(tmpdir, "art_a.rds")
        path_b <- file.path(tmpdir, "art_b.rds")
        saveRDS(art_a, path_a)
        saveRDS(art_b, path_b)

        result_files <- f(path_a, path_b)
        result_direct <- compare_artifacts(art_a, art_b)

        expect_equal(result_files, result_direct)
    })

    test_that("arquivo inexistente gera erro com caminho", {
        expect_error(
            f("/caminho/inexistente.rds", "/outro/inexistente.rds"),
            "inexistente.rds"
        )
    })
})

test_that("format_comparison", {
    f <- format_comparison
    expect_true(is.function(f))

    test_that("produz character vector nao vazio", {
        art_a <- gen_model_artifact()
        art_b <- gen_model_artifact()
        art_b$parametros$a <- art_b$parametros$a * 1.1
        comp <- compare_artifacts(art_a, art_b)

        result <- f(comp)

        expect_true(is.character(result))
        expect_true(length(result) > 0L)
    })

    test_that("contem secoes esperadas", {
        art_a <- gen_model_artifact()
        art_b <- gen_model_artifact()
        art_b$parametros$a <- art_b$parametros$a * 1.1
        comp <- compare_artifacts(art_a, art_b)

        result <- f(comp)
        joined <- paste(result, collapse = "\n")

        expect_true(grepl("Comparacao de Artefatos", joined))
        expect_true(grepl("Diferencas de Metadados", joined))
        expect_true(grepl("Resumo de Coeficientes", joined))
        expect_true(grepl("Maiores Diferencas", joined))
    })
})

test_that("compare_multiple_artifacts", {
    f <- compare_multiple_artifacts
    expect_true(is.function(f))

    test_that("3 artefatos produzem 3 comparacoes pairwise", {
        arts <- list(
            gen_model_artifact("USI1"),
            gen_model_artifact("USI2"),
            gen_model_artifact("USI3")
        )

        result <- f(arts, labels = c("A", "B", "C"))

        expect_equal(length(result), 3L)
        expect_true("A_vs_B" %in% names(result))
        expect_true("A_vs_C" %in% names(result))
        expect_true("B_vs_C" %in% names(result))
    })

    test_that("rejeita menos de 2 artefatos", {
        expect_error(
            f(list(gen_model_artifact())),
            "pelo menos 2"
        )
    })
})
