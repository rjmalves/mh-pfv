# Arquitetura do Sistema

Este documento descreve a arquitetura do pacote `melhorhistoricosolar`, incluindo o fluxo de dados, componentes principais e decisões de design.

## Visão Geral

O sistema implementa um pipeline de processamento de dados para consolidação de séries históricas de geração solar fotovoltaica. Opera em dois modos:

1. **Train**: Calibra modelos de regressão linear para estimar geração a partir de irradiância
2. **Predict**: Aplica consistência, preenche lacunas e gera o histórico consolidado

## Diagrama de Fluxo

```
                              ┌─────────────────────┐
                              │   config.jsonc      │
                              │   (configuração)    │
                              └──────────┬──────────┘
                                         │
                                         ▼
                              ┌─────────────────────┐
                              │    main.r           │
                              │  (entry point)      │
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
    │                    ▼                            ▼                  │
    │         ┌─────────────────────┐     ┌─────────────────────┐        │
    │         │  ajustar_usina()    │     │  processar_usina()  │        │
    │         │  (por usina)        │     │  (por usina)        │        │
    │         └──────────┬──────────┘     └──────────┬──────────┘        │
    │                    │                           │                   │
    │     ┌──────────────┴──────────────┐            │                   │
    │     │                             │            │                   │
    │     ▼                             ▼            ▼                   │
    │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
    │  │ consiste_        │  │ ajusta_regressao │  │ preenche_        │  │
    │  │ geracao_unit()   │  │ _ger_irrad()     │  │ geracao_unit()   │  │
    │  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘  │
    │           │                     │                     │            │
    │           │                     ▼                     │            │
    │           │           ┌──────────────────┐            │            │
    │           │           │  modelo.rds      │◄───────────┤            │
    │           │           │  (artefato)      │            │            │
    │           │           └──────────────────┘            │            │
    │           │                                           │            │
    │           └──────────────────┬──────────────────────-─┘            │
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
                                 ▼
                      ┌─────────────────────┐
                      │  SAÍDA              │
                      │  ├─ MH_geracao      │
                      │  └─ MH_sem_cortes   │
                      └─────────────────────┘
```

## Componentes Principais

### 1. Entry Point (`main.r`)

Ponto de entrada do sistema. Responsabilidades:
- Carregar bibliotecas necessárias
- Parsear argumentos de linha de comando
- Carregar configuração
- Despachar para modo `train` ou `predict`
- Tratamento de erros de alto nível

### 2. Configuração (`config-file.r`)

Gerencia parsing e validação do arquivo de configuração.

| Função | Descrição |
|--------|-----------|
| `parse_config()` | Interpreta e valida configuração completa |
| `valida_nomes_config()` | Verifica presença de chaves obrigatórias |
| `valida_tipos_config()` | Valida tipos de cada chave |
| `parsearg_janela()` | Interpreta janela temporal (S3 generic) |
| `parsearg_ids_usinas()` | Interpreta lista de usinas |

### 3. Consistência de Dados (`consistencia-dados.r`)

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

### 4. Treinamento (`train.r`)

Calibra modelos de regressão para cada usina.

| Função | Descrição |
|--------|-----------|
| `train_main()` | Orquestra treinamento para todas as usinas |
| `ajustar_usina()` | Processa uma usina individual |
| `ajusta_regressao_ger_irrad()` | Ajusta regressão por hora do dia |

#### Modelo de Regressão

Para cada hora `h` ∈ {05:00, 05:30, ..., 18:30}:

```
Geração_h = α_h × Irradiância_h
```

- Regressão linear sem intercepto (`lm(y ~ x + 0)`)
- Requer mínimo 10 pares válidos
- Valores zero tratados como NA antes do ajuste
- Fallback para quantil 70% se dados insuficientes

#### Artefato de Saída

```r
list(
    id_usina = "USINA_A",
    parametros = data.frame(
        a = c(0.12, 0.15, ...),  # coeficientes angulares
        b = c(0, 0, ...),        # sempre zero
        row.names = c("05:00", "05:30", ...)
    )
)
```

### 5. Previsão/Consolidação (`predict.r`)

Aplica consistência e gera histórico final.

| Função | Descrição |
|--------|-----------|
| `predict_main()` | Orquestra processamento de todas as usinas |
| `processar_usina()` | Processa uma usina individual |
| `organiza_resultados()` | Agrupa resultados por tipo (com/sem cortes) |
| `get_dataset()` | Carrega todos os dados necessários |

### 6. Preenchimento de Lacunas (`preenchimento-dados-faltantes.r`)

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

### 7. Utilitários (`utils.r`)

Funções auxiliares reutilizáveis.

| Função | Descrição |
|--------|-----------|
| `checa_valores_faltantes()` | Expande série para 30min, trata NaN/999 |
| `combina_dados_tempo()` | Merge temporal com sobreposição |
| `associa_nwp_usina()` | Encontra ponto NWP mais próximo (Haversine) |
| `adicionar_passo_previsao()` | Calcula D+0, D+1, etc. |
| `interpolar_30min()` | Interpola NWP de 1h para 30min |

### 8. Escrita (`escrita.r`)

Exportação de resultados.

| Função | Descrição |
|--------|-----------|
| `write_model_artifact()` | Salva modelo em RDS |
| `write_melhor_historico_geracao()` | Exporta MH em Parquet |
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
├── melhor_historico_geracao.csv     # MH anterior
└── melhor_historico_geracao_sem_cortes.csv
```

### Processamento Interno

```
pfvIO::conectamock_pfv()
    │
    ├── get_usinas()
    ├── get_geracao_observada()
    ├── get_irradiancia_prevista()
    ├── get_corte_observado()
    ├── get_melhor_historico_geracao()
    └── get_melhor_historico_geracao_sem_cortes()
```

### Saída

```
out/
├── melhor_historico_geracao.parquet
└── melhor_historico_geracao_sem_cortes.parquet

artifact/
└── {id_usina}.rds  # Um por usina
```

## Decisões de Design

### Por que data.table?

- Performance superior para datasets grandes (milhões de linhas)
- Sintaxe concisa para operações por grupo
- Modificação in-place eficiente em memória

### Por que regressão linear sem intercepto?

- Irradiância zero implica geração zero (físicamente correto)
- Modelo simples e interpretável
- Robusto com poucos dados
- Coeficiente α representa eficiência aproximada da planta

### Por que processar usinas individualmente?

- Permite paralelização futura trivial (`parallel::mclapply`)
- Isola falhas (uma usina com erro não afeta outras)
- Facilita debugging e logging por usina

### Por que dois históricos (com/sem cortes)?

- **Com cortes**: Reflete geração real observada
- **Sem cortes**: Estima geração potencial (útil para estudos de capacidade)

## Extensibilidade

### Adicionar nova fonte de dados

1. Atualizar `ordem_prioridade_fontes` no config
2. Garantir que dados sigam schema esperado
3. Lógica de combinação já é genérica

### Adicionar novo modelo NWP

1. Atualizar `ordem_prioridade_modelosNWP` no config
2. Garantir que coordenadas e timestamps estão corretos
3. Associação usina-NWP é automática (nearest neighbor)

### Modificar modelo de regressão

1. Alterar `ajusta_regressao_ger_irrad()` em `train.r`
2. Atualizar `substitui_por_estimativas()` em `preenchimento-dados-faltantes.r`
3. Manter interface do artefato (lista com `id_usina` e `parametros`)

## Dependências Externas

```
pfvIO (>= 0.2.2)
├── Leitura padronizada de dados
├── Validação de schemas
└── Conexão mock para testes

data.table (>= 1.17.0)
├── Manipulação de dados
└── Operações por grupo

lubridate (>= 1.9.4)
└── Manipulação de datas/horas

arrow (>= 22.0.0)
└── Leitura/escrita Parquet

lgr (>= 0.4.4)
└── Logging estruturado
```

## Performance

### Complexidade

| Operação | Complexidade |
|----------|-------------|
| Leitura de dados | O(N) |
| Detecção de congelados | O(N × janela) |
| Combinação de fontes | O(N × fontes) |
| Treinamento | O(N × horas) |
| Interpolação NWP | O(N) |

### Gargalos Conhecidos

1. **Associação NWP-usina**: Loop sobre usinas (pode ser vetorizado)
2. **Detecção de congelados**: Loop sobre série (poderia usar rolling com data.table)
3. **Ajuste de regressão**: Loop sobre horas (paralelizável)

### Otimizações Futuras

- Paralelização do loop de usinas
- Uso de `frollapply` para janela deslizante
- Cache de associações NWP-usina
