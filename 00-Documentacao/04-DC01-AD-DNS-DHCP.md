# SmartFactory - Etapa 04 - VM-DC01 / AD DS / DNS / DHCP

## Especificacao (CP-02 + CP-03)
- VM: VM-DC01; nome do Windows: VM-DC01.
- Windows Server 2025 Standard Server Core; Geracao 2; Secure Boot.
- 2 vCPU, RAM ESTATICA de 4 GB; VHDX dinamico de 60 GB no D:.
- Switch SF-LAN, Access VLAN 20, IP 10.20.20.11/24.
- Gateway 10.20.20.1; DNS preferencial 10.20.20.11.
- Dominio smartfactory.corp; NetBIOS SMARTFACTORY; niveis 2025.
- AD DS, DNS integrado ao AD, GC, FSMO, horario corporativo.
- Zona direta smartfactory.corp e reversa 20.10.in-addr.arpa /16.
- DNS Forwarders 1.1.1.1 e 9.9.9.9; atualizacao dinamica segura.
- OUs departamentais, Infraestrutura e Piloto_GPO; grupos AGDLP.
- Oito escopos DHCP: 30/40/50/60/70/80/90/999.
- Pools efetivos .21-.254 (corporativos), .10-.254 (visitantes).
- Concessoes 8 dias (corporativos), 8 horas (visitantes).
- Visitantes usam DNS publico, sem sufixo AD.

## Adequacoes do laboratorio
- DC02 ausente: sem replicacao de AD/DNS e sem DHCP Failover.
- DHCP instalado TEMPORARIAMENTE no DC01, IP 10.20.20.11.
- Sem SET/HA fisico real. O host permanece Windows 11 Pro, RAM 16 GB.
- GPOs, Central Store, LAPS e hardening aprofundado ficam na etapa de seguranca.
- Contas reais ainda nao foram fornecidas: nao criar usuarios ficticios.
- Teste DHCP Relay real exige cliente em outra VLAN, previsto adiante.

## Evidencias
- ISO selecionada e tela inicial do instalador Server Core.
- VM Gen 2, 2 vCPU, 4 GB RAM, VHDX 60GB, VLAN Access 20.
- SConfig do Windows Server Core; hostname/IP configurados.
- Promocao AD DS e reinicio do controlador de dominio.
- Get-ADDomain/Get-ADForest e consultas DNS SRV.
- Zonas DNS, OUs, grupos AGDLP e oito escopos DHCP.
- Resultado do script -Acao Validar e relatorio.

## Estado
VALIDACAO AUTOMATIZADA APROVADA (testes com clientes pendentes).


## Resultado de validacao - 2026-11-10 05:00:30
- VALIDACAO AUTOMATIZADA APROVADA.
- Teste de cliente DHCP e inter-VLAN: pendente de endpoints.
- Credenciais nao registradas.

