CLASS zcl_fi_cbol_hook DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CLASS-METHODS:
      "! Chamar no user exit USEREXIT_NUMBER_RANGE_INV_DATE (include RV60AFZC), no
      "! lugar do bloqueio "titulo em banco". IV_AWKEY = chave de referencia do
      "! documento contabil (BKPF-AWKEY = numero da fatura). Nunca levanta excecao.
      "! RV_CONTINUAR = ABAP_FALSE somente se o usuario recusar o aviso de titulo pago.
      on_estorno_fatura IMPORTING iv_awkey            TYPE awkey
                        RETURNING VALUE(rv_continuar) TYPE abap_bool,
      "! Mesma regra, partindo do DOCNUM da NF
      on_estorno_solicitado IMPORTING iv_docnum           TYPE j_1bdocnum
                            RETURNING VALUE(rv_continuar) TYPE abap_bool.
ENDCLASS.

CLASS zcl_fi_cbol_hook IMPLEMENTATION.

  METHOD on_estorno_fatura.
    DATA: lv_vbeln  TYPE vbeln_vf,
          lv_refkey TYPE j_1brefkey,
          lv_docnum TYPE j_1bdocnum,
          lo_err    TYPE REF TO cx_root.

    rv_continuar = abap_true.
    TRY.
        lv_vbeln  = iv_awkey(10).
        lv_refkey = lv_vbeln.
        SELECT docnum FROM j_1bnflin INTO lv_docnum UP TO 1 ROWS
          WHERE reftyp = 'BI' AND refkey = lv_refkey.
        ENDSELECT.
        IF sy-subrc <> 0.
          RETURN.      " fatura sem NF: nada a fazer
        ENDIF.
        rv_continuar = on_estorno_solicitado( lv_docnum ).
      CATCH cx_root INTO lo_err.
        rv_continuar = abap_true.
    ENDTRY.
  ENDMETHOD.

  METHOD on_estorno_solicitado.
    DATA: lv_pago TYPE abap_bool,
          lv_ans  TYPE c LENGTH 1,
          lv_txt  TYPE string,
          lo_err  TYPE REF TO cx_root.

    rv_continuar = abap_true.

    TRY.
        " Aviso (sem bloquear) quando houver titulo pago, so em dialogo
        IF sy-batch = abap_false.
          lv_pago = zcl_fi_cbol_service=>tem_titulo_pago( iv_docnum ).
          IF lv_pago = abap_true.
            lv_txt = |A NF { iv_docnum ALPHA = OUT } tem titulo ja pago. Se prosseguir, sera preciso lancar credito ao cliente (processo manual). Prosseguir com o estorno?|.
            CALL FUNCTION 'POPUP_TO_CONFIRM'
              EXPORTING
                titlebar              = 'Titulo pago'
                text_question         = lv_txt
                text_button_1         = 'Prosseguir'
                text_button_2         = 'Cancelar'
                default_button        = '2'
                display_cancel_button = space
              IMPORTING
                answer                = lv_ans.
            IF lv_ans <> '1'.
              rv_continuar = abap_false.
              RETURN.
            ENDIF.
          ENDIF.
        ENDIF.

        zcl_fi_cbol_service=>registrar_pedido( iv_docnum ).

      CATCH cx_root INTO lo_err.
        zcl_fi_cbol_util=>gravar_log( iv_docnum = iv_docnum iv_etapa = 'GANCHO'
          iv_tipo = 'E' iv_texto = lo_err->get_text( ) ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
