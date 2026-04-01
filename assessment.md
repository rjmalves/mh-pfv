# Provenance simplification

- Estratégia de provenance: substituir o objeto provenance como conhecemos hoje por um environment do R.
- Ao invés de retornar um vetor de models e realizar a atualização de provenance e escrita do artifact de maneira síncrona ao final do paralelismo, registrar o nome da usina que rodar com sucesso nesse novo environment e escrever o artifact dentro do lapply
- Ao final da rodada, escrever o provenance em json assim como é feito atualmente, para permitir a existência de checkpoints.

# Strategy refactoring

- Para o model strategy, no futuro vamos querer ter uma dependência externa para evitar reimplementações
- Agora, vamos corrigir no mh-pfv para ter um formato definitivo, adequar no pfv-sh e depois externalizamos.
- Não está legal as funções operarem dinâmicamente na "strategy"
- Model deve ser uma genérica que recebe uma string "strategy" e argumentos que devem ser paralelizados para todo mundo
- A função predict não deveria precisar de receber strategy e model ao mesmo tempo.
- Não faz sentido construir um objeto vazio e depois chamar fit e depois predict, não é para usar orientação a objeto pura. Melhor despachar dinamicamente no modelo direto (genérica)
- fit_model deve ser só uma organizadora de outras chamadas
- Daí pra frente é tudo método S3 normal (predict, metadata, etc.)
