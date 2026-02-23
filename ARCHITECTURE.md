# Arquitetura da Aplicação

Este documento descreve a arquitetura do pacote `mhpfv`, incluindo o fluxo de dados, componentes principais e decisões de design.

## Visão Geral

A aplicação implementa um pipeline de processamento de dados para consolidação de séries históricas de geração solar fotovoltaica. Opera em dois modos:

1. **Train**: Calibra modelos (plugáveis via Strategy Pattern) para estimar geração a partir de irradiância
2. **Predict**: Aplica consistência, preenche lacunas e gera o histórico consolidado

Ambos os modos suportam execução paralela via `future`/`future.apply`, retomada a partir de checkpoints, e emitem artefatos de observabilidade (proveniência, métricas, relatórios de saúde).

## Diagrama de Fluxo

```
                              ┌─────────────────────┐
                              │   config.jsonc      │
                              │   (configuração)    │
                              └──────────┬──────────┘
                                         │
                                         ▼
                              ┌─────────────────────┐
                              │   main.r            │
                              │  → cli_main()       │
                              └──────────┬──────────┘
                                         │
                         ┌───────────────┴────────────┐
                         │                            │
                         ▼                            ▼
              ┌─────────────────────┐      ┌─────────────────────┐
              │   MODO: train       │      │   MODO: predict     │
              │   train_main()      │      │   predict_main()    │
              └──────────┬──────────┘      └──────────┬──────────┘
                         │                            │
    ┌────────────────────┼────────────────────────────┼──────────────────┐
    │                    │                            │                  │
    │         ┌──────────┴──────────┐     ┌──────────┴──────────┐        │
    │         │  ajustar_usina()    │     │  processar_usina()  │        │
    │         │  (por usina, ∥)     │     │  (por usina, ∥)     │       │
    │         └──────────┬──────────┘     └──────────┬──────────┘        │
    │                    │                           │                   │
    │     ┌──────────────┴──────────────┐            │                   │
    │     │                             │            │                   │
    │     ▼                             ▼            ▼                   │
    │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
    │  │ consiste_        │  │ fit_model()      │  │ predict_model()  │  │
    │  │ geracao_unit()   │  │ (S3 dispatch)    │  │ (S3 dispatch)    │  │
    │  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘  │
    │           │                     │                     │            │
    │           │                     ▼                     │            │
    │           │           ┌──────────────────┐            │            │
    │           │           │  {usina}.rds     │◄───────────┤            │
    │           │           │  (artefato c/    │            │            │
    │           │           │   metadados)     │            │            │
    │           │           └──────────────────┘            │            │
    │           │                                           │            │
    │           └──────────────────┬────────────────────────┘            │
    │                              │                                     │
    │                              ▼                                     │
    │                   ┌──────────────────┐                             │
    │                   │ organiza_        │                             │
    │                   │ resultados()     │                             │
    │                   └────────┬─────────┘                             │
    │                            │                                       │
    │                            ▼                                       │
    │                   ┌──────────────────┐                             │
    │                   │ write_melhor_    │                             │
    │                   │ historico_*()    │                             │
    │                   └────────┬─────────┘                             │
    │                            │                                       │
    └────────────────────────────┼───────────────────────────────────────┘
                                 │
                 ┌───────────────┼───────────────┐
                 │               │               │
                 ▼               ▼               ▼
      ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
      │ SAÍDA        │ │ provenance-  │ │ metrics-     │
      │ ├─ MH_ger    │ │ {run_id}     │ │ {run_id}     │
      │ └─ MH_s/c    │ │ .json        │ │ .json        │
      └──────────────┘ └──────────────┘ └──────────────┘
                                               │
                                               ▼
                                      ┌──────────────┐
                                      │ health-      │
                                      │ {run_id}     │
                                      │ .json        │
                                      └──────────────┘
```

## Componentes Principais

### 1. Entry Point (`cli.r` / `main.r`)

`main.r` é o script de entrada que parseia argumentos CLI e delega para `cli_main()`.

`cli_main()` é a função principal do pacote, responsável por:

- Resolver parâmetros com precedência: argumento CLI > variável de ambiente > padrão
- Carregar e parsear configuração
- Despachar para modo `train` ou `predict`
- Configurar workers paralelos quando solicitado

| Parâmetro  | Flag CLI      | Variável de Ambiente | Padrão  |
| ---------- | ------------- | -------------------- | ------- |
| `parallel` | `--parallel`  | `MHPFV_PARALLEL`     | `FALSE` |
| `resume`   | `--resume`    | `MHPFV_RESUME`       | `FALSE` |
| `workers`  | `--workers N` | `MHPFV_WORKERS`      | auto    |

### 2. Configuração (`config-file.r`)

Gerencia parsing e validação do arquivo de configuração.

| Função                  | Descrição                                 |
| ----------------------- | ----------------------------------------- |
| `parse_config()`        | Interpreta e valida configuração completa |
| `valida_nomes_config()` | Verifica presença de chaves obrigatórias  |
| `valida_tipos_config()` | Valida tipos de cada chave                |
| `parsearg_janela()`     | Interpreta janela temporal (S3 generic)   |
| `parsearg_ids_usinas()` | Interpreta lista de usinas                |

### 3. Validação de Entrada (`validation.r`)

Framework de validação schema-based para dados de entrada. Verifica presença de colunas, tipos corretos e ausência de NA em colunas-chave, coletando todos os erros antes de reportar.

| Função                  | Descrição                                     |
| ----------------------- | --------------------------------------------- |
| `validate_input()`      | Valida um data.table contra um schema nomeado |
| `validate_all_inputs()` | Valida dataset completo + usinas              |
| `validate_artifact()`   | Valida estrutura de artefato de modelo        |

Schemas suportados: `geracao_observada`, `irradiancia_prevista`, `corte_observado`, `usinas`, `melhor_historico_geracao`.

### 4. Consistência de Dados (`consistencia-dados.r`)

Implementa validações e tratamentos de qualidade de dados.

```
Entrada: dados brutos de múltiplas fontes
    │
    ▼
┌─────────────────────────────────┐
│ checa_valores_faltantes()       │ → Preenche série temporal 30min
└─────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────┐
│ checa_valores_congelados()      │ → Detecta valores sem variação
└─────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────┐
│ manter_geracao_congelada_em_    │ → Preserva valores durante cortes
│ cortes()                        │
└─────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────┐
│ checa_valores_overbound()       │ → Remove outliers físicos
└─────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────┐
│ combina_fontes()                │ → Seleciona melhor fonte por timestamp
└─────────────────────────────────┘
    │
    ▼
Saída: dados consistidos com fonte única ("Consis")
```

#### Algoritmo de Detecção de Congelados

```r
# Janela deslizante de tamanho N
# Se max(janela) - min(janela) <= limiar:
#     marcar valores (exceto primeiro) como NA

# Aplicado duas vezes:
# 1. N=5, limiar=0.01 (detecção rápida)
# 2. N=8, limiar=0.1 (detecção de variação baixa)
```

### 5. Model Strategy (`model-strategy.r`, `model-linear-regression.r`)

Sistema plugável de modelos via S3 dispatch. Permite trocar o tipo de modelo sem alterar o pipeline.

#### Interface (`model_strategy`)

| Generic            | Responsabilidade                                 |
| ------------------ | ------------------------------------------------ |
| `fit_model()`      | Ajusta modelo a partir de geração e irradiância  |
| `predict_model()`  | Preenche lacunas usando modelo ajustado          |
| `model_metadata()` | Extrai metadados do modelo (slots, coeficientes) |

#### Implementação: `linear_regression`

Para cada hora `h` ∈ {05:00, 05:30, ..., 18:30}:

```
Geração_h = α_h × Irradiância_h
```

- Regressão linear sem intercepto (`lm(y ~ x + 0)`)
- Requer mínimo 10 pares válidos
- Valores zero tratados como NA antes do ajuste
- Fallback para quantil 70% se dados insuficientes

#### Como Adicionar um Novo Modelo

1. Crie `R/model-{nome}.r`
2. Implemente construtor: `{nome}_strategy <- function(...) new_model_strategy("{nome}", ...)`
3. Implemente `fit_model.{nome}()`, `predict_model.{nome}()`, `model_metadata.{nome}()`
4. Passe a nova estratégia para `train_main()` / `predict_main()`

### 6. Treinamento (`train.r`)

Calibra modelos para cada usina via `fit_model()` dispatch.

| Função                      | Descrição                                  |
| --------------------------- | ------------------------------------------ |
| `train_main()`              | Orquestra treinamento para todas as usinas |
| `ajustar_usina()`           | Processa uma usina individual              |
| `load_train_resume_state()` | Carrega estado de retomada do checkpoint   |

#### Artefato de Saída (enriquecido)

```r
list(
    id_usina = "USINA_A",
    parametros = data.frame(
        a = c(0.12, 0.15, ...),  # coeficientes angulares
        b = c(0, 0, ...),        # sempre zero (regressão linear)
        row.names = c("05:00", "05:30", ...)
    ),
    metadata = list(
        type = "linear_regression",
        n_slots = 28L,
        n_valid_slots = 26L,
        mean_coefficient = 0.031,
        timestamp = "2025-01-01T12:00:00Z",
        package_version = "0.1.1",
        config_hash = "sha256:abc123..."
    )
)
```

### 7. Previsão/Consolidação (`predict.r`)

Aplica consistência e gera histórico final via `predict_model()` dispatch.

| Função                        | Descrição                                   |
| ----------------------------- | ------------------------------------------- |
| `predict_main()`              | Orquestra processamento de todas as usinas  |
| `processar_usina()`           | Processa uma usina individual               |
| `load_predict_resume_state()` | Carrega estado de retomada do checkpoint    |
| `organiza_resultados()`       | Agrupa resultados por tipo (com/sem cortes) |
| `get_dataset()`               | Carrega todos os dados necessários          |

### 8. Preenchimento de Lacunas (`preenchimento-dados-faltantes.r`)

Imputa valores faltantes usando modelo treinado.

```
┌─────────────────────────────────┐
│ preenche_geracao_unit()         │
└─────────────────────────────────┘
    │
    ├── aplica_cortes_em_geracao() → Marca períodos de corte como NA
    │
    ├── substitui_por_estimativas() → Preenche NA com modelo
    │   │
    │   └── ger_est = α_h × irrad_NWP_h
    │
    ├── combina_dados_tempo() → Merge com MH anterior
    │
    └── zera_horarios_extremos() → Limpa horários noturnos
```

### 9. Paralelismo (`parallel.r`)

Gerencia o backend de execução paralela usando o pacote `future`.

| Função                  | Descrição                                         |
| ----------------------- | ------------------------------------------------- |
| `setup_parallel_plan()` | Configura plano paralelo (multisession/multicore) |
| `reset_parallel_plan()` | Restaura plano anterior                           |
| `get_parallel_config()` | Consulta configuração ativa (workers, strategy)   |

O número de workers é resolvido com a seguinte precedência:

1. Argumento explícito `workers`
2. Variável de ambiente `MHPFV_WORKERS`
3. Auto-detect: `future::availableCores() - 1` (mínimo 1)

### 10. Artefatos de Modelo (`artifact.r`)

Constrói e valida artefatos de modelo enriquecidos com metadados de proveniência.

| Função                        | Descrição                                               |
| ----------------------------- | ------------------------------------------------------- |
| `build_model_artifact()`      | Monta artefato completo (id + parâmetros + metadados)   |
| `build_artifact_metadata()`   | Combina metadados do modelo com info do pacote e config |
| `validate_artifact()`         | Valida estrutura (aceita formato antigo sem metadados)  |
| `normalize_config_for_hash()` | Normaliza config para hash determinístico               |

### 11. Proveniência e Checkpoints (`provenance.r`)

Rastreabilidade completa de cada execução do pipeline.

| Função                  | Descrição                                        |
| ----------------------- | ------------------------------------------------ |
| `generate_run_id()`     | Gera ID único `{mode}-{YYYYMMDD}-{HHMMSS}-{hex}` |
| `create_provenance()`   | Cria registro de proveniência inicial            |
| `update_plant_status()` | Atualiza status de uma usina                     |
| `finalize_provenance()` | Marca fim da execução com duração                |
| `write_provenance()`    | Serializa proveniência como JSON                 |
| `write_checkpoint()`    | Persiste estado para retomada                    |
| `read_checkpoint()`     | Lê e valida checkpoint (verifica config hash)    |
| `get_pending_plants()`  | Retorna usinas pendentes de um checkpoint        |
| `write_plant_result()`  | Salva resultado intermediário de uma usina       |
| `read_plant_result()`   | Carrega resultado intermediário                  |
| `cleanup_checkpoint()`  | Remove checkpoints após conclusão                |

#### Fluxo de Retomada

```
1. read_checkpoint() → valida config_hash
2. get_pending_plants() → identifica usinas não completadas
3. read_plant_result() → carrega resultados já processados
4. Processa apenas usinas pendentes
5. cleanup_checkpoint() → remove arquivos temporários
```

### 12. Métricas (`metrics.r`)

Coleta de métricas por usina e agregados do pipeline.

| Função                       | Descrição                                          |
| ---------------------------- | -------------------------------------------------- |
| `create_metrics()`           | Cria registro de métricas vazio                    |
| `record_plant_timing()`      | Registra duração de processamento por usina        |
| `record_plant_data_volume()` | Registra volume de dados e taxa de NA              |
| `record_model_quality()`     | Registra qualidade do modelo (slots, coeficientes) |
| `finalize_metrics()`         | Computa agregados (mean/max/min duração)           |
| `write_metrics()`            | Serializa métricas como JSON                       |

### 13. Relatório de Saúde (`health-report.r`)

Classificação de saúde por usina e do pipeline.

| Função                      | Descrição                                          |
| --------------------------- | -------------------------------------------------- |
| `build_health_report()`     | Agrega proveniência e métricas em relatório        |
| `classify_plant_health()`   | Classifica usina: `healthy`/`warning`/`failed`     |
| `classify_overall_health()` | Classifica pipeline: `healthy`/`degraded`/`failed` |
| `write_health_report()`     | Serializa relatório como JSON                      |

Critérios de classificação:

- **failed**: proveniência com status != "completed"
- **warning**: taxa de NA > 50% ou menos da metade dos slots com coeficiente válido
- **healthy**: caso contrário

### 14. Comparação de Modelos (`model-comparison.r`)

Comparação pairwise de artefatos de modelo.

| Função                         | Descrição                                  |
| ------------------------------ | ------------------------------------------ |
| `compare_artifacts()`          | Compara dois artefatos (metadados + coefs) |
| `compare_artifact_files()`     | Compara a partir de caminhos de arquivo    |
| `compare_multiple_artifacts()` | Comparações pairwise para N artefatos      |
| `format_comparison()`          | Formata relatório legível                  |

### 15. Logging (`logging.r`)

Logging estruturado com contexto de execução.

| Função                | Descrição                                         |
| --------------------- | ------------------------------------------------- |
| `get_pkg_logger()`    | Retorna o logger do pacote                        |
| `set_log_context()`   | Injeta `run_id`, `mode`, `stage` em todos os logs |
| `clear_log_context()` | Remove contexto estruturado                       |

Suporta saída em formato JSON via `MHPFV_LOG_FORMAT=json`.

### 16. Utilitários (`utils.r`)

Funções auxiliares reutilizáveis.

| Função                       | Descrição                                   |
| ---------------------------- | ------------------------------------------- |
| `checa_valores_faltantes()`  | Expande série para 30min, trata NaN/999     |
| `combina_dados_tempo()`      | Merge temporal com sobreposição             |
| `associa_nwp_usina()`        | Encontra ponto NWP mais próximo (Haversine) |
| `adicionar_passo_previsao()` | Calcula D+0, D+1, etc.                      |
| `interpolar_30min()`         | Interpola NWP de 1h para 30min              |

### 17. Escrita (`escrita.r`)

Exportação de resultados.

| Função                                        | Descrição             |
| --------------------------------------------- | --------------------- |
| `write_model_artifact()`                      | Salva modelo em RDS   |
| `write_melhor_historico_geracao()`            | Exporta MH em Parquet |
| `write_melhor_historico_geracao_sem_cortes()` | Exporta MH sem cortes |

## Fluxo de Dados

### Entrada

```
data/
├── config.jsonc                     # Configuração
├── usinas.csv                       # Cadastro de usinas
├── geracao_observada.csv            # Séries de geração
├── irradiancia_prevista.parquet     # Previsões NWP
├── corte_observado.csv              # Eventos de corte
```

### Processamento Interno

```
pfvIO::conectamock_pfv()
    │
    ├── get_usinas()
    ├── get_geracao_observada()
    ├── get_irradiancia_prevista()
    ├── get_corte_observado()
```

### Saída

```
out/
├── melhor_historico_geracao.parquet
├── melhor_historico_geracao_sem_cortes.parquet
├── provenance-{run_id}.json
├── metrics-{run_id}.json
└── health-{run_id}.json

artifact/
├── {id_usina}.rds  # Um por usina (com metadados)
├── provenance-{run_id}.json
├── metrics-{run_id}.json
└── health-{run_id}.json
```

## Decisões de Design

### Por que data.table?

- Performance superior para datasets grandes (milhões de linhas)
- Sintaxe concisa para operações por grupo
- Modificação in-place eficiente em memória

### Por que regressão linear sem intercepto?

- Irradiância zero implica geração zero (fisicamente correto)
- Modelo simples e interpretável
- Robusto com poucos dados

### Por que Strategy Pattern para modelos?

- Permite trocar o tipo de modelo sem alterar o pipeline
- Facilita testes com mocks (ex: `test_strategy` nos testes)
- Suporta futura adição de modelos mais sofisticados (ML, ensemble)
- Metadados do modelo são extraídos de forma uniforme

### Por que processar usinas individualmente?

- Permite paralelização via `future_lapply`
- Isola falhas (uma usina com erro não afeta outras)
- Facilita debugging e logging por usina
- Suporta retomada granular (checkpoint por usina)

### Por que dois históricos (com/sem cortes)?

- **Com cortes**: Reflete geração real observada
- **Sem cortes**: Estima geração potencial

### Por que checkpoints e retomada?

- Pipelines com centenas de usinas podem levar horas
- Falhas pontuais não devem exigir reprocessamento completo
- Hash da configuração garante que checkpoints incompatíveis são rejeitados
- Checkpoints são limpos após conclusão bem-sucedida

### Por que artefatos de observabilidade (proveniência, métricas, saúde)?

- Rastreabilidade completa de cada execução para auditoria
- Métricas por usina permitem identificar gargalos e anomalias
- Relatórios de saúde fornecem visão rápida do estado do pipeline
- Formato JSON facilita integração com ferramentas de monitoramento

## Dependências Externas

```
pfvIO (>= 0.3.1)
├── Leitura padronizada de dados
├── Validação de schemas
└── Conexão mock para testes

data.table (>= 1.17.0)
├── Manipulação de dados
└── Operações por grupo

lubridate (>= 1.9.4)
└── Manipulação de datas/horas

future (>= 1.34.0)
├── Backend de paralelismo
└── Planos: multisession, multicore, sequential

future.apply (>= 1.11.0)
└── future_lapply para paralelização

digest (>= 0.6.0)
└── SHA-256 hash para config e proveniência

jsonlite (>= 1.8.0)
└── Serialização JSON (proveniência, métricas, saúde)

lgr (>= 0.4.4)
├── Logging estruturado
└── Contexto por execução (FilterInject)

argparse (>= 2.2.5)
└── Parsing de argumentos CLI

arrow (>= 22.0.0) [Suggests]
└── Leitura/escrita Parquet
```

## CI/CD

| Workflow        | Descrição                                   |
| --------------- | ------------------------------------------- |
| `R-CMD-check`   | Verificação completa do pacote R            |
| `test-coverage` | Testes com relatório de cobertura (Codecov) |
| `lint`          | lintr com complexidade ciclomática          |
| `docker`        | Build e publicação da imagem Docker         |
| `benchmark`     | Suite de benchmarks de performance          |
