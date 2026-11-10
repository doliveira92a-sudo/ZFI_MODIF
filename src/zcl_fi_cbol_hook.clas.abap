CLASS zcl_fi_cbol_hook DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CLASS-METHODS:
      "! Chamar no ponto da J1BNFE onde hoje sai a mensagem 368 ("titulo em banco"),
      "! no lugar do bloqueio. Nunca levanta excecao: qualquer erro vai para o log
      "! e o estorno segue o fluxo normal.
      "! RV_CONTINUAR = ABAP_FALSE somente se o usuario recusar no aviso de titulo pago.
      on_estorno_solicitado IMPORTING iv_docnum           TYPE j_1bdocnum
                            RETURNING VALUE(rv_continuar) TYPE abap_bool.
ENDCLASS.

CLASS zcl_fi_cbol_hook IMPLEMENTATION.

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
