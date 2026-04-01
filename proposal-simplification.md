# Proposta de simplificacao: provenance e model strategy

Documento tecnico com diagnostico do estado atual e proposta de refatoracao para
as areas de provenance/metrics e model strategy do pacote mhpfv.

## 1. Provenance: substituir lista copy-on-modify por environment

### Diagnostico

O provenance e o metrics hoje sao listas simples atualizadas via `<<-` dentro de
closures passadas a `lapply`. O mesmo antipadrao aparece em quatro pontos:

| Arquivo     | Linhas  | Variavel                | Contexto                          |
| ----------- | ------- | ----------------------- | --------------------------------- |
| `train.r`   | 130-131 | `metrics`               | `lapply` serial, timing por usina |
| `train.r`   | 141-148 | `provenance`, `metrics` | `lapply` pos-paralelismo          |
| `predict.r` | 124-125 | `metrics`               | `lapply` serial, timing por usina |
| `predict.r` | 142-143 | `provenance`            | `for` pos-paralelismo             |

O `<<-` funciona, mas cria acoplamento implicito entre o corpo do loop e o
escopo pai. Cada `update_plant_status` retorna uma lista nova (copy-on-modify
do R), o que gera N copias para N usinas -- irrelevante em escala atual, mas
semanticamente errado para um acumulador mutavel.

O metrics sofre do mesmo problema: `record_plant_timing`, `record_plant_data_volume`
e `record_model_quality` retornam listas novas atribuidas via `<<-`.

### Proposta

Substituir as listas `provenance` e `metrics` por R environments com semantica
de referencia. O environment e mutado in-place, eliminando `<<-` e copias.

#### Provenance como environment

```r
create_provenance <- function(config, mode, parallel = FALSE) {
    run_id <- generate_run_id(mode)
    plant_ids <- config$ids_usinas

    prov <- new.env(parent = emptyenv())
    prov$run_id <- run_id
    prov$mode <- mode
    prov$package_version <- as.character(utils::packageVersion("mhpfv"))
    prov$r_version <- paste0(R.version$major, ".", R.version$minor)
    prov$start_time <- Sys.time()
    prov$end_time <- NULL
    prov$duration_seconds <- NULL
    prov$config_hash <- digest::digest(
        normalize_config_for_hash(config), algo = "sha256"
    )
    prov$n_plants <- length(plant_ids)
    prov$plant_ids <- plant_ids
    prov$plant_status <- new.env(parent = emptyenv())
    for (iu in plant_ids) prov$plant_status[[iu]] <- "pending"
    prov$parallel <- parallel
    prov$status <- "running"

    prov
}

update_plant_status <- function(provenance, id_usina, status) {
    valid_status <- c("completed", "failed", "skipped")
    stopifnot(
        is.environment(provenance),
        is.character(id_usina), length(id_usina) == 1L,
        status %in% valid_status
    )
    provenance$plant_status[[id_usina]] <- status
    invisible(provenance)
}

finalize_provenance <- function(provenance, status = "completed") {
    provenance$end_time <- Sys.time()
    provenance$duration_seconds <- as.numeric(
        difftime(provenance$end_time, provenance$start_time, units = "secs")
    )
    provenance$status <- status
    invisible(provenance)
}
```

`plant_status` tambem e um environment -- mutacoes por usina sao O(1) sem
copiar a lista inteira.

#### Metrics como environment

Mesma abordagem. `create_metrics` retorna um environment, `record_plant_*`
muta in-place:

```r
create_metrics <- function(run_id, mode) {
    m <- new.env(parent = emptyenv())
    m$run_id <- run_id
    m$mode <- mode
    m$created_at <- NULL
    m$pipeline <- list()
    m$plants <- new.env(parent = emptyenv())
    m
}

record_plant_timing <- function(metrics, id_usina, duration_secs) {
    if (is.null(metrics$plants[[id_usina]])) {
        metrics$plants[[id_usina]] <- list()
    }
    metrics$plants[[id_usina]]$duration_seconds <- duration_secs
    invisible(metrics)
}
```

#### Impacto no pipeline train/predict

O loop pos-paralelismo em `train.r:138-151` perde os `<<-`:

```r
# Antes
lapply(seq_along(v_usinas), function(i) {
    write_model_artifact(models[[i]], v_usinas[i], args$artifact)
    provenance <<- update_plant_status(provenance, v_usinas[i], "completed")
    if ("metadata" %in% names(models[[i]])) {
        metrics <<- record_model_quality(metrics, v_usinas[i], models[[i]]$metadata)
    }
    if (resume) write_checkpoint(provenance, args$artifact)
})

# Depois
lapply(seq_along(v_usinas), function(i) {
    write_model_artifact(models[[i]], v_usinas[i], args$artifact)
    update_plant_status(provenance, v_usinas[i], "completed")
    if ("metadata" %in% names(models[[i]])) {
        record_model_quality(metrics, v_usinas[i], models[[i]]$metadata)
    }
    if (resume) write_checkpoint(provenance, args$artifact)
})
```

O `on.exit` continua funcionando como esta -- as variaveis `provenance` e
`metrics` referenciam o mesmo environment, que ja foi mutado quando o handler
executa.

O loop serial (`train.r:117-134`) tambem perde o `<<-` do metrics:

```r
# Antes
models <- lapply(v_usinas, function(iu) {
    t0 <- proc.time()[["elapsed"]]
    result <- ajustar_usina(iu, ...)
    metrics <<- record_plant_timing(metrics, iu, round(proc.time()[["elapsed"]] - t0, 2L))
    result
})

# Depois
models <- lapply(v_usinas, function(iu) {
    t0 <- proc.time()[["elapsed"]]
    result <- ajustar_usina(iu, ...)
    record_plant_timing(metrics, iu, round(proc.time()[["elapsed"]] - t0, 2L))
    result
})
```

#### Serializacao para JSON

Environments nao sao serializaveis diretamente com `jsonlite::toJSON`. A funcao
de escrita converte para lista no momento da serializacao:

```r
prov_as_list <- function(provenance) {
    out <- as.list(provenance)
    out$plant_status <- as.list(provenance$plant_status)
    out
}
```

O JSON de saida permanece identico ao formato atual. Nenhum consumidor externo
e afetado.

#### Checkpoints

Checkpoints ja sao escritos como JSON via `write_checkpoint`, que recebe o
provenance e serializa. A unica mudanca e aplicar `prov_as_list()` antes de
`jsonlite::toJSON`. A leitura via `read_checkpoint` continua retornando uma
lista (e uma lista de fato -- checkpoints sao snapshots lidos do disco, nao
environments vivos).

#### Caso paralelo (future_lapply)

Workers em `multisession` rodam em processos separados e nao podem mutar o
environment do pai. O padrao atual permanece: workers retornam resultados, o
loop sequencial pos-batch faz as mutacoes no environment. A diferenca e que
o loop sequencial nao precisa mais de `<<-`.

Para `multicore` (fork), environments compartilhados seriam possiveis mas
frageis. Nao recomendo depender disso.

### Riscos e mitigacao

| Risco                           | Mitigacao                                                                 |
| ------------------------------- | ------------------------------------------------------------------------- |
| Environments nao serializaveis  | Conversao `prov_as_list()` nos pontos de escrita; JSON identico           |
| Mutacao acidental fora do loop  | Mesma superfice de ataque que o `<<-` atual; ambos dependem de disciplina |
| Testes existentes assumem lista | Adaptar construtores nos testes; assercoes com `$` funcionam igual        |

### Escopo de arquivos afetados

| Arquivo                                 | Tipo de mudanca                                                                                                      |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `R/provenance.r`                        | Reescrever `create_provenance`, `update_plant_status`, `finalize_provenance`, `write_provenance`, `write_checkpoint` |
| `R/metrics.r`                           | Reescrever `create_metrics`, `record_plant_*`, `finalize_metrics`, `write_metrics`                                   |
| `R/train.r`                             | Remover todos `<<-`                                                                                                  |
| `R/predict.r`                           | Remover todos `<<-`                                                                                                  |
| `R/health-report.r`                     | Ajustar `build_plant_reports` para ler de environment                                                                |
| `tests/testthat/test-provenance.r`      | Adaptar assercoes (environments vs listas)                                                                           |
| `tests/testthat/test-metrics.r`         | Idem                                                                                                                 |
| `tests/testthat/test-pipeline-resume.r` | Idem                                                                                                                 |
| `tests/testthat/test-health-report.r`   | Idem                                                                                                                 |

## 2. Model strategy: despacho por string, modelo com classe propria

### Diagnostico

O sistema atual tem tres problemas concretos:

**Problema 1: `predict_model` recebe `strategy` e `model` redundantemente.**

O `strategy` serve exclusivamente para dispatch S3. O `model` (um `data.frame`
sem classe) carrega os dados. O strategy e passado por tres niveis de funcao so
para chegar ao ponto de dispatch:

```
predict_main(strategy)
  -> processar_usina(strategy)
    -> preenche_geracao_unit(strategy, model)
      -> predict_model(strategy, model$parametros, ...)
```

Se o modelo carregasse sua propria classe, `strategy` desapareceria de toda a
cadeia predict.

**Problema 2: o objeto strategy e stateless -- existe so para dispatch.**

```r
strategy <- linear_regression_strategy()
# strategy$type = "linear_regression"
# strategy$params = list()  (vazio -- ninguem usa)
```

Construir um objeto S3 com classe dupla para fazer o papel de uma string e
overengineering. O `params` nunca e usado pela regressao linear e nao ha
segundo modelo implementado que justifique a generalidade.

**Problema 3: `fit_model` retorna um `data.frame` nu.**

O resultado do ajuste nao carrega tipo. Ao carregar o artefato do disco no
predict, o campo `metadata$type` existe mas nunca e usado para reconstruir
a classe. O dispatch depende do strategy que foi passado por fora.

### Proposta

Eliminar `model_strategy` como classe. `fit_model` recebe uma string e retorna
um modelo com classe propria. `predict` e `model_metadata` despacham no modelo.

#### Novo `model-strategy.r` (contrato generico)

```r
fit_model <- function(strategy, dty, dtx, dty_bruta, ...) {
    stopifnot(is.character(strategy), length(strategy) == 1L)
    fn_name <- paste0("fit_", strategy)
    ns <- asNamespace("mhpfv")
    fn <- get0(fn_name, envir = ns, mode = "function", inherits = FALSE)
    if (is.null(fn)) {
        stop("fit_model nao implementado para estrategia '", strategy, "'")
    }
    fn(dty = dty, dtx = dtx, dty_bruta = dty_bruta, ...)
}

predict_model <- function(model, ...) {
    UseMethod("predict_model")
}

predict_model.default <- function(model, ...) {
    stop("predict_model nao implementado para modelo de classe '",
        paste(class(model), collapse = "/"), "'")
}

model_metadata <- function(model, ...) {
    UseMethod("model_metadata")
}

model_metadata.default <- function(model, ...) {
    stop("model_metadata nao implementado para modelo de classe '",
        paste(class(model), collapse = "/"), "'")
}
```

`fit_model` nao e mais um generico S3 -- e uma funcao regular que despacha por
convencao de nome (`fit_<strategy>`). A resolucao usa
`get0(fn_name, envir = ns, mode = "function", inherits = FALSE)` com busca
explicita no namespace do pacote:

- `asNamespace("mhpfv")` retorna o environment do namespace do pacote.
- `inherits = FALSE` impede que a busca suba para imports, base, global env ou
  qualquer outro pacote no search path.
- `get0` retorna `NULL` se nao encontrar, sem levantar erro -- uma unica chamada
  atomica substitui o par `exists()` + `match.fun()`.
- Uma funcao `fit_xyz` definida pelo usuario no global env ou em outro pacote
  **nunca** sera encontrada.

`predict_model` e `model_metadata` continuam como genericos S3, mas despacham na
classe do **modelo**, nao da strategy. O dispatch S3 via `UseMethod` usa a
tabela de metodos registrados no NAMESPACE, que tambem e scoped ao pacote.

#### Novo `model-linear-regression.r`

```r
fit_linear_regression <- function(dty, dtx, dty_bruta, ...) {
    params <- ajusta_regressao_ger_irrad(dty = dty, dtx = dtx, dty_bruta = dty_bruta)
    structure(
        list(parametros = params),
        class = "linear_regression_model"
    )
}

predict_model.linear_regression_model <- function(model, df_ger_usi,
    df_irrad_prev, lim_dados, ...) {
    substitui_por_estimativas(
        df_ger_usi = df_ger_usi,
        df_irrad_prev = df_irrad_prev,
        regressoes = model$parametros,
        lim_dados = lim_dados
    )
}

model_metadata.linear_regression_model <- function(model, ...) {
    params <- model$parametros
    stopifnot(is.data.frame(params), "a" %in% names(params))
    list(
        type = "linear_regression",
        n_slots = nrow(params),
        n_valid_slots = sum(!is.na(params$a)),
        timestamp = Sys.time()
    )
}
```

`fit_linear_regression` retorna um objeto com classe unica
`"linear_regression_model"`. `predict_model` e `model_metadata` despacham
nessa classe -- sem strategy.

#### Artefato

O artefato passa a guardar o modelo com classe diretamente. Artefatos antigos
(com `$parametros` como `data.frame` nu) nao precisam de retrocompatibilidade
-- o projeto esta em estagio inicial e os artefatos podem ser regenerados.

```r
# artifact.r
build_model_artifact <- function(id_usina, model, config) {
    metadata <- model_metadata(model)
    metadata$package_version <- as.character(utils::packageVersion("mhpfv"))
    metadata$config_hash <- digest::digest(
        normalize_config_for_hash(config), algo = "sha256"
    )
    list(
        id_usina = id_usina,
        model = model,
        metadata = metadata
    )
}
```

O campo `$model` e o objeto com classe `"linear_regression_model"` retornado
por `fit_linear_regression`. Ao carregar do disco via `readRDS`, R preserva a
classe S3, entao `predict_model` despacha corretamente sem reconstrucao.

#### Impacto no pipeline

**Train** -- `ajustar_usina` e `train_main`:

```r
# Antes
train_main <- function(args, strategy = linear_regression_strategy(), ...)
ajustar_usina <- function(iu, ..., strategy = linear_regression_strategy(), ...)
regressoes <- fit_model(strategy, dty, dtx, dty_bruta)
build_model_artifact(iu, regressoes, strategy, config)

# Depois
train_main <- function(args, strategy = "linear_regression", ...)
ajustar_usina <- function(iu, ..., strategy = "linear_regression", ...)
model <- fit_model(strategy, dty, dtx, dty_bruta)
build_model_artifact(iu, model, config)
```

O parametro `strategy` continua existindo em `train_main` e `ajustar_usina`
como **string** para controlar qual modelo ajustar. A diferenca e que agora
`fit_model` retorna um objeto com classe, e `build_model_artifact` recebe o
modelo (nao precisa da strategy separadamente).

**Predict** -- `strategy` desaparece de toda a cadeia:

```r
# Antes
predict_main <- function(args, strategy = linear_regression_strategy(), ...)
processar_usina <- function(iu, ..., strategy = linear_regression_strategy(), ...)
preenche_geracao_unit <- function(..., model, strategy = linear_regression_strategy())
predict_model(strategy, model = model$parametros, df_ger_usi, df_irrad_prev, lim_dados)

# Depois
predict_main <- function(args, ...)
processar_usina <- function(iu, ..., artifact_dir, ...)
preenche_geracao_unit <- function(..., model)
predict_model(model, df_ger_usi = df_ger_usi, df_irrad_prev = df_irrad_prev, lim_dados = lim_dados)
```

O `strategy` desaparece de `predict_main`, `processar_usina` e
`preenche_geracao_unit`. O modelo carregado do artefato ja sabe como se
prever. O `predict_model` passa a receber o modelo como primeiro argumento.

**cli.r** -- simplifica a criacao:

```r
# Antes
strategy <- linear_regression_strategy()
train_main(args, strategy = strategy, ...)

# Depois
train_main(args, strategy = "linear_regression", ...)
```

#### Eliminacoes

| Item                                                                               | Destino                                           |
| ---------------------------------------------------------------------------------- | ------------------------------------------------- |
| `new_model_strategy()`                                                             | Deletar                                           |
| `linear_regression_strategy()`                                                     | Deletar                                           |
| Classe `model_strategy`                                                            | Deletar                                           |
| `fit_model` como generico S3                                                       | Converter em funcao regular com dispatch por nome |
| Parametro `strategy` em `predict_main`, `processar_usina`, `preenche_geracao_unit` | Remover                                           |
| `build_artifact_metadata(strategy, model, config)`                                 | Substituir por `model_metadata(model)` + hash     |

#### NAMESPACE

```
# Remover
S3method(fit_model,linear_regression)
S3method(fit_model,model_strategy)

# Manter (com novo dispatch)
S3method(predict_model,linear_regression_model)
S3method(predict_model,default)
S3method(model_metadata,linear_regression_model)
S3method(model_metadata,default)

# Adicionar
export(fit_model)
export(fit_linear_regression)
```

### Riscos e mitigacao

| Risco                              | Mitigacao                                                                                                         |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Artefatos antigos incompativeis    | Regenerar artefatos com `--mode train` apos o deploy; projeto em estagio inicial                                  |
| Extensibilidade futura             | Adicionar novo modelo = 1 arquivo com `fit_<type>` + `predict_model.<type>_model` + `model_metadata.<type>_model` |
| `fit_model` perde dispatch S3      | Intencional: o input e uma string, nao um objeto. O dispatch por convencao de nome e mais explicito               |
| Assinatura de `predict_model` muda | Primeiro argumento passa de `strategy` para `model`. Buscar todas as chamadas                                     |

### Escopo de arquivos afetados

| Arquivo                                      | Tipo de mudanca                                                                                                                          |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `R/model-strategy.r`                         | Reescrever: `fit_model` como funcao regular, `predict_model`/`model_metadata` despacham no modelo                                        |
| `R/model-linear-regression.r`                | Reescrever: `fit_linear_regression` retorna objeto com classe; `predict_model` e `model_metadata` despacham em `linear_regression_model` |
| `R/artifact.r`                               | Simplificar: `build_model_artifact` recebe modelo (nao strategy); remover `build_artifact_metadata`                                      |
| `R/train.r`                                  | `strategy` vira string; `ajustar_usina` passa modelo para `build_model_artifact`                                                         |
| `R/predict.r`                                | Remover `strategy` de `predict_main`, `processar_usina`                                                                                  |
| `R/preenchimento-dados-faltantes.r`          | Remover `strategy` de `preenche_geracao_unit`; `predict_model` recebe modelo                                                             |
| `R/cli.r`                                    | String ao inves de `linear_regression_strategy()`                                                                                        |
| `NAMESPACE`                                  | Atualizar exports e S3methods                                                                                                            |
| `tests/testthat/test-model-strategy.r`       | Reescrever para nova API                                                                                                                 |
| `tests/testthat/test-strategy-integration.r` | Adaptar para dispatch no modelo                                                                                                          |
| `tests/testthat/test-integration-train.r`    | `strategy` vira string                                                                                                                   |
| `tests/testthat/test-integration-predict.r`  | Remover `strategy`                                                                                                                       |

## 3. Resiliencia per-plant: tryCatch no loop de processamento

### Diagnostico

Hoje, se `ajustar_usina` (train) ou `processar_usina` (predict) lanca um erro
para qualquer usina, o pipeline inteiro aborta. O problema existe nos tres
caminhos de execucao:

**Serial (`lapply`):** nenhum `tryCatch` envolve a chamada ao worker. O erro
propaga da funcao anonima para o `lapply`, que aborta. O vetor `models`/
`resultados_new` nunca e atribuido. O loop de pos-processamento (escrita de
artefatos, atualizacao de provenance, checkpoint) nunca executa.

**Paralelo (`future_lapply`):** por padrao, `future_lapply` re-lanca no
processo pai o primeiro erro de qualquer worker. Mesmo efeito: o vetor de
resultados nunca e atribuido.

**Consequencias concretas** (exemplo: 4 usinas A, B, C, D; B falha):

| Aspecto                      | Esperado                              | Real                                        |
| ---------------------------- | ------------------------------------- | ------------------------------------------- |
| Usina A (sucesso antes de B) | Artefato escrito, marcada "completed" | Artefato **nao** escrito, marcada "pending" |
| Usinas C, D                  | Executam normalmente                  | **Nunca executam**                          |
| Provenance                   | A=completed, B=failed, C/D=completed  | **Todas "pending"**, status geral "failed"  |
| Checkpoint                   | Escrito com status correto por usina  | **Nao existe**                              |
| Proximo `--resume`           | Pula A/C/D, retenta B                 | **Reroda tudo do zero**                     |

O `on.exit` handler escreve `provenance-{run_id}.json` com `status: "failed"`
e todas as usinas como `"pending"` -- zero informacao util sobre o que de fato
aconteceu.

### Proposta

Envolver a chamada ao worker em `tryCatch` dentro do `lapply`/`future_lapply`,
retornando um sentinel em caso de erro. O loop de pos-processamento distingue
sucesso de falha e atualiza provenance e checkpoint corretamente.

#### Sentinel de erro

```r
plant_error <- function(id_usina, error) {
    structure(
        list(id_usina = id_usina, error = conditionMessage(error)),
        class = "plant_error"
    )
}
```

#### Train serial

```r
models <- lapply(v_usinas, function(iu) {
    t0 <- proc.time()[["elapsed"]]
    result <- tryCatch(
        ajustar_usina(iu,
            dt_usinas = dt_usinas,
            dt_ger_obs = dataset$ger_obs,
            dt_irrad_prev_filt = dt_irrad_prev_filt,
            dt_corte_obs = dataset$corte,
            fonte = args$ordem_prioridade_fontes,
            fator_tolerancia = args$fator_tolerancia_limite_superior_geracao,
            strategy = strategy,
            config = args
        ),
        error = function(e) {
            lg$error("Falha no ajuste da usina %s: %s", iu, conditionMessage(e))
            plant_error(iu, e)
        }
    )
    record_plant_timing(metrics, iu, round(proc.time()[["elapsed"]] - t0, 2L))
    result
})
```

#### Train paralelo

```r
models <- future.apply::future_lapply(v_usinas, function(iu) {
    tryCatch(
        ajustar_usina(iu,
            dt_usinas = dt_usinas,
            dt_ger_obs = dataset$ger_obs,
            dt_irrad_prev_filt = dt_irrad_prev_filt,
            dt_corte_obs = dataset$corte,
            fonte = args$ordem_prioridade_fontes,
            fator_tolerancia = args$fator_tolerancia_limite_superior_geracao,
            strategy = strategy,
            config = args
        ),
        error = function(e) {
            plant_error(iu, e)
        }
    )
}, future.seed = TRUE)
```

Nota: no path paralelo, o logging dentro do worker pode nao funcionar
corretamente dependendo do backend (`multisession` vs `multicore`). O log do
erro pode ser feito no loop de pos-processamento ao detectar o sentinel.

#### Loop de pos-processamento (train)

```r
n_failed <- 0L
lapply(seq_along(v_usinas), function(i) {
    if (inherits(models[[i]], "plant_error")) {
        update_plant_status(provenance, v_usinas[i], "failed")
        n_failed <<- n_failed + 1L
        lg$error("Usina %s falhou: %s", v_usinas[i], models[[i]]$error)
    } else {
        write_model_artifact(models[[i]], v_usinas[i], args$artifact)
        update_plant_status(provenance, v_usinas[i], "completed")
        if ("metadata" %in% names(models[[i]])) {
            record_model_quality(metrics, v_usinas[i], models[[i]]$metadata)
        }
    }
    if (resume) write_checkpoint(provenance, args$artifact)
    lg$info("Usina %s processada (%d/%d)", v_usinas[i], i, n_total)
})

final_status <- if (n_failed == 0L) "completed" else "failed"
provenance <- finalize_provenance(provenance, final_status)
```

A mesma logica se aplica ao predict, com `processar_usina` no lugar de
`ajustar_usina`.

#### Status final do pipeline

Com falhas parciais, o pipeline pode terminar com `status: "failed"` mas com
usinas individuais marcadas corretamente. O health report ja tem infraestrutura
para reportar usinas individuais com `health: "failed"` via
`classify_plant_health`. O que muda e que agora chegamos la de fato.

Alternativa: pode-se introduzir um status intermediario `"partial"` para
distinguir "tudo falhou" de "algumas falharam". Mas isso e uma decisao de
produto que pode ser tomada depois -- o importante e que a informacao por usina
esteja correta no provenance.

#### Resume apos falha parcial

Com o checkpoint escrito corretamente, o proximo `--resume` pula as usinas
`"completed"` e reprocessa apenas as `"pending"` e `"failed"`:

```r
get_pending_plants <- function(checkpoint) {
    statuses <- checkpoint$plant_status
    names(statuses)[vapply(statuses, function(s) {
        s != "completed"
    }, logical(1L))]
}
```

`get_pending_plants` ja retorna tudo que nao e `"completed"`, incluindo
`"failed"`. Nenhuma mudanca necessaria nessa funcao.

### Riscos e mitigacao

| Risco                             | Mitigacao                                                                                   |
| --------------------------------- | ------------------------------------------------------------------------------------------- |
| `tryCatch` esconde bugs reais     | O erro e logado com `lg$error` e registrado no provenance; health report lista as falhas    |
| Falha silenciosa em producao      | Health report com `overall_health: "failed"` + lista de erros por usina sinaliza o problema |
| Sentinel misturado com resultados | Checagem `inherits(x, "plant_error")` no pos-processamento; classe dedicada evita confusao  |
| Logging no worker paralelo        | Log do erro feito no pos-processamento, nao no worker                                       |

### Escopo de arquivos afetados

| Arquivo                                     | Tipo de mudanca                                                                    |
| ------------------------------------------- | ---------------------------------------------------------------------------------- |
| `R/train.r`                                 | `tryCatch` no lapply serial e paralelo; pos-processamento com branch sucesso/falha |
| `R/predict.r`                               | Idem para `processar_usina`                                                        |
| `R/provenance.r`                            | Adicionar `plant_error()` (ou em utils); sem mudanca em `get_pending_plants`       |
| `R/health-report.r`                         | Nenhuma mudanca necessaria (ja suporta `"failed"` por usina)                       |
| `tests/testthat/test-integration-train.r`   | Adicionar testes de falha parcial                                                  |
| `tests/testthat/test-integration-predict.r` | Idem                                                                               |

## 4. Sequenciamento

Recomendo executar na ordem:

1. **Resiliencia per-plant** -- corrige um bug real (falha de uma usina mata o
   pipeline inteiro). Precede as outras mudancas porque a refatoracao de
   provenance/metrics para environment vai alterar os mesmos trechos de codigo.
   Melhor corrigir o comportamento primeiro, depois mudar a representacao.

2. **Provenance/metrics como environment** -- menor raio de explosao, totalmente
   interno. Nenhuma assinatura publica muda. Valida a abordagem environment antes
   do refactor maior. Nesse ponto o tryCatch e o sentinel ja estao no lugar,
   entao a refatoracao e puramente mecanica (lista -> environment, remover `<<-`).

3. **Model strategy** -- toca mais arquivos e muda assinaturas publicas
   (`predict_model`, `fit_model`, `build_model_artifact`). Executar depois que
   os testes estiverem estaveis com as mudancas anteriores.

Cada etapa deve ser um PR independente.
