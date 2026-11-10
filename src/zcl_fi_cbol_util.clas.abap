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
      msg_sy RETURNING VALUE(rv_txt) TYPE char200.
ENDCLASS.

CLASS zcl_fi_cbol_util IMPLEMENTATION.

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
