CLASS zcl_fi_cbol_util DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_ret,
             ok  TYPE abap_bool,
             msg TYPE char200,
           END OF ty_ret.

    CLASS-METHODS:
      "! Grava linha de log (COMMIT feito por quem chama)
      gravar_log IMPORTING iv_docnum TYPE j_1bdocnum
                    iv_bukrs  TYPE bukrs OPTIONAL
                    iv_belnr  TYPE belnr_d OPTIONAL
                    iv_gjahr  TYPE gjahr OPTIONAL
                    iv_buzei  TYPE buzei OPTIONAL
                    iv_etapa  TYPE char10
                    iv_tipo   TYPE char1
                    iv_texto  TYPE csequence,
      "! Verifica se o FM existe no sistema
      fm_existe IMPORTING iv_fm TYPE rs38l_fnam
                RETURNING VALUE(rv_ok) TYPE abap_bool,
      "! Mensagem do sy-msg* em texto
      msg_sy RETURNING VALUE(rv_txt) TYPE char200,
      "! Texto da 1a mensagem de erro de uma tabela de protocolo (PROTT, MESG...)
      texto_tabela IMPORTING it_tab        TYPE ANY TABLE
                   RETURNING VALUE(rv_txt) TYPE char200.
ENDCLASS.

CLASS zcl_fi_cbol_util IMPLEMENTATION.

  METHOD texto_tabela.
    DATA: lv_id TYPE sy-msgid, lv_no TYPE sy-msgno, lv_ty TYPE sy-msgty,
          lv_v1 TYPE sy-msgv1, lv_v2 TYPE sy-msgv2, lv_v3 TYPE sy-msgv3, lv_v4 TYPE sy-msgv4.
    FIELD-SYMBOLS: <l> TYPE any, <f> TYPE any.
    LOOP AT it_tab ASSIGNING <l>.
      CLEAR: lv_id, lv_no, lv_ty, lv_v1, lv_v2, lv_v3, lv_v4.
      ASSIGN COMPONENT 'MSGTY' OF STRUCTURE <l> TO <f>. IF sy-subrc = 0. lv_ty = <f>. ENDIF.
      IF lv_ty CA 'EAX' OR lv_ty IS INITIAL.
        ASSIGN COMPONENT 'MSGID' OF STRUCTURE <l> TO <f>. IF sy-subrc = 0. lv_id = <f>. ENDIF.
        IF lv_id IS INITIAL.
          ASSIGN COMPONENT 'ARBGB' OF STRUCTURE <l> TO <f>. IF sy-subrc = 0. lv_id = <f>. ENDIF.
        ENDIF.
        ASSIGN COMPONENT 'MSGNO' OF STRUCTURE <l> TO <f>. IF sy-subrc = 0. lv_no = <f>. ENDIF.
        IF lv_no IS INITIAL.
          ASSIGN COMPONENT 'TXTNR' OF STRUCTURE <l> TO <f>. IF sy-subrc = 0. lv_no = <f>. ENDIF.
        ENDIF.
        ASSIGN COMPONENT 'MSGV1' OF STRUCTURE <l> TO <f>. IF sy-subrc = 0. lv_v1 = <f>. ENDIF.
        ASSIGN COMPONENT 'MSGV2' OF STRUCTURE <l> TO <f>. IF sy-subrc = 0. lv_v2 = <f>. ENDIF.
        IF lv_id IS NOT INITIAL AND lv_no IS NOT INITIAL.
          MESSAGE ID lv_id TYPE 'S' NUMBER lv_no WITH lv_v1 lv_v2 lv_v3 lv_v4 INTO rv_txt.
          RETURN.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD gravar_log.
    DATA: ls_log TYPE zfi_cbol_log,
          lv_seq TYPE zfi_cbol_log-seq.

    SELECT MAX( seq ) FROM zfi_cbol_log INTO lv_seq
      WHERE docnum = iv_docnum.
    lv_seq = lv_seq + 1.

    ls_log-docnum   = iv_docnum.
    ls_log-seq      = lv_seq.
    ls_log-bukrs    = iv_bukrs.
    ls_log-belnr    = iv_belnr.
    ls_log-gjahr    = iv_gjahr.
    ls_log-buzei    = iv_buzei.
    ls_log-etapa    = iv_etapa.
    ls_log-tipo_msg = iv_tipo.
    ls_log-texto    = iv_texto.
    ls_log-erdat    = sy-datum.
    ls_log-erzet    = sy-uzeit.
    ls_log-ernam    = sy-uname.
    INSERT zfi_cbol_log FROM ls_log.
  ENDMETHOD.

  METHOD fm_existe.
    DATA lv_name TYPE rs38l_fnam.
    SELECT SINGLE funcname FROM tfdir INTO lv_name WHERE funcname = iv_fm.
    rv_ok = boolc( sy-subrc = 0 ).
  ENDMETHOD.

  METHOD msg_sy.
    IF sy-msgid IS INITIAL.
      RETURN.
    ENDIF.
    MESSAGE ID sy-msgid TYPE 'S' NUMBER sy-msgno
      WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 INTO rv_txt.
  ENDMETHOD.

ENDCLASS.
