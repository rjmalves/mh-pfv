# mhpfv

[![R-CMD-check](https://github.com/rjmalves/mh-pfv/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/rjmalves/mh-pfv/actions/workflows/R-CMD-check.yaml)
[![codecov](https://codecov.io/gh/rjmalves/mh-pfv/graph/badge.svg?token=ek0AkoDosq)](https://codecov.io/gh/rjmalves/mh-pfv)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Construção do Melhor Histórico de Geração Solar Fotovoltaica** — Um pacote R para consolidação e consistência de dados históricos de geração de usinas solares fotovoltaicas do Sistema Interligado Nacional (SIN).

Desenvolvido pelo [Operador Nacional do Sistema Elétrico (ONS)](https://www.ons.org.br/) para uso em planejamento energético e previsão de geração renovável.

---

## Visão Geral

Este pacote implementa um pipeline de processamento de dados que:

1. **Valida e consiste** dados de geração observada de múltiplas fontes (PI-ONS, CCEE, etc.)
2. **Detecta e trata** valores anômalos (congelados, fora de limites físicos)
3. **Preenche lacunas** usando modelos plugáveis via S3 Strategy Pattern (padrão: regressão linear com NWP)
4. **Combina fontes** por ordem de prioridade configurável
5. **Gera históricos consolidados** com e sem consideração de cortes de geração
6. **Rastreia proveniência** com run IDs, checksums de configuração e checkpoints para retomada
7. **Coleta métricas** de desempenho por usina e gera relatórios de saúde do pipeline

### Casos de Uso

- Construção de séries históricas consistentes para estudos de planejamento energético
- Preparação de dados de treinamento para modelos de previsão de geração solar
- Auditoria e validação de dados de medição de usinas fotovoltaicas
- Análise de desempenho histórico de plantas solares
- Comparação entre execuções de modelos e artefatos

---

## Arquitetura

```
┌────────────────────────────────────────────────────────────────────────────┐
│                              ENTRADA DE DADOS                              │
├─────────────────┬─────────────────┬──────────────────┬─────────────────────┤
│ Geração Observ. │ Irradiância NWP │ Cortes Observ.   │ Cadastro Usinas     │
│ (PI/CCEE)       │ (GFS, etc.)     │                  │                     │
└────────┬────────┴────────┬────────┴────────┬─────────┴──────────┬──────────┘
         │                 │                 │                    │
         ▼                 ▼                 ▼                    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                  PARSING E VALIDAÇÃO (parse_config)                        │
└────────────────────────────────┬───────────────────────────────────────────┘
                                 │
                 ┌───────────────┴────────────┐
                 │                            │
                 ▼                            ▼
┌────────────────────────────────┐ ┌────────────────────────────────┐
│     MODO: TRAIN (train_main)   │ │   MODO: PREDICT (predict_main) │
│                                │ │                                │
│  Consistência → Cortes →       │ │  Consistência → Preenchimento  │
│  fit_model(strategy) →         │ │  predict_model(strategy) →     │
│  Artefato c/ metadados         │ │  MH Geração (com/sem cortes)   │
└────────────┬───────────────────┘ └────────────┬───────────────────┘
             │                                  │
             └──────────────┬───────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                         OBSERVABILIDADE                                    │
│  Proveniência (JSON) │ Métricas (JSON) │ Relatório de Saúde (JSON)         │
└────────────────────────────────────────────────────────────────────────────┘
```

### Componentes Principais

| Módulo                            | Descrição                                                       |
| --------------------------------- | --------------------------------------------------------------- |
| `cli.r`                           | Entry point do pacote (`cli_main`), parsing de flags e env vars |
| `config-file.r`                   | Parsing e validação do arquivo de configuração                  |
| `consistencia-dados.r`            | Detecção de valores congelados, outliers, combinação de fontes  |
| `model-strategy.r`                | Interface plugável para modelos (`fit_model`, `predict_model`)  |
| `model-linear-regression.r`       | Implementação da estratégia de regressão linear                 |
| `train.r`                         | Pipeline de treinamento com suporte a paralelismo e retomada    |
| `predict.r`                       | Pipeline de consolidação com suporte a paralelismo e retomada   |
| `preenchimento-dados-faltantes.r` | Imputação de dados faltantes usando NWP                         |
| `parallel.r`                      | Gestão do backend paralelo (`future`/`future.apply`)            |
| `artifact.r`                      | Construção e validação de artefatos de modelo enriquecidos      |
| `provenance.r`                    | Rastreabilidade de execução, checkpoints e retomada             |
| `metrics.r`                       | Coleta de métricas por usina e agregados do pipeline            |
| `health-report.r`                 | Classificação de saúde por usina e do pipeline                  |
| `logging.r`                       | Logging estruturado com contexto (run_id, mode)                 |
| `utils.r`                         | Funções auxiliares (interpolação, associação NWP-usina)         |
| `escrita.r`                       | Exportação de resultados em Parquet                             |

---

## Quick Start

### Pré-requisitos

- R >= 4.0
- [renv](https://rstudio.github.io/renv/) para gerenciamento de dependências

### Instalação

```bash
# Instale o pacote usando remotes para desenvolvimento (branch main)
Rscript -e "remotes::install_github(\"rjmalves/mh-pfv\")"

# Instale o pacote usando remotes de uma tag específica (para uso)
Rscript -e "remotes::install_github(\"rjmalves/mh-pfv@release\")"
```

### Execução Rápida

```bash
# 1. Prepare seus dados no diretório ./data (veja seção "Dados de Entrada")

# 2. Configure o arquivo config.jsonc

# 3. Execute o treinamento
Rscript main.r --datadir ./data

# 4. Altere mode para "predict" no config.jsonc e execute
Rscript main.r --datadir ./data
```

### Execução com Paralelismo e Retomada

```bash
# Treinamento paralelo com 4 workers
Rscript main.r --datadir ./data --parallel --workers 4

# Retomada após falha (reprocessa apenas usinas pendentes)
Rscript main.r --datadir ./data --parallel --resume
```

### Usando Docker

```bash
# Build da imagem
docker build -t mhpfv .

# Execução com volumes montados
docker run -v $(pwd)/data:/app/data -v $(pwd)/out:/app/out mhpfv --datadir /app/data

# Execução paralela com variáveis de ambiente
docker run \
  -e MHPFV_PARALLEL=true \
  -e MHPFV_WORKERS=4 \
  -e MHPFV_RESUME=true \
  -v $(pwd)/data:/app/data \
  -v $(pwd)/out:/app/out \
  mhpfv --datadir /app/data
```

---

## Uso Detalhado

### Linha de Comando

```bash
Rscript main.r --datadir <DIRETÓRIO> [--parallel] [--resume] [--workers N]
```

| Argumento    | Descrição                                            | Default  |
| ------------ | ---------------------------------------------------- | -------- |
| `--datadir`  | Diretório contendo dados de entrada e `config.jsonc` | `./data` |
| `--parallel` | Habilita processamento paralelo de usinas            | `FALSE`  |
| `--resume`   | Retoma execução a partir do último checkpoint        | `FALSE`  |
| `--workers`  | Número de workers paralelos (requer `--parallel`)    | auto     |

### Variáveis de Ambiente

| Variável           | Descrição                    | Valores                          |
| ------------------ | ---------------------------- | -------------------------------- |
| `LOG_LEVEL`        | Nível de log                 | `debug`, `info`, `warn`, `error` |
| `MHPFV_LOG_FORMAT` | Formato de saída do log      | `text` (padrão), `json`          |
| `MHPFV_PARALLEL`   | Habilita paralelismo via env | `true`/`false`                   |
| `MHPFV_RESUME`     | Habilita retomada via env    | `true`/`false`                   |
| `MHPFV_WORKERS`    | Número de workers via env    | inteiro positivo                 |

A resolução de prioridade para flags é: **argumento CLI** > **variável de ambiente** > **valor padrão**.

```bash
LOG_LEVEL=debug MHPFV_LOG_FORMAT=json Rscript main.r --datadir ./data
```

### Arquivo de Configuração (`config.jsonc`)

```jsonc
{
  // Modo de execução: "train" ou "predict"
  "mode": "train",

  // Caminhos de I/O
  "input": "./data",
  "output": "./out",
  "artifact": "./artifact",

  // Janela temporal: inteiro (dias passados) ou ["YYYY-MM-DD", "YYYY-MM-DD"]
  "janela": 90,

  // IDs das usinas (vazio = todas)
  "ids_usinas": [],

  // Prioridade das fontes de geração observada
  "ordem_prioridade_fontes": ["PI", "CCEE", "CCEE1h"],

  // Prioridade dos modelos NWP
  "ordem_prioridade_modelosNWP": ["GFS"],

  // Fator multiplicador da capacidade instalada para limite superior
  "fator_tolerancia_limite_superior_geracao": 1.1,
}
```

---

## Dados de Entrada

O diretório de dados deve conter os seguintes arquivos:

| Arquivo                                       | Formato        | Descrição                                                        |
| --------------------------------------------- | -------------- | ---------------------------------------------------------------- |
| `config.jsonc`                                | JSONC          | Configuração do modelo                                           |
| `usinas.parquet`                              | Parquet ou CSV | Cadastro de usinas (id, lat, lon, capacidade)                    |
| `geracao_observada.parquet`                   | Parquet ou CSV | Série temporal de geração por fonte                              |
| `irradiancia_prevista.parquet`                | Parquet ou CSV | Previsões NWP de irradiância                                     |
| `corte_observado.parquet`                     | Parquet ou CSV | Registro da existência de cortes de geração (binário)            |
| `melhor_historico_geracao.parquet`            | Parquet ou CSV | Versão existente do MHG sem estimar valores em momento de cortes |
| `melhor_historico_geracao_sem_cortes.parquet` | Parquet ou CSV | Registro de cortes de geração com estimativas durante cortes     |

### Schemas de Dados

#### `usinas.parquet`

```
id_usina,latitude,longitude,capacidade_instalada_MW,data_inicio_operacao_comercial
USINA_A,-23.5505,-46.6333,100.0,2020-01-01 12:00:00
```

#### `geracao_observada.parquet`

```
id_fonte_observacao,id_usina,data_hora_observacao,valor,status
PI,USINA_A,2024-01-01 00:00:00,45.2,0
```

#### `irradiancia_prevista.parquet`

```
id_modelo_nwp,latitude,longitude,data_hora_rodada,data_hora_previsao,valor
GFS,-23.5,-46.5,2024-01-01 00:00:00,2024-01-01 12:00:00,850.5
```

#### `corte_observado.parquet`

```
id_fonte_observacao,id_usina,data_hora_observacao,valor,status
PI,USINA_A,2024-01-01 00:00:00,1,0
```

### `melhor_historico_geracao.parquet`

```
id_fonte_observacao,id_usina,data_hora_observacao,valor,status
Consis,USINA_A,2024-01-01 00:00:00,45.2,1
```

### `melhor_historico_geracao_sem_cortes.parquet`

```
id_fonte_observacao,id_usina,data_hora_observacao,valor,status
Consis,USINA_A,2024-01-01 00:00:00,45.2,1
```

---

## Saídas

O pipeline gera os seguintes artefatos no diretório de saída:

### Dados de Resultado

| Arquivo                                       | Descrição                                                                |
| --------------------------------------------- | ------------------------------------------------------------------------ |
| `melhor_historico_geracao.parquet`            | Série consolidada de geração sem estimar valores para momentos de cortes |
| `melhor_historico_geracao_sem_cortes.parquet` | Série consolidada de geração com valores estimados durante cortes        |

### Schema de Saída

```
id_fonte_observacao,id_usina,data_hora_observacao,valor,status
Consis,USINA_A,2024-01-01 00:00:00,45.2,1
```

| Status | Significado                            |
| ------ | -------------------------------------- |
| 1      | Dado original da fonte prioritária     |
| 2      | Dado de fonte secundária               |
| 3      | Dado de fonte terciária                |
| 4      | Estimado pelo modelo (NWP + regressão) |

### Artefatos de Observabilidade

Cada execução do pipeline produz adicionalmente:

| Arquivo                    | Descrição                                                                 |
| -------------------------- | ------------------------------------------------------------------------- |
| `{id_usina}.rds`           | Artefato de modelo com metadados (tipo, versão, config hash) — modo train |
| `provenance-{run_id}.json` | Registro de proveniência com status por usina e timestamps                |
| `metrics-{run_id}.json`    | Métricas por usina (duração, volume de dados, qualidade do modelo)        |
| `health-{run_id}.json`     | Relatório de saúde (healthy/degraded/failed) com avisos e erros por usina |
| `checkpoint-{run_id}.json` | Checkpoint para retomada (removido após conclusão bem-sucedida)           |

---

## Metodologia

### Detecção de Valores Congelados

Valores são considerados "congelados" quando uma janela deslizante de N valores consecutivos apresenta variação menor que um limiar. O algoritmo aplica duas passagens:

- Janela de 5 valores com limiar de 0.01
- Janela de 8 valores com limiar de 0.1

### Modelo de Regressão (Strategy Pattern)

O pipeline usa um sistema de estratégias plugáveis. `fit_model()` resolve a
função de ajuste por convenção de nome, enquanto `predict_model()` e
`model_metadata()` usam despacho S3:

```r
# Treinamento com estratégia padrão (regressão linear sem intercepto)
train_main(config, strategy = "linear_regression")

# Previsão (lê modelo do artefato salvo)
predict_main(config)
```

Para cada hora do dia (05:00 às 18:30, intervalos de 30min), ajusta-se:

```
Geração = α × Irradiância
```

Requer mínimo de 10 pares válidos por hora para ajuste.

### Preenchimento de Lacunas

1. Valores faltantes são estimados usando: `Ger_est = α × Irrad_NWP`
2. Estimativas fora dos limites físicos (0 a capacidade × fator) são descartadas
3. Dados do MH anterior são combinados com novos dados

### Retomada de Execução

Quando `--resume` está habilitado:

1. O pipeline verifica checkpoints existentes no diretório de saída
2. Valida o hash da configuração (rejeita checkpoints de configurações diferentes)
3. Reprocessa apenas usinas pendentes, carregando resultados intermediários do disco
4. Remove checkpoints e resultados intermediários após conclusão bem-sucedida

---

## Testes

```bash
# Executar testes unitários
Rscript -e "devtools::test()"

# Verificação completa do pacote
Rscript -e "devtools::check()"

# Linting (inclui complexidade ciclomática)
Rscript -e "lintr::lint_package()"

# Cobertura de testes
Rscript -e "covr::package_coverage()"
```

---

## Contribuindo

Contribuições são bem-vindas! Por favor, leia o [CONTRIBUTING.md](CONTRIBUTING.md) para detalhes sobre:

- Configuração do ambiente de desenvolvimento
- Padrões de código e estilo
- Processo de submissão de Pull Requests

---

## Licença

Este projeto está licenciado sob a Licença MIT - veja o arquivo [LICENSE](LICENSE) para detalhes.

---

## Documentação Adicional

- [ARCHITECTURE.md](ARCHITECTURE.md) - Detalhes da arquitetura da aplicação
- [CHANGELOG.md](CHANGELOG.md) - Histórico de versões

---

## Contato

- **Organização**: [ONS - Operador Nacional do Sistema Elétrico](https://www.ons.org.br/)
- **Issues**: [GitHub Issues](https://github.com/rjmalves/mh-pfv/issues)

## Citação

```bibtex
@software{mhpfv2025,
  author = {{ONS - Operador Nacional do Sistema Elétrico}},
  title = {mhpfv: Consolidação de Histórico de Geração Solar},
  year = {2025},
  url = {https://github.com/rjmalves/mh-pfv},
  version = {0.1.1}
}
```
