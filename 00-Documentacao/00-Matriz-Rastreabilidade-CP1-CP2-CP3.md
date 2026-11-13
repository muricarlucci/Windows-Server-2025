# SmartFactory - Rastreabilidade das tres CPs

Regra: marcar [x] somente apos implementacao e evidencia. Omitir VMs por hardware nao equivale a implementar alta disponibilidade.

## CP-01 - Rede

- [ ] Enderecamento completo e VLANs 10-120, 999 (VLAN 99 nativa sem IP).
- [ ] Hyper-V, SF-LAN, trunk e host na VLAN 10; evidencias.
- [ ] Gateway pfSense em todas as redes e roteamento inter-VLAN.
- [ ] ACLs stateful, minimo privilegio e bloqueio de movimento lateral.
- [ ] Isolamento RH/Financeiro e TI/OT Produção.
- [ ] DMZ interna, acesso permitido e bloqueio de pivot.
- [ ] Visitantes isolados das redes privadas.
- [ ] NAT automatico, politicas WAN e DHCP Relay.
- [ ] Documentar SET/switches fisicos como arquitetura nao implantada.
- [ ] Diagrama logico e fisico, plano IP e testes positivos/negativos.

## CP-02 - Windows Server 2025

- [ ] DC01 Windows Server 2025 Core; AD DS smartfactory.corp.
- [ ] DNS integrado AD, zonas, SRV, forwarders, zona reversa.
- [ ] OUs, usuarios, grupos e AGDLP.
- [ ] DHCP Windows, oito escopos, opcoes, exclusoes e Relay funcional.
- [ ] DC02/DHCP Failover: limitacao de laboratorio registrada.
- [ ] FILE01, VHDX/SCSI, NTFS, permissoes e shares SMB 3.1.1.
- [ ] DFS Namespace, FSRM, VSS e deduplicacao (verificar suporte).
- [ ] FILE02/DFSR assincrono: limitacao registrada, nao confundir com backup.
- [ ] WEB01 IIS em DMZ, TLS/HTTPS e autenticacao Windows.
- [ ] BKP01, isolamento, backups e restauracao.
- [ ] Cliente Windows 11 no dominio e testes DNS/DHCP/SMB/IIS.
- [ ] Documentar licenciamento, Core/Desktop e restricoes de RAM.

## CP-03 - Hardening, SIEM e resposta

- [ ] VLAN 110 SOC e VLAN 120 backup isoladas.
- [ ] PAW-TI01 e acessos admin restritos; excecao do host documentada.
- [ ] Matriz de firewall integral, regras, logs e verificacao de bloqueios.
- [ ] GPOs modulares, Central Store, piloto, gpresult e rollback.
- [ ] Windows LAPS, delegacao, ACLs, senha local e validacoes.
- [ ] Hardening Windows Server Core, WinRM, Defender, SMB e auditoria.
- [ ] Ubuntu Wazuh: SSH por chave, UFW, AppArmor, patching.
- [ ] Wazuh manager/indexer/dashboard, agentes e RBAC.
- [ ] Sysmon, coleta 4625/4720/1102/4104, FIM/SCA e vulnerability detection.
- [ ] Isolar backup, procedimento restore de arquivos e system-state.
- [ ] Playbooks IR, GMUD, rollback de mudancas e logs de auditoria.
- [ ] Pacote de evidencias e apresentacao com limites do laboratorio.

## Matriz de 30 testes da CP-03

- [ ] T01 ADM para RH SMB: bloqueado.
- [ ] T02 Cliente para FILE01 TCP445: permitido.
- [ ] T03 Visitantes para 10.20.0.0/16: bloqueado.
- [ ] T04 Cliente para Intranet 443: permitido.
- [ ] T05 WEB01 para RH: bloqueado.
- [ ] T06 Estacao comum para RDP servidor: bloqueado.
- [ ] T07 PAW para RDP WEB01: permitido.
- [ ] T08 PAW para WinRM Core: permitido.
- [ ] T09 Nao-PAW para SSH Wazuh: bloqueado.
- [ ] T10 PAW para SSH Wazuh por chave: permitido.
- [ ] T11 Login SSH por senha: negado.
- [ ] T12 gpresult de endpoint: GPO aplicada.
- [ ] T13 Get-LapsADPassword autorizado: retorna senha.
- [ ] T14 Get-LapsADPassword usuario comum: acesso negado.
- [ ] T15 Reset-LapsPassword: nova senha no AD.
- [ ] T16 Rollback VM teste: rotacao LAPS.
- [ ] T17 Falha logon repetida: alerta Wazuh.
- [ ] T18 Criacao usuario AD: evento 4720 no Wazuh.
- [ ] T19 Inclusao grupo privilegiado: alerta critico.
- [ ] T20 Limpeza Security log: evento 1102 critico.
- [ ] T21 Modificacao arquivo IIS: alerta FIM.
- [ ] T22 PowerShell teste: evento 4104 no Wazuh.
- [ ] T23 Sysmon Process Create: evento ID 1 ingerido.
- [ ] T24 Defender teste benigno: telemetria capturada.
- [ ] T25 Vulnerability Detection: CVE visivel.
- [ ] T26 Mudanca ACL arquivo: evento 4670 no Wazuh.
- [ ] T27 Wazuh Agent parado: deteccao host offline.
- [ ] T28 Restore arquivo: integridade verificada.
- [ ] T29 Restore System State: log/procedimento.
- [ ] T30 Failover de FILE: nao executavel sem FILE02; justificar.

## Limitacoes formais do laboratorio

- Oito VMs e apenas 16GB de RAM no host Windows 11.
- DC02, FILE02, DHCP Failover, DFSR e SET fisico nao sao implantados.
- Acesso a arquivos/servicos depende das VMs e do firewall local Windows.
- Backup em disco do mesmo host nao e backup offline/imutavel.
- Para testes inviaveis: registrar a justificativa, sem marcar como aprovados.
