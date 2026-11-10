*&---------------------------------------------------------------------*
*& Report ZFI_CBOL_JOB
*& Job de apoio do estorno NF x boleto (projeto 2026-025):
*&  - sem parametros: processa NFs aguardando SEFAZ / etapas pendentes
*&    (agendar a cada poucos minutos)
*&  - P_LEMB: envia lembrete dos boletos sem confirmacao no banco
*&    (agendar 1x ao dia)
*&  - P_REG + P_DOCNUM: teste manual da etapa 1 (pedido de estorno) para
*&    uma NF, sem depender do gancho na J1BNFE
*&---------------------------------------------------------------------*
REPORT zfi_cbol_job.

PARAMETERS: p_docnum TYPE j_1bdocnum,
            p_reg    AS CHECKBOX,
            p_lemb   AS CHECKBOX.

START-OF-SELECTION.
  DATA lv_pago TYPE abap_bool.

  IF p_reg = abap_true.
    IF p_docnum IS INITIAL.
      MESSAGE 'Informe o numero do documento (DOCNUM) da NF' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    lv_pago = zcl_fi_cbol_service=>registrar_pedido( p_docnum ).
    COMMIT WORK AND WAIT.
    WRITE: / 'Etapa 1 executada para o DOCNUM', p_docnum.
    IF zcl_fi_cbol_config=>is_ativo( ) = abap_false.
      WRITE: / 'Modo SIMULACAO (TVARV ZFI_CBOL_MODO <> X): titulo nao foi alterado.'.
    ENDIF.
    IF lv_pago = abap_true.
      WRITE: / 'ATENCAO: ha titulo ja pago; sera preciso lancar credito ao cliente.'.
    ENDIF.
    WRITE: / 'Veja o resultado no monitor ZFI_CBOL.'.
    RETURN.
  ENDIF.

  zcl_fi_cbol_service=>processar_pendentes( p_docnum ).
  IF p_lemb = abap_true.
    zcl_fi_cbol_service=>enviar_lembretes( ).
  ENDIF.
  COMMIT WORK.
  WRITE: / 'Processamento concluido.'.
