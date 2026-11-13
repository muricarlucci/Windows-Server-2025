# IR-02 | Conta privilegiada comprometida
1. Preservar eventos 4624/4625/4648/4672/4728/4732/4756/5136.
2. Confirmar identidade, origens, sessoes e escopo; registrar UTC e local.
3. Com autorizacao, revogar sessoes e suspender a conta comprometida.
4. Examinar GPO, membros de grupos e criacao de usuarios/servicos.
5. Rotacionar credenciais afetadas e revisar logins pela PAW.
6. NUNCA automatizar reset de krbtgt; somente plano formal de recuperacao AD.
7. Validar recuperacao e gerar GMUD pos-incidente.
