# Changelog

Todas as mudanças notáveis deste projeto serão documentadas neste arquivo.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/),
e este projeto adere ao [Semantic Versioning](https://semver.org/lang/pt-BR/).

## [Unreleased]

### Added
- Documentação completa do projeto (README, CONTRIBUTING, ARCHITECTURE, MODEL_CARD)
- GitHub Actions para CI/CD (R-CMD-check, lint, testes)
- Templates de issues e pull requests

### Changed
- Reorganização dos dados de teste para `tests/testthat/fixtures/`

### Fixed
- Correção de links roxygen2 para funções internas

---

## [0.1.0] - 2025-11-28

### Added
- Implementação inicial do pipeline de consistência de dados
- Modo `train`: treinamento de modelos de regressão linear por hora
- Modo `predict`: geração do melhor histórico consolidado
- Detecção de valores congelados com janela deslizante
- Combinação de múltiplas fontes de dados por prioridade
- Preenchimento de lacunas usando previsões NWP
- Suporte a configuração via arquivo JSONC
- Logging estruturado com `lgr`
- Exportação em formato Parquet
- Dockerfile para containerização
- Testes unitários com `testthat`
- Linting com `lintr`

### Dependencies
- R >= 4.0
- data.table >= 1.17.0
- lubridate >= 1.9.4
- arrow >= 22.0.0
- argparse >= 2.2.5
- lgr >= 0.4.4
- pfvIO >= 0.2.2

---

## Tipos de Mudanças

- **Added**: para novas funcionalidades
- **Changed**: para mudanças em funcionalidades existentes
- **Deprecated**: para funcionalidades que serão removidas em breve
- **Removed**: para funcionalidades removidas
- **Fixed**: para correções de bugs
- **Security**: para correções de vulnerabilidades
