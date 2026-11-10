CLASS zcl_fi_cbol_service DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES ty_t_mon TYPE zcl_fi_cbol_titulo=>ty_t_mon.

    CONSTANTS:
      " STATUS do registro
      c_st_aguarda  TYPE char1 VALUE 'A',  " aguardando autorizacao SEFAZ
      c_st_estorno  TYPE char1 VALUE 'E',  " cancelamento autorizado
      c_st_rejeit   TYPE char1 VALUE 'R',  " cancelamento rejeitado
      " ST_BOL / ST_MB / ST_DL / ST_SO
      c_pend        TYPE char1 VALUE ' ',
      c_ok          TYPE char1 VALUE 'X',
      c_erro        TYPE char1 VALUE 'E',
      c_simul       TYPE char1 VALUE 'S',
      c_na          TYPE char1 VALUE '-'.

    CLASS-METHODS:
      "! Existe titulo ja pago na NF? (para o aviso na tela do estorno)
      tem_titulo_pago IMPORTING iv_docnum      TYPE j_1bdocnum
                      RETURNING VALUE(rv_pago) TYPE abap_bool,
      "! Etapa 1 - no pedido de estorno: guarda dados e grava monitor (nao altera o titulo).
      "! Nao faz COMMIT. Retorna ABAP_TRUE se houver titulo pago.
      registrar_pedido IMPORTING iv_docnum      TYPE j_1bdocnum
                       RETURNING VALUE(rv_pago) TYPE abap_bool,
      "! Etapa 2 - apos autorizacao SEFAZ: e-mail + VL09 + VL02N + VA02 (faz COMMIT)
      processar_pendentes IMPORTING iv_docnum TYPE j_1bdocnum OPTIONAL,
      "! Lembrete dos boletos ainda sem confirmacao de cancelamento no banco
      enviar_lembretes,
      confirmar_banco IMPORTING is_key  TYPE zfi_cbol_mon
                                iv_obs  TYPE csequence OPTIONAL
                      RETURNING VALUE(rs_ret) TYPE zcl_fi_cbol_util=>ty_ret,
      confirmar_credito IMPORTING is_key TYPE zfi_cbol_mon
                        RETURNING VALUE(rs_ret) TYPE zcl_fi_cbol_util=>ty_ret,
      "! SEFAZ rejeitou: marca o registro como rejeitado
      marcar_rejeitado IMPORTING is_key TYPE zfi_cbol_mon
                       RETURNING VALUE(rs_ret) TYPE zcl_fi_cbol_util=>ty_ret,
      "! Zera etapas com erro da NF para o job tentar de novo
      reprocessar IMPORTING iv_docnum TYPE j_1bdocnum.
  PRIVATE SECTION.
    CLASS-METHODS:
      autorizado IMPORTING iv_docnum TYPE j_1bdocnum
                 RETURNING VALUE(rv_ok) TYPE abap_bool,
      processar_nf IMPORTING iv_docnum TYPE j_1bdocnum,
      executar_etapas IMPORTING iv_docnum TYPE j_1bdocnum
                      CHANGING  cs_mon    TYPE zfi_cbol_mon,
      permitido IMPORTING iv_bukrs TYPE bukrs
                RETURNING VALUE(rv_ok) TYPE abap_bool.
ENDCLASS.

CLASS zcl_fi_cbol_service IMPLEMENTATION.

  METHOD tem_titulo_pago.
    DATA lt_mon TYPE ty_t_mon.
    FIELD-SYMBOLS <m> TYPE zfi_cbol_mon.
    lt_mon = zcl_fi_cbol_titulo=>ler_titulos( iv_docnum ).
    LOOP AT lt_mon ASSIGNING <m> WHERE tipo = zcl_fi_cbol_titulo=>c_tipo_pago.
      rv_pago = abap_true.
      RETURN.
    ENDLOOP.
  ENDMETHOD.

  METHOD registrar_pedido.
    DATA: lt_mon TYPE ty_t_mon,
          ls_old TYPE zfi_cbol_mon,
          ls_ret TYPE zcl_fi_cbol_util=>ty_ret,
          lv_ativo TYPE abap_bool.
    FIELD-SYMBOLS <m> TYPE zfi_cbol_mon.

    lt_mon = zcl_fi_cbol_titulo=>ler_titulos( iv_docnum ).
    lv_ativo = zcl_fi_cbol_config=>is_ativo( ).

    LOOP AT lt_mon ASSIGNING <m>.
      IF zcl_fi_cbol_config=>empresa_habilitada( <m>-bukrs ) = abap_false.
        CONTINUE.
      ENDIF.
      IF <m>-tipo = zcl_fi_cbol_titulo=>c_tipo_sem.
        zcl_fi_cbol_util=>gravar_log( iv_docnum = iv_docnum iv_bukrs = <m>-bukrs
          iv_belnr = <m>-belnr iv_gjahr = <m>-gjahr iv_buzei = <m>-buzei
          iv_etapa = 'REGISTRO' iv_tipo = 'I'
          iv_texto = 'Titulo sem boleto (sem solicitacao L/C): nada a fazer' ).
        CONTINUE.
      ENDIF.

      " Idempotente: nao repete se o titulo ja esta no monitor
      SELECT SINGLE * FROM zfi_cbol_mon INTO ls_old
        WHERE bukrs = <m>-bukrs AND belnr = <m>-belnr
          AND gjahr = <m>-gjahr AND buzei = <m>-buzei.
      IF sy-subrc = 0 AND ls_old-status <> c_st_rejeit.
        CONTINUE.
      ENDIF.

      <m>-status = c_st_aguarda.
      <m>-erdat  = sy-datum.
      <m>-erzet  = sy-uzeit.
      <m>-ernam  = sy-uname.
      <m>-st_mb  = c_pend.
      <m>-st_dl  = c_pend.
      <m>-st_so  = c_pend.

      IF <m>-tipo = zcl_fi_cbol_titulo=>c_tipo_boleto.
        " Nao altera o titulo aqui (estamos dentro do estorno da fatura).
        " Limpeza dos dados do boleto, se habilitada, ocorre ao confirmar o banco.
        IF lv_ativo = abap_false.
          <m>-st_bol = c_simul.
        ELSEIF zcl_fi_cbol_config=>limpar_titulo( ) = abap_true.
          <m>-st_bol = c_pend.
        ELSE.
          <m>-st_bol = c_na.
        ENDIF.
      ELSE.
        <m>-st_bol = c_na.   " titulo pago: sem baixa; financeiro lanca credito
        rv_pago = abap_true.
      ENDIF.

      MODIFY zfi_cbol_mon FROM <m>.
      zcl_fi_cbol_util=>gravar_log( iv_docnum = iv_docnum iv_bukrs = <m>-bukrs
        iv_belnr = <m>-belnr iv_gjahr = <m>-gjahr iv_buzei = <m>-buzei
        iv_etapa = 'REGISTRO' iv_tipo = COND #( WHEN <m>-st_bol = c_erro THEN 'E' ELSE 'S' )
        iv_texto = |Titulo registrado: tipo { <m>-tipo }, boleto SAP { <m>-st_bol } { <m>-msg_erro }| ).
    ENDLOOP.
  ENDMETHOD.

  METHOD autorizado.
    DATA lv_cancel TYPE j_1bcancel.
    SELECT SINGLE cancel FROM j_1bnfdoc INTO lv_cancel WHERE docnum = iv_docnum.
    rv_ok = boolc( sy-subrc = 0 AND lv_cancel = 'X' ).
  ENDMETHOD.

  METHOD processar_pendentes.
    DATA lt_doc TYPE STANDARD TABLE OF j_1bdocnum WITH DEFAULT KEY.
    FIELD-SYMBOLS <d> TYPE j_1bdocnum.

    IF iv_docnum IS NOT INITIAL.
      APPEND iv_docnum TO lt_doc.
    ELSE.
      " Pendentes: aguardando SEFAZ, ou autorizadas com e-mail/etapa em aberto
      SELECT DISTINCT docnum FROM zfi_cbol_mon INTO TABLE lt_doc
        WHERE status = c_st_aguarda.
      DATA lt_doc2 LIKE lt_doc.
      SELECT DISTINCT docnum FROM zfi_cbol_mon INTO TABLE lt_doc2
        WHERE status = c_st_estorno
          AND ( mail_env = ' ' OR st_mb = ' ' OR st_dl = ' ' OR st_so = ' ' ).
      APPEND LINES OF lt_doc2 TO lt_doc.
      SORT lt_doc.
      DELETE ADJACENT DUPLICATES FROM lt_doc.
    ENDIF.

    LOOP AT lt_doc ASSIGNING <d>.
      processar_nf( <d> ).
      COMMIT WORK AND WAIT.
    ENDLOOP.
  ENDMETHOD.

  METHOD processar_nf.
    DATA: lt_mon TYPE ty_t_mon,
          lv_mail_ok TYPE abap_bool VALUE abap_true.
    FIELD-SYMBOLS <m> TYPE zfi_cbol_mon.

    SELECT * FROM zfi_cbol_mon INTO TABLE lt_mon
      WHERE docnum = iv_docnum AND status IN (c_st_aguarda, c_st_estorno).
    IF lt_mon IS INITIAL.
      RETURN.
    ENDIF.

    READ TABLE lt_mon ASSIGNING <m> INDEX 1.
    IF <m>-status = c_st_aguarda.
      IF autorizado( iv_docnum ) = abap_false.
        RETURN.    " SEFAZ ainda nao autorizou
      ENDIF.
      LOOP AT lt_mon ASSIGNING <m>.
        <m>-status = c_st_estorno.
        <m>-autdat = sy-datum.
        <m>-autzet = sy-uzeit.
        MODIFY zfi_cbol_mon FROM <m>.
      ENDLOOP.
      zcl_fi_cbol_util=>gravar_log( iv_docnum = iv_docnum iv_etapa = 'SEFAZ'
        iv_tipo = 'S' iv_texto = 'Cancelamento autorizado pela SEFAZ' ).
    ENDIF.

    " E-mail (uma vez por NF; falha nao trava o estorno)
    READ TABLE lt_mon ASSIGNING <m> INDEX 1.
    IF <m>-mail_env IS INITIAL.
      lv_mail_ok = zcl_fi_cbol_mail=>enviar_aviso( lt_mon ).
      IF lv_mail_ok = abap_true.
        LOOP AT lt_mon ASSIGNING <m>.
          <m>-mail_env = 'X'.
          MODIFY zfi_cbol_mon FROM <m>.
        ENDLOOP.
      ENDIF.
    ENDIF.

    " Etapas logisticas (uma vez por NF, gravadas em todos os titulos)
    READ TABLE lt_mon ASSIGNING <m> INDEX 1.
    executar_etapas( EXPORTING iv_docnum = iv_docnum CHANGING cs_mon = <m> ).
    DATA(ls_ref) = <m>.
    LOOP AT lt_mon ASSIGNING <m>.
      <m>-st_mb = ls_ref-st_mb.
      <m>-st_dl = ls_ref-st_dl.
      <m>-st_so = ls_ref-st_so.
      <m>-msg_erro = ls_ref-msg_erro.
      MODIFY zfi_cbol_mon FROM <m>.
    ENDLOOP.
  ENDMETHOD.

  METHOD executar_etapas.
    DATA ls_ret TYPE zcl_fi_cbol_util=>ty_ret.
    DATA lv_ativo TYPE abap_bool.
    lv_ativo = zcl_fi_cbol_config=>is_ativo( ).

    " 1) VL09 - estorno do movimento de mercadoria
    IF cs_mon-st_mb = c_pend.
      IF cs_mon-vbeln_vl IS INITIAL OR cs_mon-mblnr IS INITIAL.
        cs_mon-st_mb = c_na.
      ELSEIF lv_ativo = abap_false.
        cs_mon-st_mb = c_simul.
      ELSE.
        ls_ret = zcl_fi_cbol_logistica=>estornar_mercadoria( cs_mon ).
        IF ls_ret-ok = abap_true.
          COMMIT WORK AND WAIT.
          cs_mon-st_mb = c_ok.
          cs_mon-msg_erro = space.
        ELSE.
          cs_mon-st_mb = c_erro.
          cs_mon-msg_erro = |VL09: { ls_ret-msg }|.
        ENDIF.
        zcl_fi_cbol_util=>gravar_log( iv_docnum = iv_docnum iv_etapa = 'VL09'
          iv_tipo = COND #( WHEN ls_ret-ok = abap_true THEN 'S' ELSE 'E' )
          iv_texto = COND #( WHEN ls_ret-ok = abap_true THEN 'Mercadoria estornada' ELSE ls_ret-msg ) ).
      ENDIF.
    ENDIF.

    " 2) VL02N - exclusao da remessa
    IF cs_mon-st_dl = c_pend AND ( cs_mon-st_mb = c_ok OR cs_mon-st_mb = c_na OR cs_mon-st_mb = c_simul ).
      IF cs_mon-vbeln_vl IS INITIAL.
        cs_mon-st_dl = c_na.
      ELSEIF lv_ativo = abap_false.
        cs_mon-st_dl = c_simul.
      ELSE.
        ls_ret = zcl_fi_cbol_logistica=>excluir_remessa( cs_mon ).
        IF ls_ret-ok = abap_true.
          COMMIT WORK AND WAIT.
          cs_mon-st_dl = c_ok.
          cs_mon-msg_erro = space.
        ELSE.
          cs_mon-st_dl = c_erro.
          cs_mon-msg_erro = |VL02N: { ls_ret-msg }|.
        ENDIF.
        zcl_fi_cbol_util=>gravar_log( iv_docnum = iv_docnum iv_etapa = 'VL02N'
          iv_tipo = COND #( WHEN ls_ret-ok = abap_true THEN 'S' ELSE 'E' )
          iv_texto = COND #( WHEN ls_ret-ok = abap_true THEN 'Remessa excluida' ELSE ls_ret-msg ) ).
      ENDIF.
    ENDIF.

    " 3) VA02 - recusa dos itens da ordem
    IF cs_mon-st_so = c_pend AND ( cs_mon-st_dl = c_ok OR cs_mon-st_dl = c_na OR cs_mon-st_dl = c_simul ).
      IF cs_mon-vbeln_va IS INITIAL.
        cs_mon-st_so = c_na.
      ELSEIF lv_ativo = abap_false.
        cs_mon-st_so = c_simul.
      ELSE.
        ls_ret = zcl_fi_cbol_logistica=>recusar_ordem( cs_mon ).
        IF ls_ret-ok = abap_true.
          cs_mon-st_so = c_ok.
          cs_mon-msg_erro = space.
        ELSE.
          cs_mon-st_so = c_erro.
          cs_mon-msg_erro = |VA02: { ls_ret-msg }|.
        ENDIF.
        zcl_fi_cbol_util=>gravar_log( iv_docnum = iv_docnum iv_etapa = 'VA02'
          iv_tipo = COND #( WHEN ls_ret-ok = abap_true THEN 'S' ELSE 'E' )
          iv_texto = COND #( WHEN ls_ret-ok = abap_true THEN 'Ordem recusada' ELSE ls_ret-msg ) ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD enviar_lembretes.
    DATA: lt_mon TYPE ty_t_mon,
          lv_dat TYPE d,
          lv_zet TYPE t,
          lv_h   TYPE i.
    lv_h = zcl_fi_cbol_config=>get_lembrete_horas( ).
    lv_dat = sy-datum.
    lv_zet = sy-uzeit.
    " limite = agora - N horas (aproximado por dias inteiros + horas)
    DATA(lv_ts_lim) = CONV timestamp( 0 ).
    GET TIME STAMP FIELD DATA(lv_ts_now).
    lv_ts_lim = cl_abap_tstmp=>subtractsecs( tstmp = lv_ts_now secs = lv_h * 3600 ).
    CONVERT TIME STAMP lv_ts_lim TIME ZONE sy-zonlo INTO DATE lv_dat TIME lv_zet.

    SELECT * FROM zfi_cbol_mon INTO TABLE lt_mon
      WHERE status = c_st_estorno AND tipo = zcl_fi_cbol_titulo=>c_tipo_boleto
        AND bco_ok = ' '
        AND ( autdat < lv_dat OR ( autdat = lv_dat AND autzet <= lv_zet ) ).
    IF lt_mon IS NOT INITIAL.
      zcl_fi_cbol_mail=>enviar_lembrete( lt_mon ).
    ENDIF.
  ENDMETHOD.

  METHOD permitido.
    AUTHORITY-CHECK OBJECT 'F_BKPF_BUK'
      ID 'BUKRS' FIELD iv_bukrs
      ID 'ACTVT' FIELD '02'.
    rv_ok = boolc( sy-subrc = 0 ).
  ENDMETHOD.

  METHOD confirmar_banco.
    DATA ls_mon TYPE zfi_cbol_mon.
    IF permitido( is_key-bukrs ) = abap_false.
      MESSAGE e005(zfi_cbol) WITH is_key-bukrs INTO rs_ret-msg.
      RETURN.
    ENDIF.
    SELECT SINGLE * FROM zfi_cbol_mon INTO ls_mon
      WHERE bukrs = is_key-bukrs AND belnr = is_key-belnr
        AND gjahr = is_key-gjahr AND buzei = is_key-buzei.
    IF sy-subrc <> 0.
      rs_ret-msg = 'Registro nao encontrado'.
      RETURN.
    ENDIF.
    IF ls_mon-st_bol = c_pend AND zcl_fi_cbol_config=>is_ativo( ) = abap_true
       AND zcl_fi_cbol_config=>limpar_titulo( ) = abap_true.
      DATA(ls_lim) = zcl_fi_cbol_titulo=>limpar_boleto( ls_mon ).
      IF ls_lim-ok = abap_true.
        ls_mon-st_bol = c_ok.
        ls_mon-msg_erro = space.
      ELSE.
        ls_mon-st_bol = c_erro.
        ls_mon-msg_erro = |Limpeza do titulo: { ls_lim-msg }|.
      ENDIF.
      zcl_fi_cbol_util=>gravar_log( iv_docnum = ls_mon-docnum iv_bukrs = ls_mon-bukrs
        iv_belnr = ls_mon-belnr iv_gjahr = ls_mon-gjahr iv_buzei = ls_mon-buzei
        iv_etapa = 'LIMPEZA' iv_tipo = COND #( WHEN ls_lim-ok = abap_true THEN 'S' ELSE 'W' )
        iv_texto = COND #( WHEN ls_lim-ok = abap_true THEN 'Dados do boleto limpos no titulo' ELSE ls_lim-msg ) ).
    ENDIF.
    ls_mon-bco_ok   = 'X'.
    ls_mon-bco_user = sy-uname.
    ls_mon-bco_data = sy-datum.
    ls_mon-bco_hora = sy-uzeit.
    ls_mon-bco_obs  = iv_obs.
    MODIFY zfi_cbol_mon FROM ls_mon.
    zcl_fi_cbol_util=>gravar_log( iv_docnum = ls_mon-docnum iv_bukrs = ls_mon-bukrs
      iv_belnr = ls_mon-belnr iv_gjahr = ls_mon-gjahr iv_buzei = ls_mon-buzei
      iv_etapa = 'BANCO' iv_tipo = 'S' iv_texto = 'Cancelamento no banco confirmado' ).
    rs_ret-ok = abap_true.
  ENDMETHOD.

  METHOD confirmar_credito.
    DATA ls_mon TYPE zfi_cbol_mon.
    IF permitido( is_key-bukrs ) = abap_false.
      MESSAGE e005(zfi_cbol) WITH is_key-bukrs INTO rs_ret-msg.
      RETURN.
    ENDIF.
    SELECT SINGLE * FROM zfi_cbol_mon INTO ls_mon
      WHERE bukrs = is_key-bukrs AND belnr = is_key-belnr
        AND gjahr = is_key-gjahr AND buzei = is_key-buzei.
    IF sy-subrc <> 0.
      rs_ret-msg = 'Registro nao encontrado'.
      RETURN.
    ENDIF.
    ls_mon-cred_ok   = 'X'.
    ls_mon-cred_user = sy-uname.
    ls_mon-cred_data = sy-datum.
    ls_mon-cred_hora = sy-uzeit.
    MODIFY zfi_cbol_mon FROM ls_mon.
    zcl_fi_cbol_util=>gravar_log( iv_docnum = ls_mon-docnum iv_bukrs = ls_mon-bukrs
      iv_belnr = ls_mon-belnr iv_gjahr = ls_mon-gjahr iv_buzei = ls_mon-buzei
      iv_etapa = 'CREDITO' iv_tipo = 'S' iv_texto = 'Credito ao cliente lancado' ).
    rs_ret-ok = abap_true.
  ENDMETHOD.

  METHOD marcar_rejeitado.
    DATA ls_mon TYPE zfi_cbol_mon.
    IF permitido( is_key-bukrs ) = abap_false.
      MESSAGE e005(zfi_cbol) WITH is_key-bukrs INTO rs_ret-msg.
      RETURN.
    ENDIF.
    SELECT SINGLE * FROM zfi_cbol_mon INTO ls_mon
      WHERE bukrs = is_key-bukrs AND belnr = is_key-belnr
        AND gjahr = is_key-gjahr AND buzei = is_key-buzei.
    IF sy-subrc <> 0 OR ls_mon-status <> c_st_aguarda.
      rs_ret-msg = 'So vale para registro aguardando SEFAZ'.
      RETURN.
    ENDIF.
    ls_mon-status = c_st_rejeit.
    MODIFY zfi_cbol_mon FROM ls_mon.
    zcl_fi_cbol_util=>gravar_log( iv_docnum = ls_mon-docnum iv_bukrs = ls_mon-bukrs
      iv_belnr = ls_mon-belnr iv_gjahr = ls_mon-gjahr iv_buzei = ls_mon-buzei
      iv_etapa = 'SEFAZ' iv_tipo = 'W' iv_texto = 'SEFAZ rejeitou o cancelamento da NF' ).
    rs_ret-ok = abap_true.
  ENDMETHOD.

  METHOD reprocessar.
    UPDATE zfi_cbol_mon SET st_mb = ' ' WHERE docnum = iv_docnum AND st_mb = 'E'.
    UPDATE zfi_cbol_mon SET st_dl = ' ' WHERE docnum = iv_docnum AND st_dl = 'E'.
    UPDATE zfi_cbol_mon SET st_so = ' ' WHERE docnum = iv_docnum AND st_so = 'E'.
    UPDATE zfi_cbol_mon SET msg_erro = ' ' WHERE docnum = iv_docnum.
  ENDMETHOD.

ENDCLASS.
