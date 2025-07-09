# Fluxo de Consistência para Cada Usina

- **consiste_geracao_unit()**
  - checa_valores_faltantes()
  - checa_valores_congelados() _(Dados novos)_
    - remove_congelados()
  - checa_valores_overbound()
  - combina_fontes()
    - combina_dados()
  - checa_valores_faltantes()  _(Histórico MHG)_
  - combina_dados_tempo()      _(Une histórico com dados novos)_

- **consiste_vento_unit()**
  - checa_valores_faltantes()
  - checa_valores_congelados()
    - remove_congelados()
  - checa_valores_overbound()
  - combina_fontes()
    - ajusta_regressao_fontes_vento()
    - elimina_dados_por_R2()
    - elimina_pontos_distantes()
    - ajusta_fontes_vento()
    - combina_dados()
  - checa_valores_faltantes()  _(Histórico MHV)_
  - combina_dados_tempo()      _(Une histórico com dados novos)_
