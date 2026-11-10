CLASS zcl_fi_cbol_mail DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CLASS-METHODS:
      "! Aviso apos autorizacao SEFAZ: boleto a cancelar no banco e/ou titulo pago
      "! Retorna ABAP_TRUE se nada precisava ser enviado ou se o envio foi aceito
      enviar_aviso IMPORTING it_mon       TYPE zcl_fi_cbol_titulo=>ty_t_mon
                   RETURNING VALUE(rv_ok) TYPE abap_bool,
      enviar_lembrete IMPORTING it_mon TYPE zcl_fi_cbol_titulo=>ty_t_mon.
  PRIVATE SECTION.
    CLASS-METHODS:
      linhas IMPORTING is_mon TYPE zfi_cbol_mon
             CHANGING  ct_txt TYPE soli_tab,
      adicionar IMPORTING iv_txt TYPE csequence
          CHANGING  ct_txt TYPE soli_tab,
      enviar IMPORTING iv_assunto   TYPE so_obj_des
                       it_corpo     TYPE soli_tab
             RETURNING VALUE(rv_ok) TYPE abap_bool.
ENDCLASS.

CLASS zcl_fi_cbol_mail IMPLEMENTATION.

  METHOD adicionar.
    DATA ls_line TYPE soli.
    ls_line-line = iv_txt.
    APPEND ls_line TO ct_txt.
  ENDMETHOD.

  METHOD linhas.
    adicionar( EXPORTING iv_txt = |NF { is_mon-nfenum } serie { is_mon-series } - cliente { is_mon-kunnr }|
         CHANGING ct_txt = ct_txt ).
    adicionar( EXPORTING iv_txt = |  Empresa { is_mon-bukrs }  Doc. contabil { is_mon-belnr }/{ is_mon-gjahr } item { is_mon-buzei }|
         CHANGING ct_txt = ct_txt ).
    adicionar( EXPORTING iv_txt = |  Banco empresa { is_mon-hbkid }  Solicitacao L/C { is_mon-anfbn }/{ is_mon-anfbu }/{ is_mon-anfbj }|
         CHANGING ct_txt = ct_txt ).
    adicionar( EXPORTING iv_txt = |  Vencimento { is_mon-faedt DATE = ENVIRONMENT }|
         CHANGING ct_txt = ct_txt ).
    adicionar( EXPORTING iv_txt = ` `
         CHANGING ct_txt = ct_txt ).
  ENDMETHOD.

  METHOD enviar_aviso.
    DATA: lt_b   TYPE soli_tab,
          lt_p   TYPE soli_tab,
          lt_h   TYPE soli_tab,
          lv_nf  TYPE j_1bnfnum9,
          lv_ok1 TYPE abap_bool VALUE abap_true,
          lv_ok2 TYPE abap_bool VALUE abap_true.
    FIELD-SYMBOLS <m> TYPE zfi_cbol_mon.

    LOOP AT it_mon ASSIGNING <m>.
      lv_nf = <m>-nfenum.
      CASE <m>-tipo.
        WHEN zcl_fi_cbol_titulo=>c_tipo_boleto.
          linhas( EXPORTING is_mon = <m> CHANGING ct_txt = lt_b ).
        WHEN zcl_fi_cbol_titulo=>c_tipo_pago.
          linhas( EXPORTING is_mon = <m> CHANGING ct_txt = lt_p ).
      ENDCASE.
    ENDLOOP.

    IF lt_b IS NOT INITIAL.
      adicionar( EXPORTING iv_txt = 'Estorno da NF autorizado pela SEFAZ. Boleto(s) ja baixado(s) no SAP.'
                 CHANGING ct_txt = lt_h ).
      adicionar( EXPORTING iv_txt = ` ` CHANGING ct_txt = lt_h ).
      APPEND LINES OF lt_b TO lt_h.
      adicionar( EXPORTING iv_txt = 'Cancele o(s) boleto(s) acima no banco e marque no monitor ZFI_CBOL.'
                 CHANGING ct_txt = lt_h ).
      lv_ok1 = enviar( iv_assunto = |Estorno NF { lv_nf }: cancelar boleto no banco|
                       it_corpo   = lt_h ).
    ENDIF.

    IF lt_p IS NOT INITIAL.
      CLEAR lt_h.
      adicionar( EXPORTING iv_txt = 'Estorno da NF autorizado, mas o(s) titulo(s) abaixo ja foi(ram) pago(s):'
                 CHANGING ct_txt = lt_h ).
      adicionar( EXPORTING iv_txt = ` ` CHANGING ct_txt = lt_h ).
      APPEND LINES OF lt_p TO lt_h.
      adicionar( EXPORTING iv_txt = 'Lancar credito ao cliente e marcar no monitor ZFI_CBOL.'
                 CHANGING ct_txt = lt_h ).
      lv_ok2 = enviar( iv_assunto = |ATENCAO NF { lv_nf } estornada com titulo pago: lancar credito|
                       it_corpo   = lt_h ).
    ENDIF.

    rv_ok = boolc( lv_ok1 = abap_true AND lv_ok2 = abap_true ).
  ENDMETHOD.

  METHOD enviar_lembrete.
    DATA lt_txt TYPE soli_tab.
    FIELD-SYMBOLS <m> TYPE zfi_cbol_mon.
    adicionar( EXPORTING iv_txt = 'Boletos ainda sem confirmacao de cancelamento no banco:'
         CHANGING ct_txt = lt_txt ).
    LOOP AT it_mon ASSIGNING <m>.
      linhas( EXPORTING is_mon = <m> CHANGING ct_txt = lt_txt ).
    ENDLOOP.
    enviar( iv_assunto = 'Lembrete: boletos pendentes de cancelamento no banco'
            it_corpo   = lt_txt ).
  ENDMETHOD.

  METHOD enviar.
    DATA: lt_mail TYPE bcsy_smtpa,
          lv_mail TYPE ad_smtpadr,
          lv_rem  TYPE ad_smtpadr,
          lo_req  TYPE REF TO cl_bcs,
          lo_doc  TYPE REF TO cl_document_bcs,
          lo_rec  TYPE REF TO if_recipient_bcs,
          lo_send TYPE REF TO if_sender_bcs,
          lo_err  TYPE REF TO cx_bcs.

    lt_mail = zcl_fi_cbol_config=>get_emails( ).
    IF lt_mail IS INITIAL.
      RETURN.   " sem destinatarios na TVARV: tenta de novo no job
    ENDIF.

    TRY.
        lo_req = cl_bcs=>create_persistent( ).
        lo_doc = cl_document_bcs=>create_document(
                   i_type    = 'RAW'
                   i_subject = iv_assunto
                   i_text    = it_corpo ).
        lo_req->set_document( lo_doc ).

        lv_rem = zcl_fi_cbol_config=>get_remetente( ).
        IF lv_rem IS NOT INITIAL.
          lo_send = cl_cam_address_bcs=>create_internet_address( lv_rem ).
          lo_req->set_sender( lo_send ).
        ENDIF.

        LOOP AT lt_mail INTO lv_mail.
          lo_rec = cl_cam_address_bcs=>create_internet_address( lv_mail ).
          lo_req->add_recipient( i_recipient = lo_rec ).
        ENDLOOP.

        lo_req->set_send_immediately( abap_true ).
        rv_ok = lo_req->send( ).
        COMMIT WORK.
      CATCH cx_bcs INTO lo_err.
        rv_ok = abap_false.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
