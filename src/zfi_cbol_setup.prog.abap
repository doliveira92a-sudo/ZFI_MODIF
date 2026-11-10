*&---------------------------------------------------------------------*
*& Report ZFI_CBOL_SETUP
*& Cria as variaveis da TVARV usadas pelo estorno NF x boleto (rodar uma
*& vez em cada sistema/mandante; a TVARV nao e transportada pelo abapGit).
*& Nao sobrescreve valores ja existentes.
*&---------------------------------------------------------------------*
REPORT zfi_cbol_setup.

START-OF-SELECTION.
  PERFORM criar USING 'ZFI_CBOL_MODO'        'P' 'S'  'S = simulacao (nada e alterado); X = ativo'.
  PERFORM criar USING 'ZFI_CBOL_ABGRU'       'P' 'Z1' 'Motivo de recusa dos itens da ordem (VA02)'.
  PERFORM criar USING 'ZFI_CBOL_LEMBRETE_H'  'P' '24' 'Horas ate o lembrete de boleto pendente no banco'.
  PERFORM criar USING 'ZFI_CBOL_LIMPAR'      'P' 'X'  'X = limpa dados do boleto no titulo ao confirmar o banco'.
  PERFORM criar USING 'ZFI_CBOL_REMETENTE'   'P' ''   'E-mail remetente (opcional)'.
  WRITE: / 'Preencha na STVARV (tipo S, uma linha por valor):'.
  WRITE: / '  ZFI_CBOL_EMAIL - destinatarios dos avisos'.
  WRITE: / '  ZFI_CBOL_BUKRS - empresas habilitadas (vazio = todas)'.

FORM criar USING iv_name TYPE csequence iv_type TYPE csequence
                 iv_low  TYPE csequence iv_txt  TYPE csequence.
  DATA: ls_var TYPE tvarvc,
        lv_cnt TYPE i.
  SELECT COUNT(*) FROM tvarvc INTO lv_cnt WHERE name = iv_name AND type = iv_type.
  IF lv_cnt > 0.
    WRITE: / iv_name, 'ja existe - mantido'.
    RETURN.
  ENDIF.
  ls_var-name = iv_name.
  ls_var-type = iv_type.
  ls_var-numb = '0000'.
  ls_var-low  = iv_low.
  INSERT tvarvc FROM ls_var.
  WRITE: / iv_name, 'criado:', iv_low, '-', iv_txt.
ENDFORM.
