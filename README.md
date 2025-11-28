# mhpfv

[![R-CMD-check](https://github.com/rjmalves/mh-pfv/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/rjmalves/mh-pfv/actions/workflows/R-CMD-check.yaml)
[![codecov](https://codecov.io/gh/rjmalves/mh-pfv/graph/badge.svg?token=ek0AkoDosq)](https://codecov.io/gh/rjmalves/mh-pfv)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Construção do Melhor Histórico de Geração Solar Fotovoltaica** — Um pacote R para consolidação e consistência de dados históricos de geração de usinas solares fotovoltaicas do Sistema Interligado Nacional (SIN).

Desenvolvido pelo [Operador Nacional do Sistema Elétrico (ONS)](https://www.ons.org.br/) para uso em planejamento energético e previsão de geração renovável.

---

## 📋 Visão Geral

Este pacote implementa um pipeline de processamento de dados que:

1. **Valida e consiste** dados de geração observada de múltiplas fontes (PI-ONS, CCEE, etc.)
2. **Detecta e trata** valores anômalos (congelados, fora de limites físicos)
3. **Preenche lacunas** usando modelos de regressão linear calibrados com previsões de irradiância (NWP)
4. **Combina fontes** por ordem de prioridade configurável
5. **Gera históricos consolidados** com e sem consideração de cortes de geração

### Casos de Uso

- Construção de séries históricas consistentes para estudos de planejamento energético
- Preparação de dados de treinamento para modelos de previsão de geração solar
- Auditoria e validação de dados de medição de usinas fotovoltaicas
- Análise de desempenho histórico de plantas solares

---

## 🏗️ Arquitetura

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
│                         MODO: TRAIN (train_main)                           │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────┐  │
│  │ Consistência     │  │ Aplicação de     │  │ Ajuste de Regressão      │  │
│  │ de Dados         │→ │ Cortes           │→ │ Geração ~ Irradiância    │  │
│  │ (por usina)      │  │                  │  │ (por hora do dia)        │  │
│  └──────────────────┘  └──────────────────┘  └───────────┬──────────────┘  │
│                                                          │                 │
│                                                          ▼                 │
│                                              ┌──────────────────────────┐  │
│                                              │ Artefato: modelo.rds     │  │
│                                              │ (coeficientes por hora)  │  │
│                                              └──────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────────┐
│                        MODO: PREDICT (predict_main)                        │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────┐  │
│  │ Consistência     │  │ Preenchimento    │  │ Combinação com           │  │
│  │ de Dados         │→ │ por Estimativas  │→ │ MH Anterior              │  │
│  │ (por usina)      │  │ (modelo + NWP)   │  │                          │  │
│  └──────────────────┘  └──────────────────┘  └───────────┬──────────────┘  │
│                                                          │                 │
│                                                          ▼                 │
│                                              ┌──────────────────────────┐  │
│                                              │ Saída: MH Geração        │  │
│                                              │ (com/sem cortes)         │  │
│                                              └──────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────┘
```

### Componentes Principais

| Módulo                            | Descrição                                                          |
| --------------------------------- | ------------------------------------------------------------------ |
| `config-file.r`                   | Parsing e validação do arquivo de configuração                     |
| `consistencia-dados.r`            | Detecção de valores congelados, outliers, combinação de fontes     |
| `train.r`                         | Treinamento de modelos de regressão linear (geração ~ irradiância) |
| `predict.r`                       | Pipeline de consolidação e geração do melhor histórico             |
| `preenchimento-dados-faltantes.r` | Imputação de dados faltantes usando NWP                            |
| `utils.r`                         | Funções auxiliares (interpolação, associação NWP-usina)            |
| `escrita.r`                       | Exportação de resultados em CSV/Parquet                            |

---

## 🚀 Quick Start

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

### Usando Docker

```bash
# Build da imagem
docker build -t mhpfv .

# Execução com volumes montados
docker run -v $(pwd)/data:/app/data -v $(pwd)/out:/app/out mhpfv --datadir /app/data
```

---

## 📖 Uso Detalhado

### Linha de Comando

```bash
Rscript main.r --datadir <DIRETÓRIO>
```

| Argumento   | Descrição                                            | Default  |
| ----------- | ---------------------------------------------------- | -------- |
| `--datadir` | Diretório contendo dados de entrada e `config.jsonc` | `./data` |

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
  "fator_tolerancia_limite_superior_geracao": 1.1
}
```

### Variáveis de Ambiente

| Variável    | Descrição    | Valores                          |
| ----------- | ------------ | -------------------------------- |
| `LOG_LEVEL` | Nível de log | `debug`, `info`, `warn`, `error` |

```bash
LOG_LEVEL=debug Rscript main.r --datadir ./data
```

---

## 📁 Dados de Entrada

O diretório de dados deve conter os seguintes arquivos:

| Arquivo                        | Formato        | Descrição                                     |
| ------------------------------ | -------------- | --------------------------------------------- |
| `config.jsonc`                 | JSONC          | Configuração do modelo                        |
| `usinas.parquet`               | Parquet ou CSV | Cadastro de usinas (id, lat, lon, capacidade) |
| `geracao_observada.parquet`    | Parquet ou CSV | Série temporal de geração por fonte           |
| `irradiancia_prevista.parquet` | Parquet ou CSV | Previsões NWP de irradiância                  |
| `corte_observado.parquet`      | Parquet ou CSV | Registro de cortes de geração                 |

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
PI,USINA_A,2024-01-01 00:00:00,45.2,0
```

---

## 📊 Saídas

O modelo gera dois arquivos no diretório de saída:

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

---

## 🔬 Metodologia

### Detecção de Valores Congelados

Valores são considerados "congelados" quando uma janela deslizante de N valores consecutivos apresenta variação menor que um limiar. O algoritmo aplica duas passagens:

- Janela de 5 valores com limiar de 0.01
- Janela de 8 valores com limiar de 0.1

### Modelo de Regressão

Para cada hora do dia (05:00 às 18:30, intervalos de 30min), ajusta-se uma regressão linear sem intercepto:

```
Geração = α × Irradiância
```

Requer mínimo de 10 pares válidos por hora para ajuste.

### Preenchimento de Lacunas

1. Valores faltantes são estimados usando: `Ger_est = α × Irrad_NWP`
2. Estimativas fora dos limites físicos (0 a capacidade × fator) são descartadas
3. Dados do MH anterior são combinados com novos dados

---

## 🧪 Testes

```bash
# Executar testes unitários
Rscript -e "devtools::test()"

# Verificação completa do pacote
Rscript -e "devtools::check()"

# Linting
Rscript -e "lintr::lint_package()"
```

---

## 🤝 Contribuindo

Contribuições são bem-vindas! Por favor, leia o [CONTRIBUTING.md](CONTRIBUTING.md) para detalhes sobre:

- Configuração do ambiente de desenvolvimento
- Padrões de código e estilo
- Processo de submissão de Pull Requests

---

## 📜 Licença

Este projeto está licenciado sob a Licença MIT - veja o arquivo [LICENSE](LICENSE) para detalhes.

---

## 📚 Documentação Adicional

- [ARCHITECTURE.md](ARCHITECTURE.md) - Detalhes da arquitetura da aplicação
- [CHANGELOG.md](CHANGELOG.md) - Histórico de versões

---

## 📞 Contato

- **Organização**: [ONS - Operador Nacional do Sistema Elétrico](https://www.ons.org.br/)
- **Issues**: [GitHub Issues](https://github.com/rjmalves/mh-pfv/issues)

## Citação

```bibtex
@software{mhpfv2025,
  author = {{ONS - Operador Nacional do Sistema Elétrico}},
  title = {mhpfv: Consolidação de Histórico de Geração Solar},
  year = {2025},
  url = {https://github.com/rjmalves/mh-pfv},
  version = {0.1.0}
}
```
