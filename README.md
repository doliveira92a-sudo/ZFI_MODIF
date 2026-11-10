# ZFI_MODIF

Customizacoes FI (SAP ECC, SAP_BASIS 7.40, idioma principal P). Pacote e repositorio abapGit: `ZFI_MODIF`.

## Projeto 2026-025 - Cancelamento automatico do boleto no estorno da NF

Ao estornar a NF (J1BNFE), o sistema baixa os dados do boleto no titulo, avisa o financeiro para cancelar no banco
e executa as etapas logisticas que hoje sao manuais.

### Fluxo

1. **Estorno da fatura** (gancho no user exit do VF11, rapido): para cada titulo de cliente da fatura da NF
   - sem `ANFBN` (Solicitacao L/C) preenchida: sem boleto (bonificacao, a vista) - so log;
   - com L/C e em aberto: guarda copia dos dados do boleto e grava no monitor (status *aguardando SEFAZ*). Opcionalmente (`ZFI_CBOL_LIMPAR`) limpa `HBKID/HKTID/BVTYP/ANFBN/ANFBU/ANFBJ` e troca a Atribuicao (`ZUONR`) para "NF cancelada";
   - titulo ja compensado (pago): aviso na tela, **nao bloqueia**; monitor marca "TITULO PAGO - lancar credito".
2. **Apos autorizacao da SEFAZ** (job `ZFI_CBOL_JOB`, a cada poucos minutos): e-mail de aviso (boleto a cancelar no banco ou titulo pago) e, em ordem, **VL09** (estorno de mercadoria), **VL02N** (excluir remessa) e **VA02** (recusa por item, motivo na TVARV). Cada etapa grava status; erro nao trava as demais NFs.
3. **Monitor `ZFI_CBOL`**: lista NFs estornadas, documentos ligados (fatura, remessa, doc. de material, ordem, doc. contabil de estorno), semaforos por etapa e colunas de acao (clique no icone): confirmar cancelado no banco, confirmar credito lancado, reprocessar, SEFAZ rejeitou, ver log.

Se a SEFAZ rejeitar o cancelamento, use "SEFAZ rejeitou" no monitor: os dados do boleto voltam ao titulo.

### Objetos

| Objeto | Funcao |
|---|---|
| `ZFI_CBOL_MON` / `ZFI_CBOL_LOG` | Monitor (1 linha por titulo) e log por NF |
| `ZCL_FI_CBOL_CONFIG` | Leitura da TVARV |
| `ZCL_FI_CBOL_TITULO` | Leitura/alteracao do titulo (BSEG so por chave do documento) |
| `ZCL_FI_CBOL_LOGISTICA` | VL09, VL02N, VA02 |
| `ZCL_FI_CBOL_SERVICE` | Orquestracao e confirmacoes |
| `ZCL_FI_CBOL_MAIL` | E-mails (SAPconnect) |
| `ZCL_FI_CBOL_HOOK` | Ponto de chamada seguro para a J1BNFE (nunca levanta excecao) |
| `ZFI_CBOL_MONITOR` (+ tcode `ZFI_CBOL`) | Monitor ALV |
| `ZFI_CBOL_JOB` | Job de processamento / lembretes / teste manual |
| `ZFI_CBOL_SETUP` | Cria as variaveis da TVARV |
| `ZFI_CBOL` (MSAG) | Mensagens |

Autorizacao: objeto padrao `F_BKPF_BUK` (ACTVT 03 exibir; 02 confirmar/reprocessar).

### TVARV (nao transportada - rodar `ZFI_CBOL_SETUP` em cada sistema)

| Variavel | Tipo | Uso |
|---|---|---|
| `ZFI_CBOL_MODO` | P | `S` = simulacao (padrao), `X` = ativo |
| `ZFI_CBOL_EMAIL` | S | Destinatarios (uma linha por e-mail) - preencher na STVARV |
| `ZFI_CBOL_BUKRS` | S | Empresas habilitadas (vazio = todas) |
| `ZFI_CBOL_ABGRU` | P | Motivo de recusa da VA02 (padrao `Z1`) |
| `ZFI_CBOL_LEMBRETE_H` | P | Horas ate o lembrete de pendencia no banco |
| `ZFI_CBOL_LIMPAR` | P | `X` = alem de registrar, limpa os dados do boleto no titulo (padrao vazio: so registra) |
| `ZFI_CBOL_REMETENTE` | P | Remetente (opcional) |

### Jobs

- `ZFI_CBOL_JOB` sem parametros: a cada poucos minutos.
- `ZFI_CBOL_JOB` com `P_LEMB`: 1x ao dia.

### Pendente

- **Gancho (manual, fora do abapGit)**: o bloqueio "titulo em banco" (mensagem 00/368) esta no user exit
  `USEREXIT_NUMBER_RANGE_INV_DATE` do include `RV60AFZC` (estorno da fatura, VF11). Como e include do padrao,
  o abapGit nao o leva: alterar no DEV e transportar. Substituir o trecho "verifica dados do titulo em aberto":

```abap
** verifica se foi gerado documento contabil
    SELECT * FROM bkpf
    WHERE awtyp = AWTYP AND
          awkey = beleg.
      EXIT.
    ENDSELECT.
    check sy-subrc IS INITIAL.

** projeto 2026-025: registra o boleto no monitor ZFI_CBOL (nao bloqueia mais)
    IF zcl_fi_cbol_hook=>on_estorno_fatura( bkpf-awkey ) = abap_false.
      message e368(00) with 'Estorno cancelado pelo usuario' 'titulo ja pago'.
    ENDIF.
```

  O hook nunca levanta excecao; so devolve `abap_false` se o usuario recusar o aviso de titulo pago (somente em dialogo).
- Chamadas dinamicas a validar no DEV/QAS (assinatura na SE37): `FI_DOCUMENT_CHANGE`,
  `WS_REVERSE_GOODS_ISSUE`, `WS_DELIVERY_UPDATE_2`. Erro de parametro aparece no monitor, nao na ativacao.
- Testar com usuario do Faturamento (autorizacao para alterar o titulo).

### Teste no QAS (sugestao)

1. `ZFI_CBOL_SETUP`; preencher `ZFI_CBOL_EMAIL` (modo continua `S`).
2. `ZFI_CBOL_JOB` com `P_REG` + DOCNUM de NF de teste: valida leitura dos titulos e o monitor sem alterar nada.
3. Trocar `ZFI_CBOL_MODO` para `X` e repetir; conferir o titulo na FBL5N.
