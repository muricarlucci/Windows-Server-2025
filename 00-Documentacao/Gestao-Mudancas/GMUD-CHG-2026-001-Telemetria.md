# GMUD | CHG-2026-001 | Telemetria SmartFactory
Responsavel: [preencher]
Objetivo: instalar agentes Wazuh offline, eventchannels, FIM, Sysmon piloto e preparar IR.
Ativos: DC01, FILE01, WEB01, BKP01, CLI-ADM01, PAW-TI01 e WAZUH01.
Risco: aumento de logs, carga em disco/CPU, reducao de memoria e falha de agente.
Pre-teste: backup de GPO e System State, estado de servicos, espaco e RAM.
Janela: [data/hora da execucao]
Autorizacao: [preencher]
Rollback Windows: restaurar copia de ossec.conf, reiniciar WazuhSvc; remover Sysmon somente se autorizado.
Rollback Linux: restaurar /etc/ssh/sshd_config.d e recarregar sshd; nao reinstalar Wazuh.
Pos-teste: status WazuhSvc, XML valido, eventos gerados localmente, fase futura de dashboard.
Validador: [preencher]
Resultado: [sucesso/parcial/falha; anexar evidencia]
