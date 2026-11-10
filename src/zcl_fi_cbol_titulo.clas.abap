CLASS zcl_fi_cbol_titulo DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES ty_t_mon TYPE STANDARD TABLE OF zfi_cbol_mon WITH DEFAULT KEY.

    CONSTANTS:
      c_tipo_boleto TYPE char1 VALUE 'B',  " boleto gerado, titulo em aberto
      c_tipo_pago   TYPE char1 VALUE 'P',  " boleto gerado, titulo ja compensado
      c_tipo_sem    TYPE char1 VALUE 'N',  " sem boleto (bonificacao, a vista...)
      c_atribuicao  TYPE dzuonr VALUE 'NF cancelada'.

    CLASS-METHODS:
      "! Le os titulos de cliente da NF (acesso por chave; BSEG so por documento)
      ler_titulos IMPORTING iv_docnum     TYPE j_1bdocnum
                  RETURNING VALUE(rt_mon) TYPE ty_t_mon,
      "! Remove os dados do boleto do titulo e troca a atribuicao
      limpar_boleto IMPORTING is_mon        TYPE zfi_cbol_mon
                    RETURNING VALUE(rs_ret) TYPE zcl_fi_cbol_util=>ty_ret,
      "! Devolve ao titulo os dados guardados no monitor
      restaurar_boleto IMPORTING is_mon        TYPE zfi_cbol_mon
                       RETURNING VALUE(rs_ret) TYPE zcl_fi_cbol_util=>ty_ret.
  PRIVATE SECTION.
    TYPES: BEGIN OF ty_chg,
             fdname TYPE char30,
             newval TYPE char60,
           END OF ty_chg,
           ty_t_chg TYPE STANDARD TABLE OF ty_chg WITH DEFAULT KEY.
    CLASS-METHODS:
      alterar_titulo IMPORTING is_mon        TYPE zfi_cbol_mon
                               it_chg        TYPE ty_t_chg
                     RETURNING VALUE(rs_ret) TYPE zcl_fi_cbol_util=>ty_ret.
ENDCLASS.

CLASS zcl_fi_cbol_titulo IMPLEMENTATION.

  METHOD ler_titulos.
    DATA: ls_doc   TYPE j_1bnfdoc,
          lt_lin   TYPE STANDARD TABLE OF j_1bnflin,
          ls_lin   TYPE j_1bnflin,
          lv_vf    TYPE vbeln_vf,
          ls_vbrk  TYPE vbrk,
          lt_vbrp  TYPE STANDARD TABLE OF vbrp,
          ls_vbrp  TYPE vbrp,
          lv_vl    TYPE vbeln_vl,
          lv_va    TYPE vbeln_va,
          lv_mblnr TYPE mblnr,
          lv_mjahr TYPE mjahr,
          lt_bseg  TYPE STANDARD TABLE OF bseg,
          ls_bseg  TYPE bseg,
          ls_mon   TYPE zfi_cbol_mon.

    SELECT SINGLE * FROM j_1bnfdoc INTO ls_doc WHERE docnum = iv_docnum.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    " Fatura de origem da NF (REFKEY comeca com o numero da fatura)
    SELECT * FROM j_1bnflin INTO TABLE lt_lin
      WHERE docnum = iv_docnum AND reftyp = 'BI'.
    READ TABLE lt_lin INTO ls_lin INDEX 1.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    lv_vf = ls_lin-refkey(10).

    SELECT SINGLE * FROM vbrk INTO ls_vbrk WHERE vbeln = lv_vf.
    IF sy-subrc <> 0 OR ls_vbrk-belnr IS INITIAL.
      RETURN.
    ENDIF.

    " Remessa e ordem de origem
    SELECT * FROM vbrp INTO TABLE lt_vbrp WHERE vbeln = lv_vf.
    READ TABLE lt_vbrp INTO ls_vbrp INDEX 1.
    IF sy-subrc = 0.
      lv_va = ls_vbrp-aubel.
      IF ls_vbrp-vgtyp = 'J'.
        lv_vl = ls_vbrp-vgbel.
      ENDIF.
    ENDIF.

    " Movimento de mercadoria da remessa (fluxo de documentos, chave VBELV)
    IF lv_vl IS NOT INITIAL.
      SELECT vbeln mjahr FROM vbfa INTO (lv_mblnr, lv_mjahr) UP TO 1 ROWS
        WHERE vbelv = lv_vl AND vbtyp_n = 'R'
        ORDER BY vbeln.
      ENDSELECT.
    ENDIF.

    " BSEG somente pela chave do documento (cluster): sem filtro por campo livre
    SELECT * FROM bseg INTO TABLE lt_bseg
      WHERE bukrs = ls_vbrk-bukrs
        AND belnr = ls_vbrk-belnr
        AND gjahr = ls_vbrk-gjahr.

    LOOP AT lt_bseg INTO ls_bseg WHERE koart = 'D'.
      CLEAR ls_mon.
      ls_mon-bukrs    = ls_bseg-bukrs.
      ls_mon-belnr    = ls_bseg-belnr.
      ls_mon-gjahr    = ls_bseg-gjahr.
      ls_mon-buzei    = ls_bseg-buzei.
      ls_mon-docnum   = iv_docnum.
      ls_mon-nfenum   = ls_doc-nfenum.
      ls_mon-series   = ls_doc-series.
      ls_mon-kunnr    = ls_bseg-kunnr.
      ls_mon-vbeln_vf = lv_vf.
      ls_mon-vbeln_vl = lv_vl.
      ls_mon-vbeln_va = lv_va.
      ls_mon-mblnr    = lv_mblnr.
      ls_mon-mjahr    = lv_mjahr.
      ls_mon-faedt    = ls_bseg-zfbdt + ls_bseg-zbd1t.
      ls_mon-hbkid    = ls_bseg-hbkid.
      ls_mon-hktid    = ls_bseg-hktid.
      ls_mon-bvtyp    = ls_bseg-bvtyp.
      ls_mon-anfbn    = ls_bseg-anfbn.
      ls_mon-anfbu    = ls_bseg-anfbu.
      ls_mon-anfbj    = ls_bseg-anfbj.
      ls_mon-zuonr    = ls_bseg-zuonr.
      IF ls_bseg-anfbn IS INITIAL.
        ls_mon-tipo = c_tipo_sem.
      ELSEIF ls_bseg-augbl IS NOT INITIAL.
        ls_mon-tipo = c_tipo_pago.
      ELSE.
        ls_mon-tipo = c_tipo_boleto.
      ENDIF.
      APPEND ls_mon TO rt_mon.
    ENDLOOP.
  ENDMETHOD.

  METHOD limpar_boleto.
    DATA: lt_chg TYPE ty_t_chg,
          ls_chg TYPE ty_chg.

    DEFINE _add.
      ls_chg-fdname = &1.
      ls_chg-newval = &2.
      APPEND ls_chg TO lt_chg.
    END-OF-DEFINITION.

    " Campos mostrados na tela "Outros dados" do titulo (BSEG)
    _add 'HBKID' ''.
    _add 'HKTID' ''.
    _add 'BVTYP' ''.
    _add 'ANFBN' ''.
    _add 'ANFBU' ''.
    _add 'ANFBJ' ''.
    _add 'ZUONR' c_atribuicao.

    rs_ret = alterar_titulo( is_mon = is_mon it_chg = lt_chg ).
  ENDMETHOD.

  METHOD restaurar_boleto.
    DATA: lt_chg TYPE ty_t_chg,
          ls_chg TYPE ty_chg.

    DEFINE _add.
      ls_chg-fdname = &1.
      ls_chg-newval = &2.
      APPEND ls_chg TO lt_chg.
    END-OF-DEFINITION.

    _add 'HBKID' is_mon-hbkid.
    _add 'HKTID' is_mon-hktid.
    _add 'BVTYP' is_mon-bvtyp.
    _add 'ANFBN' is_mon-anfbn.
    _add 'ANFBU' is_mon-anfbu.
    _add 'ANFBJ' is_mon-anfbj.
    _add 'ZUONR' is_mon-zuonr.

    rs_ret = alterar_titulo( is_mon = is_mon it_chg = lt_chg ).
  ENDMETHOD.

  METHOD alterar_titulo.
    " FI_DOCUMENT_CHANGE chamada de forma dinamica: se a assinatura for
    " diferente no sistema, o erro aparece no monitor (nao na ativacao).
    " O COMMIT WORK fica por conta de quem chama.
    DATA: lt_acc  TYPE STANDARD TABLE OF accchg,
          ls_acc  TYPE accchg,
          lt_ptab TYPE abap_func_parmbind_tab,
          ls_p    TYPE abap_func_parmbind,
          lt_etab TYPE abap_func_excpbind_tab,
          ls_e    TYPE abap_func_excpbind,
          lv_bukrs TYPE bukrs,
          lv_belnr TYPE belnr_d,
          lv_gjahr TYPE gjahr,
          lo_err  TYPE REF TO cx_root.
    FIELD-SYMBOLS: <c> TYPE ty_chg,
                   <f> TYPE any.

    lv_bukrs = is_mon-bukrs.
    lv_belnr = is_mon-belnr.
    lv_gjahr = is_mon-gjahr.

    LOOP AT it_chg ASSIGNING <c>.
      CLEAR ls_acc.
      ASSIGN COMPONENT 'BUZEI' OF STRUCTURE ls_acc TO <f>.
      IF sy-subrc = 0.
        <f> = is_mon-buzei.
      ENDIF.
      ASSIGN COMPONENT 'FDNAME' OF STRUCTURE ls_acc TO <f>.
      IF sy-subrc = 0.
        <f> = <c>-fdname.
      ENDIF.
      ASSIGN COMPONENT 'NEWVAL' OF STRUCTURE ls_acc TO <f>.
      IF sy-subrc = 0.
        <f> = <c>-newval.
      ENDIF.
      APPEND ls_acc TO lt_acc.
    ENDLOOP.

    ls_p-name = 'I_BUKRS'. ls_p-kind = abap_func_exporting.
    GET REFERENCE OF lv_bukrs INTO ls_p-value. INSERT ls_p INTO TABLE lt_ptab.
    ls_p-name = 'I_BELNR'. ls_p-kind = abap_func_exporting.
    GET REFERENCE OF lv_belnr INTO ls_p-value. INSERT ls_p INTO TABLE lt_ptab.
    ls_p-name = 'I_GJAHR'. ls_p-kind = abap_func_exporting.
    GET REFERENCE OF lv_gjahr INTO ls_p-value. INSERT ls_p INTO TABLE lt_ptab.
    ls_p-name = 'T_ACCCHG'. ls_p-kind = abap_func_tables.
    GET REFERENCE OF lt_acc INTO ls_p-value. INSERT ls_p INTO TABLE lt_ptab.
    ls_e-name = 'OTHERS'. ls_e-value = 1. INSERT ls_e INTO TABLE lt_etab.

    IF zcl_fi_cbol_util=>fm_existe( 'FI_DOCUMENT_CHANGE' ) = abap_false.
      rs_ret-msg = 'FM FI_DOCUMENT_CHANGE nao existe no sistema'.
      RETURN.
    ENDIF.

    TRY.
        CALL FUNCTION 'FI_DOCUMENT_CHANGE'
          PARAMETER-TABLE lt_ptab
          EXCEPTION-TABLE lt_etab.
        IF sy-subrc = 0.
          rs_ret-ok = abap_true.
        ELSE.
          rs_ret-msg = zcl_fi_cbol_util=>msg_sy( ).
          IF rs_ret-msg IS INITIAL.
            rs_ret-msg = 'FI_DOCUMENT_CHANGE retornou excecao'.
          ENDIF.
        ENDIF.
      CATCH cx_root INTO lo_err.
        rs_ret-msg = lo_err->get_text( ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
