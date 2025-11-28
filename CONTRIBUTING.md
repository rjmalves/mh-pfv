# Contribuindo para o mhpfv

Obrigado pelo interesse em contribuir! Este documento fornece diretrizes para contribuições ao projeto.

## 📋 Índice

- [Como Contribuir](#como-contribuir)
- [Configuração do Ambiente](#configuração-do-ambiente)
- [Padrões de Código](#padrões-de-código)
- [Testes](#testes)
- [Documentação](#documentação)
- [Processo de Pull Request](#processo-de-pull-request)

---

## 🤝 Como Contribuir

### Reportando Bugs

1. Verifique se o bug já não foi reportado nas [Issues](https://github.com/rjmalves/melhor-historico-solar/issues)
2. Se não encontrar, crie uma nova issue usando o template de bug report
3. Inclua:
   - Descrição clara do problema
   - Passos para reproduzir
   - Comportamento esperado vs. observado
   - Versão do R e do pacote
   - Logs de erro (se aplicável)

### Sugerindo Melhorias

1. Abra uma issue usando o template de feature request
2. Descreva:
   - O problema que a melhoria resolve
   - A solução proposta
   - Alternativas consideradas

### Contribuindo com Código

1. Fork o repositório
2. Crie uma branch para sua feature (`git checkout -b feature/minha-feature`)
3. Faça commits atômicos com mensagens descritivas
4. Escreva/atualize testes para suas mudanças
5. Garanta que todos os testes passam
6. Abra um Pull Request

---

## 🛠️ Configuração do Ambiente

### Pré-requisitos

- R >= 4.0
- Visual Studio Code (recomendado) ou outra IDE
- Git

### Setup Inicial

```bash
# Clone seu fork
git clone https://github.com/SEU_USUARIO/melhor-historico-solar.git
cd melhor-historico-solar

# Adicione o upstream
git remote add upstream https://github.com/rjmalves/melhor-historico-solar.git

# Restaure as dependências com renv
Rscript -e "renv::restore()"

# Instale dependências de desenvolvimento
Rscript -e "install.packages(c('devtools', 'testthat', 'lintr', 'roxygen2', 'covr', 'cyclocomp'))"
```

### Verificando a Instalação

```r
# No R
devtools::load_all()   # Carrega o pacote em desenvolvimento
devtools::test()       # Executa os testes
devtools::check()      # Verificação completa
```

---

## 📐 Padrões de Código

### Estilo

Seguimos o [tidyverse style guide](https://style.tidyverse.org/) com algumas customizações definidas em `.lintr`:

```r
# Configurações principais:
# - Linha máxima: 120 caracteres
# - Indentação: 4 espaços
# - Nomes: snake_case
```

### Verificação de Estilo

```r
# Executar linter
lintr::lint_package()

# Ou para um arquivo específico
lintr::lint("R/meu_arquivo.r")
```

### Boas Práticas R

Seguimos os princípios do [Advanced R](https://adv-r.hadley.nz/):

#### 1. Funções Puras e Pequenas

```r
# ✅ Bom: função focada, sem efeitos colaterais
calcular_mae <- function(observado, previsto) {
    stopifnot(
        is.numeric(observado),
        is.numeric(previsto),
        length(observado) == length(previsto)
    )
    mean(abs(observado - previsto), na.rm = TRUE)
}

# ❌ Evitar: funções grandes com múltiplas responsabilidades
```

#### 2. Validação de Entrada

```r
# ✅ Bom: validar tipos e dimensões
processar_dados <- function(dt, coluna) {
    if (!is.data.table(dt)) {
        stop("'dt' deve ser um data.table")
    }
    if (!coluna %in% names(dt)) {
        stop(sprintf("Coluna '%s' não encontrada", coluna))
    }
    # ...
}
```

#### 3. Operações Vetorizadas

```r
# ✅ Bom: vetorizado
valores_normalizados <- (valores - min(valores)) / (max(valores) - min(valores))

# ❌ Evitar: loops explícitos quando desnecessários
for (i in seq_along(valores)) {
    valores_normalizados[i] <- (valores[i] - min(valores)) / (max(valores) - min(valores))
}
```

#### 4. data.table Idiomático

```r
# ✅ Bom: sintaxe data.table
dt[, valor_ajustado := valor * fator, by = id_usina]
dt[is.na(valor), valor := 0]

# ❌ Evitar: misturar com dplyr ou base R desnecessariamente
```

#### 5. Tratamento de Erros

```r
# ✅ Bom: mensagens informativas
if (nrow(dados) == 0) {
    stop(
        "Nenhum dado encontrado para a usina '", id_usina, "' ",
        "no período de ", data_inicio, " a ", data_fim
    )
}
```

---

## 🧪 Testes

### Estrutura de Testes

```
tests/
├── testthat.r           # Runner principal
└── testthat/
    ├── data/            # Dados de teste
    ├── test-config-file.r
    ├── test-consistencia-dados.r
    ├── test-predict.r
    ├── test-train.r
    └── test-utils.r
```

### Escrevendo Testes

```r
test_that("funcao_exemplo retorna resultado esperado", {
    # Arrange: preparar dados
    entrada <- data.table(valor = c(1, 2, 3, NA, 5))

    # Act: executar função
    resultado <- funcao_exemplo(entrada)

    # Assert: verificar resultado
    expect_equal(nrow(resultado), 5)
    expect_true(all(!is.na(resultado$valor)))
})
```

### Executando Testes

```r
# Todos os testes
devtools::test()

# Teste específico
devtools::test(filter = "config-file")

# Com cobertura
covr::package_coverage()
```

### Requisitos de Cobertura

- Novas funções públicas devem ter testes
- Casos de borda (NA, vazios, tipos errados) devem ser testados
- Testes devem ser independentes e reprodutíveis

---

## 📝 Documentação

### Roxygen2

Todas as funções exportadas devem ter documentação completa:

```r
#' Título Curto da Função
#'
#' Descrição mais detalhada do que a função faz,
#' quando usar, e qualquer contexto relevante.
#'
#' @param x Descrição do parâmetro x. Tipo esperado.
#' @param y Descrição do parâmetro y. Valor default.
#'
#' @return Descrição do retorno, incluindo tipo e estrutura.
#'
#' @details
#' Detalhes adicionais sobre o algoritmo, complexidade,
#' ou considerações importantes.
#' Se for exportada pelo pacote, deve ter exemplos.
#'
#' @examples
#' \dontrun{
#' resultado <- minha_funcao(dados, opcao = TRUE)
#' }
#'
#' @seealso [funcao_relacionada()]
#'
#' @export
minha_funcao <- function(x, y = TRUE) {
    # implementação
}
```

### Gerando Documentação

```r
# Atualizar documentação
devtools::document()

# Verificar se há warnings
devtools::check_man()
```

---

## 🔄 Processo de Pull Request

### Antes de Abrir o PR

1. **Sincronize com upstream**

   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. **Execute verificações locais**

   ```r
   devtools::document()  # Atualiza documentação
   devtools::test()      # Testes passam
   lintr::lint_package() # Sem erros de lint
   devtools::check()     # Check completo passa
   ```

3. **Commits organizados**
   - Mensagens descritivas em português ou inglês
   - Um commit por mudança lógica
   - Formato: `tipo: descrição curta`
     - `feat:` nova funcionalidade
     - `fix:` correção de bug
     - `docs:` documentação
     - `test:` testes
     - `refactor:` refatoração

### Template do PR

```markdown
## Descrição

Breve descrição das mudanças.

## Tipo de Mudança

- [ ] Bug fix
- [ ] Nova feature
- [ ] Breaking change
- [ ] Documentação

## Checklist

- [ ] Testes adicionados/atualizados
- [ ] Documentação atualizada
- [ ] `devtools::check()` passa sem erros
- [ ] Código segue os padrões do projeto

## Issues Relacionadas

Closes #123
```

### Revisão

- PRs requerem pelo menos 1 aprovação
- CI deve passar (testes, lint, check)
- Discussões devem ser resolvidas antes do merge

---

## 🏷️ Versionamento

Seguimos [Semantic Versioning](https://semver.org/):

- **MAJOR**: mudanças incompatíveis na API
- **MINOR**: novas funcionalidades compatíveis
- **PATCH**: correções de bugs compatíveis

Atualize o `DESCRIPTION` e `CHANGELOG.md` ao lançar versões.

---

## ❓ Dúvidas?

- Abra uma [Discussion](https://github.com/ONS/melhor-historico-solar/discussions) para perguntas gerais
- Use [Issues](https://github.com/ONS/melhor-historico-solar/issues) para bugs e features
- Consulte a documentação existente

Obrigado por contribuir! 🎉
