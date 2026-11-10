*&---------------------------------------------------------------------*
*& Report ZFI_CBOL_MONITOR
*& Monitor de NFs estornadas x boletos (projeto 2026-025)
*& Acoes por clique nas colunas de icone: banco, credito, reprocessar,
*& rejeitado e log.
*&---------------------------------------------------------------------*
REPORT zfi_cbol_monitor.

TABLES: zfi_cbol_mon.

TYPES: BEGIN OF ty_out,
         st_sefaz  TYPE icon_d,
         st_bol    TYPE icon_d,
         st_mb     TYPE icon_d,
         st_dl     TYPE icon_d,
         st_so     TYPE icon_d,
         st_banco  TYPE icon_d,
         st_cred   TYPE icon_d,
         bukrs     TYPE bukrs,
         nfenum    TYPE j_1bnfnum9,
         series    TYPE j_1bseries,
         kunnr     TYPE kunnr,
         faedt     TYPE d,
         belnr     TYPE belnr_d,
         gjahr     TYPE gjahr,
         buzei     TYPE buzei,
         stblg     TYPE stblg,
         vbeln_vf  TYPE vbeln_vf,
         vbeln_vl  TYPE vbeln_vl,
         mblnr     TYPE mblnr,
         vbeln_va  TYPE vbeln_va,
         hbkid     TYPE hbkid,
         anfbn     TYPE anfbn,
         tipo_txt  TYPE char20,
         erdat     TYPE d,
         ernam     TYPE syuname,
         autdat    TYPE d,
         bco_user  TYPE syuname,
         bco_data  TYPE d,
         bco_obs   TYPE char100,
         cred_user TYPE syuname,
         cred_data TYPE d,
         msg_erro  TYPE char100,
         docnum    TYPE j_1bdocnum,
         ac_bco    TYPE icon_d,
         ac_cred   TYPE icon_d,
         ac_rep    TYPE icon_d,
         ac_rej    TYPE icon_d,
         ac_log    TYPE icon_d,
       END OF ty_out,
       ty_t_out TYPE STANDARD TABLE OF ty_out WITH DEFAULT KEY.

SELECT-OPTIONS: s_bukrs FOR zfi_cbol_mon-bukrs,
                s_nfe   FOR zfi_cbol_mon-nfenum,
                s_kunnr FOR zfi_cbol_mon-kunnr,
                s_erdat FOR zfi_cbol_mon-erdat.
PARAMETERS: p_pend AS CHECKBOX DEFAULT 'X'.

INITIALIZATION.
  s_erdat-sign   = 'I'.
  s_erdat-option = 'BT'.
  s_erdat-low    = sy-datum - 30.
  s_erdat-high   = sy-datum.
  APPEND s_erdat.

CLASS lcl_mon DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-DATA: gt_out  TYPE ty_t_out,
                go_alv  TYPE REF TO cl_salv_table,
                go_cols TYPE REF TO cl_salv_columns_table.
    CLASS-METHODS:
      run,
      carregar,
      exibir,
      on_link_click FOR EVENT link_click OF cl_salv_events_table
        IMPORTING row column.
  PRIVATE SECTION.
    CLASS-METHODS:
      led IMPORTING iv_st TYPE char1 RETURNING VALUE(rv_icon) TYPE icon_d,
      key_de IMPORTING iv_row TYPE i RETURNING VALUE(rs_key) TYPE zfi_cbol_mon,
      mostrar_log IMPORTING is_out TYPE ty_out,
      confirmar IMPORTING iv_texto TYPE csequence RETURNING VALUE(rv_sim) TYPE abap_bool,
      pedir_obs RETURNING VALUE(rv_obs) TYPE char100,
      colunas,
      txt IMPORTING iv_col TYPE lvc_fname iv_s TYPE scrtext_s iv_m TYPE scrtext_m.
ENDCLASS.

START-OF-SELECTION.
  lcl_mon=>run( ).

CLASS lcl_mon IMPLEMENTATION.

  METHOD run.
    carregar( ).
    IF gt_out IS INITIAL.
      MESSAGE 'Nenhum registro encontrado' TYPE 'S'.
      RETURN.
    ENDIF.
    exibir( ).
  ENDMETHOD.

  METHOD led.
    CASE iv_st.
      WHEN 'X'. rv_icon = icon_led_green.
      WHEN 'E'. rv_icon = icon_led_red.
      WHEN ' '. rv_icon = icon_led_yellow.
      WHEN OTHERS. rv_icon = icon_led_inactive.   " '-' (nao se aplica) e 'S' (simulado)
    ENDCASE.
  ENDMETHOD.

  METHOD carregar.
    DATA: lt_mon  TYPE STANDARD TABLE OF zfi_cbol_mon,
          ls_out  TYPE ty_out,
          lv_stbl TYPE stblg,
          lt_aut  TYPE STANDARD TABLE OF bukrs,
          lv_pend TYPE abap_bool.
    FIELD-SYMBOLS <m> TYPE zfi_cbol_mon.

    SELECT * FROM zfi_cbol_mon INTO TABLE lt_mon
      WHERE bukrs IN s_bukrs AND nfenum IN s_nfe
        AND kunnr IN s_kunnr AND erdat IN s_erdat.
    SORT lt_mon BY erdat DESCENDING erzet DESCENDING nfenum buzei.

    LOOP AT lt_mon ASSIGNING <m>.
      " Somente empresas que o usuario pode exibir
      READ TABLE lt_aut TRANSPORTING NO FIELDS WITH KEY table_line = <m>-bukrs.
      IF sy-subrc <> 0.
        AUTHORITY-CHECK OBJECT 'F_BKPF_BUK' ID 'BUKRS' FIELD <m>-bukrs ID 'ACTVT' FIELD '03'.
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.
        APPEND <m>-bukrs TO lt_aut.
      ENDIF.

      " Pendente = falta banco (boleto), credito (pago), ou alguma etapa em aberto/erro
      IF p_pend = abap_true AND <m>-status = 'E'.
        lv_pend = boolc( ( <m>-tipo = 'B' AND <m>-bco_ok = ' ' ) OR
                         ( <m>-tipo = 'P' AND <m>-cred_ok = ' ' ) OR
                         <m>-st_mb = ' ' OR <m>-st_mb = 'E' OR
                         <m>-st_dl = ' ' OR <m>-st_dl = 'E' OR
                         <m>-st_so = ' ' OR <m>-st_so = 'E' ).
        IF lv_pend = abap_false.
          CONTINUE.
        ENDIF.
      ENDIF.

      " Documento contabil de estorno: leitura por chave (BKPF), so se ainda nao gravado
      IF <m>-status = 'E' AND <m>-stblg IS INITIAL.
        SELECT SINGLE stblg FROM bkpf INTO lv_stbl
          WHERE bukrs = <m>-bukrs AND belnr = <m>-belnr AND gjahr = <m>-gjahr.
        IF sy-subrc = 0 AND lv_stbl IS NOT INITIAL.
          <m>-stblg = lv_stbl.
          UPDATE zfi_cbol_mon SET stblg = lv_stbl
            WHERE bukrs = <m>-bukrs AND belnr = <m>-belnr
              AND gjahr = <m>-gjahr AND buzei = <m>-buzei.
        ENDIF.
      ENDIF.

      CLEAR ls_out.
      MOVE-CORRESPONDING <m> TO ls_out.
      CASE <m>-status.
        WHEN 'A'. ls_out-st_sefaz = icon_led_yellow.
        WHEN 'E'. ls_out-st_sefaz = icon_led_green.
        WHEN 'R'. ls_out-st_sefaz = icon_led_red.
      ENDCASE.
      ls_out-st_bol = led( <m>-st_bol ).
      ls_out-st_mb  = led( <m>-st_mb ).
      ls_out-st_dl  = led( <m>-st_dl ).
      ls_out-st_so  = led( <m>-st_so ).

      CASE <m>-tipo.
        WHEN 'B'.
          ls_out-tipo_txt = 'Boleto em banco'.
          ls_out-st_banco = COND #( WHEN <m>-bco_ok = 'X' THEN icon_led_green ELSE icon_led_red ).
          ls_out-st_cred  = icon_led_inactive.
        WHEN 'P'.
          ls_out-tipo_txt = 'TITULO PAGO'.
          ls_out-st_banco = icon_led_inactive.
          ls_out-st_cred  = COND #( WHEN <m>-cred_ok = 'X' THEN icon_led_green ELSE icon_led_red ).
      ENDCASE.

      ls_out-ac_bco  = icon_checked.
      ls_out-ac_cred = icon_execute_object.
      ls_out-ac_rep  = icon_refresh.
      ls_out-ac_rej  = icon_cancel.
      ls_out-ac_log  = icon_protocol.
      APPEND ls_out TO gt_out.
    ENDLOOP.
    COMMIT WORK.
  ENDMETHOD.

  METHOD txt.
    TRY.
        DATA(lo_c) = CAST cl_salv_column_table( go_cols->get_column( iv_col ) ).
        lo_c->set_short_text( iv_s ).
        lo_c->set_medium_text( iv_m ).
        lo_c->set_long_text( CONV #( iv_m ) ).
      CATCH cx_salv_not_found.
    ENDTRY.
  ENDMETHOD.

  METHOD colunas.
    DATA lo_cols TYPE REF TO cl_salv_columns_table.
    lo_cols = go_alv->get_columns( ).
    lo_cols->set_optimize( abap_true ).
    go_cols = lo_cols.


    txt( iv_col = 'ST_SEFAZ' iv_s = 'SEFAZ' iv_m = 'Cancelamento SEFAZ' ).
    txt( iv_col = 'ST_BOL' iv_s = 'Bol.SAP' iv_m = 'Dados do boleto limpos no SAP' ).
    txt( iv_col = 'ST_MB' iv_s = 'VL09' iv_m = 'Estorno mercadoria' ).
    txt( iv_col = 'ST_DL' iv_s = 'VL02N' iv_m = 'Remessa excluida' ).
    txt( iv_col = 'ST_SO' iv_s = 'VA02' iv_m = 'Ordem recusada' ).
    txt( iv_col = 'ST_BANCO' iv_s = 'Banco' iv_m = 'Cancelado no banco' ).
    txt( iv_col = 'ST_CRED' iv_s = 'Credito' iv_m = 'Credito lancado' ).
    txt( iv_col = 'TIPO_TXT' iv_s = 'Tipo' iv_m = 'Situacao do titulo' ).
    txt( iv_col = 'STBLG' iv_s = 'Doc.estor' iv_m = 'Doc. contabil estorno' ).
    txt( iv_col = 'AC_BCO' iv_s = 'OK Banco' iv_m = 'Confirmar cancelado no banco' ).
    txt( iv_col = 'AC_CRED' iv_s = 'OK Cred.' iv_m = 'Confirmar credito lancado' ).
    txt( iv_col = 'AC_REP' iv_s = 'Reproc.' iv_m = 'Reprocessar etapas com erro' ).
    txt( iv_col = 'AC_REJ' iv_s = 'Rejeit.' iv_m = 'SEFAZ rejeitou o cancelamento' ).
    txt( iv_col = 'AC_LOG' iv_s = 'Log' iv_m = 'Ver log da NF' ).
    txt( iv_col = 'BCO_USER' iv_s = 'Usu.banco' iv_m = 'Usuario confirmacao banco' ).
    txt( iv_col = 'BCO_DATA' iv_s = 'Dt.banco' iv_m = 'Data confirmacao banco' ).
    txt( iv_col = 'CRED_USER' iv_s = 'Usu.cred.' iv_m = 'Usuario credito' ).
    txt( iv_col = 'CRED_DATA' iv_s = 'Dt.cred.' iv_m = 'Data credito' ).
    txt( iv_col = 'ERDAT' iv_s = 'Dt.pedido' iv_m = 'Data pedido de estorno' ).
    txt( iv_col = 'ERNAM' iv_s = 'Usuario' iv_m = 'Usuario do estorno' ).
    txt( iv_col = 'AUTDAT' iv_s = 'Dt.SEFAZ' iv_m = 'Data autorizacao SEFAZ' ).
    txt( iv_col = 'MSG_ERRO' iv_s = 'Erro' iv_m = 'Ultimo erro' ).
    txt( iv_col = 'BCO_OBS' iv_s = 'Obs.banco' iv_m = 'Observacao banco' ).
    txt( iv_col = 'VBELN_VF' iv_s = 'Fatura' iv_m = 'Fatura SD' ).
    txt( iv_col = 'VBELN_VL' iv_s = 'Remessa' iv_m = 'Remessa' ).
    txt( iv_col = 'VBELN_VA' iv_s = 'Ordem' iv_m = 'Ordem de venda' ).
    txt( iv_col = 'MBLNR' iv_s = 'Doc.merc.' iv_m = 'Doc. de material' ).

    TRY.
        DATA(lo_hot) = CAST cl_salv_column_table( lo_cols->get_column( 'AC_BCO' ) ).
        lo_hot->set_cell_type( if_salv_c_cell_type=>hotspot ).
        lo_hot = CAST cl_salv_column_table( lo_cols->get_column( 'AC_CRED' ) ).
        lo_hot->set_cell_type( if_salv_c_cell_type=>hotspot ).
        lo_hot = CAST cl_salv_column_table( lo_cols->get_column( 'AC_REP' ) ).
        lo_hot->set_cell_type( if_salv_c_cell_type=>hotspot ).
        lo_hot = CAST cl_salv_column_table( lo_cols->get_column( 'AC_REJ' ) ).
        lo_hot->set_cell_type( if_salv_c_cell_type=>hotspot ).
        lo_hot = CAST cl_salv_column_table( lo_cols->get_column( 'AC_LOG' ) ).
        lo_hot->set_cell_type( if_salv_c_cell_type=>hotspot ).
        lo_cols->get_column( 'DOCNUM' )->set_visible( abap_false ).
      CATCH cx_salv_not_found.
    ENDTRY.
  ENDMETHOD.

  METHOD exibir.
    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = go_alv
                                CHANGING  t_table      = gt_out ).
        go_alv->get_functions( )->set_all( abap_true ).
        go_alv->get_display_settings( )->set_list_header(
          'Estorno de NF x boleto (clique nos icones de acao)' ).
        go_alv->get_display_settings( )->set_striped_pattern( abap_true ).
        colunas( ).
        SET HANDLER on_link_click FOR go_alv->get_event( ).
        go_alv->display( ).
      CATCH cx_salv_msg cx_salv_not_found INTO DATA(lo_err).
        MESSAGE lo_err->get_text( ) TYPE 'E'.
    ENDTRY.
  ENDMETHOD.

  METHOD key_de.
    DATA ls_out TYPE ty_out.
    READ TABLE gt_out INTO ls_out INDEX iv_row.
    rs_key-bukrs  = ls_out-bukrs.
    rs_key-belnr  = ls_out-belnr.
    rs_key-gjahr  = ls_out-gjahr.
    rs_key-buzei  = ls_out-buzei.
    rs_key-docnum = ls_out-docnum.
  ENDMETHOD.

  METHOD confirmar.
    DATA lv_ans TYPE c LENGTH 1.
    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        titlebar              = 'Confirmacao'
        text_question         = iv_texto
        text_button_1         = 'Sim'
        text_button_2         = 'Nao'
        default_button        = '2'
        display_cancel_button = space
      IMPORTING
        answer                = lv_ans.
    rv_sim = boolc( lv_ans = '1' ).
  ENDMETHOD.

  METHOD pedir_obs.
    DATA: lt_val TYPE STANDARD TABLE OF sval,
          ls_val TYPE sval,
          lv_rc  TYPE c LENGTH 1.
    ls_val-tabname   = 'ZFI_CBOL_MON'.
    ls_val-fieldname = 'BCO_OBS'.
    ls_val-fieldtext = 'Obs./protocolo do banco'.
    APPEND ls_val TO lt_val.
    CALL FUNCTION 'POPUP_GET_VALUES'
      EXPORTING
        popup_title = 'Cancelamento no banco'
      IMPORTING
        returncode  = lv_rc
      TABLES
        fields      = lt_val.
    IF lv_rc = space.
      READ TABLE lt_val INTO ls_val INDEX 1.
      rv_obs = ls_val-value.
    ENDIF.
  ENDMETHOD.

  METHOD mostrar_log.
    DATA: lt_log TYPE STANDARD TABLE OF zfi_cbol_log,
          ls_log TYPE zfi_cbol_log,
          lt_txt TYPE STANDARD TABLE OF char255,
          lv_txt TYPE char255.
    SELECT * FROM zfi_cbol_log INTO TABLE lt_log
      WHERE docnum = is_out-docnum ORDER BY seq.
    LOOP AT lt_log INTO ls_log.
      lv_txt = |{ ls_log-erdat DATE = ENVIRONMENT } { ls_log-erzet TIME = ENVIRONMENT } { ls_log-ernam } [{ ls_log-etapa }] { ls_log-texto }|.
      APPEND lv_txt TO lt_txt.
    ENDLOOP.
    IF lt_txt IS INITIAL.
      MESSAGE 'Sem log para esta NF' TYPE 'S'.
      RETURN.
    ENDIF.
    CALL FUNCTION 'POPUP_WITH_TABLE_DISPLAY_OK'
      EXPORTING
        endpos_col   = 160
        endpos_row   = 25
        startpos_col = 2
        startpos_row = 2
        titletext    = 'Log da NF'
      TABLES
        valuetab     = lt_txt
      EXCEPTIONS
        break_off    = 1
        OTHERS       = 2.
  ENDMETHOD.

  METHOD on_link_click.
    DATA: ls_key TYPE zfi_cbol_mon,
          ls_out TYPE ty_out,
          ls_ret TYPE zcl_fi_cbol_util=>ty_ret,
          lv_obs TYPE char100.

    READ TABLE gt_out INTO ls_out INDEX row.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    ls_key = key_de( row ).

    CASE column.
      WHEN 'AC_LOG'.
        mostrar_log( ls_out ).
        RETURN.
      WHEN 'AC_BCO'.
        IF ls_out-st_banco = icon_led_inactive.
          RETURN.
        ENDIF.
        IF confirmar( |Confirmar que o boleto da NF { ls_out-nfenum } foi cancelado no banco?| ) = abap_false.
          RETURN.
        ENDIF.
        lv_obs = pedir_obs( ).
        ls_ret = zcl_fi_cbol_service=>confirmar_banco( is_key = ls_key iv_obs = lv_obs ).
      WHEN 'AC_CRED'.
        IF ls_out-st_cred = icon_led_inactive.
          RETURN.
        ENDIF.
        IF confirmar( |Confirmar que o credito da NF { ls_out-nfenum } foi lancado ao cliente?| ) = abap_false.
          RETURN.
        ENDIF.
        ls_ret = zcl_fi_cbol_service=>confirmar_credito( ls_key ).
      WHEN 'AC_REP'.
        IF confirmar( |Reprocessar as etapas com erro da NF { ls_out-nfenum }?| ) = abap_false.
          RETURN.
        ENDIF.
        zcl_fi_cbol_service=>reprocessar( ls_key-docnum ).
        zcl_fi_cbol_service=>processar_pendentes( ls_key-docnum ).
        ls_ret-ok = abap_true.
      WHEN 'AC_REJ'.
        IF confirmar( |Marcar que a SEFAZ rejeitou o cancelamento da NF { ls_out-nfenum }?| ) = abap_false.
          RETURN.
        ENDIF.
        ls_ret = zcl_fi_cbol_service=>marcar_rejeitado( ls_key ).
      WHEN OTHERS.
        RETURN.
    ENDCASE.

    IF ls_ret-ok = abap_true.
      COMMIT WORK AND WAIT.
      CLEAR gt_out.
      carregar( ).
      go_alv->refresh( ).
      MESSAGE 'Registro atualizado' TYPE 'S'.
    ELSE.
      ROLLBACK WORK.
      MESSAGE ls_ret-msg TYPE 'S' DISPLAY LIKE 'E'.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
