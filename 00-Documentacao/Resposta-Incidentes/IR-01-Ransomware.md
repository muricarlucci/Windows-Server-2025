# IR-01 | Suspeita de ransomware em endpoint
1. Registrar ticket, horario, usuario, IP, hostname e alerta Wazuh/Defender.
2. Preservar Security, Sysmon, logs do agente, hashes e arquivos suspeitos.
3. Verificar escopo em SMB, FILE01, contas administrativas e movimentos laterais.
4. Propor isolamento seletivo no firewall; nunca desligar host OT automaticamente.
5. Com autorizacao, conter conta/sessao suspeita e bloquear IOCs confirmados.
6. Investigar persistencia, erradicar e rotacionar credenciais comprometidas.
7. Restaurar de backup validado APOS confirmar remediacao, conferir hashes.
8. Reabrir acessos por GMUD; registrar lições e atualizar deteccoes.
