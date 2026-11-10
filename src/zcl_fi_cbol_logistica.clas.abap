CLASS zcl_fi_cbol_logistica DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CLASS-METHODS:
      "! VL09: estorna o movimento de mercadoria da remessa
      estornar_mercadoria IMPORTING is_mon        TYPE zfi_cbol_mon
                          RETURNING VALUE(rs_ret) TYPE zcl_fi_cbol_util=>ty_ret,
      "! VL02N: exclui a remessa
      excluir_remessa IMPORTING is_mon        TYPE zfi_cbol_mon
                      RETURNING VALUE(rs_ret) TYPE zcl_fi_cbol_util=>ty_ret,
      "! VA02: recusa os itens da ordem faturados na NF
      recusar_ordem IMPORTING is_mon        TYPE zfi_cbol_mon
                    RETURNING VALUE(rs_ret) TYPE zcl_fi_cbol_util=>ty_ret.
ENDCLASS.

CLASS zcl_fi_cbol_logistica IMPLEMENTATION.

  METHOD estornar_mercadoria.
    " Chamada dinamica: parametros conferidos em runtime (validar na SE37)
    DATA: lt_ptab  TYPE abap_func_parmbind_tab,
          ls_p     TYPE abap_func_parmbind,
          lt_etab  TYPE abap_func_excpbind_tab,
          ls_e     TYPE abap_func_excpbind,
          lt_mesg  TYPE STANDARD TABLE OF mesg,
          lv_vbeln TYPE vbeln_vl,
          lv_budat TYPE budat,
          lv_count TYPE i VALUE 1,
          lv_mblnr TYPE mblnr,
          lv_mjahr TYPE mjahr,
          lv_vbtyp TYPE char1 VALUE 'J',
          lv_tcode TYPE sytcode VALUE 'VL09',
          lo_err   TYPE REF TO cx_root.

    lv_vbeln = is_mon-vbeln_vl.
    lv_budat = sy-datum.
    lv_mblnr = is_mon-mblnr.
    lv_mjahr = is_mon-mjahr.

    IF zcl_fi_cbol_util=>fm_existe( 'WS_REVERSE_GOODS_ISSUE' ) = abap_false.
      rs_ret-msg = 'FM WS_REVERSE_GOODS_ISSUE nao existe no sistema'.
      RETURN.
    ENDIF.

    ls_p-name = 'I_VBELN'. ls_p-kind = abap_func_exporting.
    GET REFERENCE OF lv_vbeln INTO ls_p-value. INSERT ls_p INTO TABLE lt_ptab.
    ls_p-name = 'I_BUDAT'. ls_p-kind = abap_func_exporting.
    GET REFERENCE OF lv_budat INTO ls_p-value. INSERT ls_p INTO TABLE lt_ptab.
    ls_p-name = 'I_COUNT'. ls_p-kind = abap_func_exporting.
    GET REFERENCE OF lv_count INTO ls_p-value. INSERT ls_p INTO TABLE lt_ptab.
    ls_p-name = 'I_MBLNR'. ls_p-kind = abap_func_exporting.
    GET REFERENCE OF lv_mblnr INTO ls_p-value. INSERT ls_p INTO TABLE lt_ptab.
    ls_p-name = 'I_MJAHR'. ls_p-kind = abap_func_exporting.
    GET REFERENCE OF lv_mjahr INTO ls_p-value. INSERT ls_p INTO TABLE lt_ptab.
    ls_p-name = 'I_VBTYP'. ls_p-kind = abap_func_exporting.
    GET REFERENCE OF lv_vbtyp INTO ls_p-value. INSERT ls_p INTO TABLE lt_ptab.
    ls_p-name = 'I_TCODE'. ls_p-kind = abap_func_exporting.
    GET REFERENCE OF lv_tcode INTO ls_p-value. INSERT ls_p INTO TABLE lt_ptab.
    ls_p-name = 'T_MESG'. ls_p-kind = abap_func_tables.
    GET REFERENCE OF lt_mesg INTO ls_p-value. INSERT ls_p INTO TABLE lt_ptab.
    ls_e-name = 'OTHERS'. ls_e-value = 1. INSERT ls_e INTO TABLE lt_etab.

    TRY.
        CALL FUNCTION 'WS_REVERSE_GOODS_ISSUE'
          PARAMETER-TABLE lt_ptab
          EXCEPTION-TABLE lt_etab.
        IF sy-subrc = 0.
          rs_ret-ok = abap_true.
        ELSE.
          rs_ret-msg = zcl_fi_cbol_util=>msg_sy( ).
          IF rs_ret-msg IS INITIAL.
            rs_ret-msg = zcl_fi_cbol_util=>texto_tabela( lt_mesg ).
            IF rs_ret-msg IS INITIAL.
              rs_ret-msg = 'Estorno de mercadoria (VL09) retornou excecao'.
            ENDIF.
          ENDIF.
        ENDIF.
      CATCH cx_root INTO lo_err.
        rs_ret-msg = lo_err->get_text( ).
    ENDTRY.
  ENDMETHOD.

  METHOD excluir_remessa.
    " Exclusao da remessa (VL02N > Remessa > Excluir) = WS_DELIVERY_UPDATE_2 com
    " VBKOK_WA-LIKP_DEL = 'X' e o numero da remessa em DELIVERY. Chamada dinamica.
    DATA: lt_ptab  TYPE abap_func_parmbind_tab,
          ls_p     TYPE abap_func_parmbind,
          lt_etab  TYPE abap_func_excpbind_tab,
          ls_e     TYPE abap_func_excpbind,
          ls_vbkok TYPE vbkok,
          lt_prot  TYPE STANDARD TABLE OF prott,
          lv_vbeln TYPE vbeln_vl,
          lv_sync  TYPE char1 VALUE 'X',
          lv_com   TYPE char1 VALUE 'X',
          lv_erro  TYPE xfeld,
          lo_err   TYPE REF TO cx_root.
    FIELD-SYMBOLS <f> TYPE any.

    lv_vbeln = is_mon-vbeln_vl.

    DEFINE _set.
      ASSIGN COMPONENT &1 OF STRUCTURE ls_vbkok TO <f>.
      IF sy-subrc = 0.
        <f> = &2.
      ENDIF.
    END-OF-DEFINITION.
    _set 'VBELN_VL' lv_vbeln.
    _set 'VBELN'    lv_vbeln.
    _set 'VBTYP_VL' 'J'.
    _set 'LIKP_DEL' 'X'.

    IF zcl_fi_cbol_util=>fm_existe( 'WS_DELIVERY_UPDATE_2' ) = abap_false.
      rs_ret-msg = 'FM WS_DELIVERY_UPDATE_2 nao existe no sistema'.
      RETURN.
    ENDIF.

    ls_p-name = 'VBKOK_WA'. ls_p-kind = abap_func_exporting.
    GET REFERENCE OF ls_vbkok INTO ls_p-value. INSERT ls_p INTO TABLE lt_ptab.
    ls_p-name = 'DELIVERY'. ls_p-kind = abap_func_exporting.
    GET REFERENCE OF lv_vbeln INTO ls_p-value. INSERT ls_p INTO TABLE lt_ptab.
    ls_p-name = 'SYNCHRON'. ls_p-kind = abap_func_exporting.
    GET REFERENCE OF lv_sync INTO ls_p-value. INSERT ls_p INTO TABLE lt_ptab.
    ls_p-name = 'COMMIT'. ls_p-kind = abap_func_exporting.
    GET REFERENCE OF lv_com INTO ls_p-value. INSERT ls_p INTO TABLE lt_ptab.
    ls_p-name = 'EF_ERROR_ANY'. ls_p-kind = abap_func_importing.
    GET REFERENCE OF lv_erro INTO ls_p-value. INSERT ls_p INTO TABLE lt_ptab.
    ls_p-name = 'PROT'. ls_p-kind = abap_func_tables.
    GET REFERENCE OF lt_prot INTO ls_p-value. INSERT ls_p INTO TABLE lt_ptab.
    ls_e-name = 'OTHERS'. ls_e-value = 1. INSERT ls_e INTO TABLE lt_etab.

    TRY.
        CALL FUNCTION 'WS_DELIVERY_UPDATE_2'
          PARAMETER-TABLE lt_ptab
          EXCEPTION-TABLE lt_etab.
        IF sy-subrc = 0 AND lv_erro IS INITIAL.
          rs_ret-ok = abap_true.
        ELSE.
          rs_ret-msg = zcl_fi_cbol_util=>texto_tabela( lt_prot ).
          IF rs_ret-msg IS INITIAL.
            rs_ret-msg = 'Exclusao de remessa (VL02N) retornou erro'.
          ENDIF.
        ENDIF.
      CATCH cx_root INTO lo_err.
        rs_ret-msg = lo_err->get_text( ).
    ENDTRY.
  ENDMETHOD.

  METHOD recusar_ordem.
    " Recusa por item (motivo na TVARV ZFI_CBOL_ABGRU, padrao Z1)
    DATA: lt_vbrp   TYPE STANDARD TABLE OF vbrp,
          ls_vbrp   TYPE vbrp,
          ls_hdrx   TYPE bapisdh1x,
          lt_item   TYPE STANDARD TABLE OF bapisditm,
          ls_item   TYPE bapisditm,
          lt_itemx  TYPE STANDARD TABLE OF bapisditmx,
          ls_itemx  TYPE bapisditmx,
          lt_ret    TYPE STANDARD TABLE OF bapiret2,
          ls_ret    TYPE bapiret2,
          lv_abgru  TYPE abgru_va,
          lv_erro   TYPE abap_bool.

    IF is_mon-vbeln_va IS INITIAL.
      rs_ret-ok = abap_true.
      RETURN.
    ENDIF.
    lv_abgru = zcl_fi_cbol_config=>get_abgru( ).

    SELECT * FROM vbrp INTO TABLE lt_vbrp WHERE vbeln = is_mon-vbeln_vf.
    LOOP AT lt_vbrp INTO ls_vbrp WHERE aupos IS NOT INITIAL.
      CLEAR: ls_item, ls_itemx.
      ls_item-itm_number  = ls_vbrp-aupos.
      ls_item-reason_rej  = lv_abgru.
      ls_itemx-itm_number = ls_vbrp-aupos.
      ls_itemx-updateflag = 'U'.
      ls_itemx-reason_rej = 'X'.
      APPEND ls_item  TO lt_item.
      APPEND ls_itemx TO lt_itemx.
    ENDLOOP.
    IF lt_item IS INITIAL.
      rs_ret-ok = abap_true.
      RETURN.
    ENDIF.

    ls_hdrx-updateflag = 'U'.
    CALL FUNCTION 'BAPI_SALESORDER_CHANGE'
      EXPORTING
        salesdocument    = is_mon-vbeln_va
        order_header_inx = ls_hdrx
      TABLES
        return           = lt_ret
        order_item_in    = lt_item
        order_item_inx   = lt_itemx.

    LOOP AT lt_ret INTO ls_ret WHERE type CA 'AEX'.
      lv_erro = abap_true.
      rs_ret-msg = ls_ret-message.
      EXIT.
    ENDLOOP.

    IF lv_erro = abap_true.
      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    ELSE.
      CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
        EXPORTING
          wait = 'X'.
      rs_ret-ok = abap_true.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
