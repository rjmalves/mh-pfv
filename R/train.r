train_main <- function(args) {
    # Define a ordem de prioridade das fontes a partir do argumento
    conn <- conectamock_pfv(args$input)

    v_usinas <- args$ids_usinas
    dt_usinas <- get_usinas(conn, id_usina = v_usinas)

    dataset <- get_dataset(args, conn)

    # Realiza o treinamento para cada usina
    models <- lapply(v_usinas, ajustar_usina)

    # Exporta o artefato treinado para cada usina
    lapply(seq_along(v_usinas), function(i) {
        iu <- v_usinas[i]
        model <- models[[i]]

        write_model_artifact(model, iu, args$artifact)
    })
}

ajustar_usina <- function(iu) {
    list(
        id_usina = iu,
        parametro_exemplo = 42
    )
}
