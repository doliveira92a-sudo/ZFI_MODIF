CLASS zcl_fi_cbol_config DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CONSTANTS:
      c_modo       TYPE rvari_vnam VALUE 'ZFI_CBOL_MODO',
      c_bukrs      TYPE rvari_vnam VALUE 'ZFI_CBOL_BUKRS',
      c_email      TYPE rvari_vnam VALUE 'ZFI_CBOL_EMAIL',
      c_remetente  TYPE rvari_vnam VALUE 'ZFI_CBOL_REMETENTE',
      c_lembrete_h TYPE rvari_vnam VALUE 'ZFI_CBOL_LEMBRETE_H',
      c_abgru      TYPE rvari_vnam VALUE 'ZFI_CBOL_ABGRU'.

    TYPES: ty_r_bukrs TYPE RANGE OF bukrs.

    CLASS-METHODS:
      "! Modo ativo: 'X'; qualquer outro valor = simulacao (nada e alterado)
      is_ativo RETURNING VALUE(rv_ativo) TYPE abap_bool,
      "! Empresa habilitada (lista vazia = todas)
      empresa_habilitada IMPORTING iv_bukrs TYPE bukrs
                         RETURNING VALUE(rv_ok) TYPE abap_bool,
      get_emails RETURNING VALUE(rt_email) TYPE bcsy_smtpa,
      get_remetente RETURNING VALUE(rv_email) TYPE ad_smtpadr,
      get_lembrete_horas RETURNING VALUE(rv_horas) TYPE i,
      "! Motivo de recusa da ordem (VBAP-ABGRU); padrao Z1
      get_abgru RETURNING VALUE(rv_abgru) TYPE abgru_va.
  PRIVATE SECTION.
    CLASS-METHODS:
      get_low IMPORTING iv_name TYPE rvari_vnam
              RETURNING VALUE(rv_low) TYPE rvari_val_255,
      get_lows IMPORTING iv_name TYPE rvari_vnam
               RETURNING VALUE(rt_low) TYPE string_table.
ENDCLASS.

CLASS zcl_fi_cbol_config IMPLEMENTATION.

  METHOD get_low.
    SELECT SINGLE low FROM tvarvc INTO rv_low
      WHERE name = iv_name AND type = 'P' AND numb = '0000'.
  ENDMETHOD.

  METHOD get_lows.
    DATA lt_low TYPE STANDARD TABLE OF rvari_val_255 WITH DEFAULT KEY.
    FIELD-SYMBOLS <l> TYPE rvari_val_255.
    SELECT low FROM tvarvc INTO TABLE lt_low
      WHERE name = iv_name AND type = 'S'.
    LOOP AT lt_low ASSIGNING <l>.
      IF <l> IS NOT INITIAL.
        APPEND <l> TO rt_low.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD is_ativo.
    rv_ativo = boolc( get_low( c_modo ) = 'X' ).
  ENDMETHOD.

  METHOD empresa_habilitada.
    DATA lt_bukrs TYPE string_table.
    lt_bukrs = get_lows( c_bukrs ).
    IF lt_bukrs IS INITIAL.
      rv_ok = abap_true.
      RETURN.
    ENDIF.
    READ TABLE lt_bukrs TRANSPORTING NO FIELDS WITH KEY table_line = iv_bukrs.
    rv_ok = boolc( sy-subrc = 0 ).
  ENDMETHOD.

  METHOD get_emails.
    DATA: lt_low TYPE string_table,
          lv_mail TYPE ad_smtpadr.
    FIELD-SYMBOLS <l> TYPE string.
    lt_low = get_lows( c_email ).
    LOOP AT lt_low ASSIGNING <l>.
      lv_mail = <l>.
      APPEND lv_mail TO rt_email.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_remetente.
    rv_email = get_low( c_remetente ).
  ENDMETHOD.

  METHOD get_lembrete_horas.
    DATA lv_low TYPE rvari_val_255.
    lv_low = get_low( c_lembrete_h ).
    IF lv_low CO ' 0123456789' AND lv_low IS NOT INITIAL.
      rv_horas = lv_low.
    ELSE.
      rv_horas = 24.
    ENDIF.
  ENDMETHOD.

  METHOD get_abgru.
    DATA lv_low TYPE rvari_val_255.
    lv_low = get_low( c_abgru ).
    IF lv_low IS INITIAL.
      rv_abgru = 'Z1'.
    ELSE.
      rv_abgru = lv_low.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
