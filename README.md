# `melhorhistoricosolar`

## Executando a `main.r`

Para executar o script principal, e necessario ter o pacote `melhorhistoricosolar` instalado. Isto
pode ser feito direto do repositorio com `remotes::install_github` ou a partir do repositorio local

```r
remotes::install_local(".", force = TRUE)
```

Recomenda-se instalacoes locais, e nao do repositorio remoto, pois este e fechado e demandaria mais
configuracoes desnecessarias no momento.

Finalmente, a `main.r` podera entao ser executada via linha de comando

```
$ Rscript main.r [-h] [--mode MODE] [--input INPUT] [--output OUTPUT]
              [--artifact ARTIFACT] [--data-inicio DATA_INICIO]
              [--data-fim DATA_FIM] [--ids-usinas IDS_USINAS]
              [--ordem-prioridade-fontes ORDEM_PRIORIDADE_FONTES]
              [--ordem-prioridade-modelosNWP ORDEM_PRIORIDADE_MODELOSNWP]
              [--fator-tolerancia-limite-superior-geracao FATOR_TOLERANCIA_LIMITE_SUPERIOR_GERACAO]
```

Que retornara descricao dos argumentos. Execucao em modo de debug pode ser realizada com

```
$ LOG_LEVEL='debug' Rscript main.r []