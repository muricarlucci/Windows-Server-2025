# SmartFactory-GS — Etapa 09: PAW-TI01 e Administracao Segura

Estado: EM IMPLEMENTACAO. Nao declarar acesso remoto comprovado antes de teste real.

## Arquitetura
- PAW-TI01: Windows 11 Pro, Hyper-V geracao 2, Secure Boot, vTPM, 2 vCPU.
- VHDX dinamico 80 GB, memoria dinamica min/start 4 GB, max 6 GB.
- Rede SF-LAN, Access VLAN 90, IP estatico 10.20.90.10/24.
- Gateway 10.20.90.1; DNS exclusivo 10.20.20.11; dominio smartfactory.corp.
- OU: OU=Computadores,OU=TI,OU=SmartFactory.
- Conta nominal de LABORATORIO adm.lab com grupo global GG_PAW_Administradores.
- Grupo com privilegio de Administrador LOCAL apenas nesta PAW. Nao Domain Admins.
- Restricao de logon da conta adm.lab a PAW-TI01 (atributo AD LogonWorkstations).
- Politica de uso: acesso administrativo; nao utilizar a PAW para email/navegacao cotidiana.

## Protecoes aplicadas
- Firewall do Windows habilitado; inbound negado por padrao.
- RDP RECEBIDO na PAW desabilitado; a PAW usa mstsc como cliente de conexoes de saida.
- Nenhum listener de SSH ou WinRM aberto na PAW pela automacao.
- RSAT instalavel opcionalmente, conforme disponibilidade do Windows Update.
- Nao configurar TrustedHosts=* ou Basic Auth de WinRM.

## Dependencias e limites
- FW01 e DC01 devem estar Running; CLI-ADM01, FILE01, WEB01, BKP01 Off durante esta etapa.
- DC01 com RAM dinamica: manter como esta enquanto estavel.
- Regras pfSense da Etapa 03 autorizam 10.20.90.10 aos destinos administrativos previstos.
- RDP WEB01/BKP01, WinRM dos membros, Wazuh SSH/dashboard: testar na bateria final quando alvos estiverem ligados.
- Conta adm.lab NAO tem automaticamente privilegios nos servidores remotos; isso requer delegacao posterior.
- LAPS, GPO de PAW, auditoria completa, Credential Guard e telemetria: futuras etapas de hardening.
- O script nao bloqueia navegação na Internet por politica global; implementar politica formal depois.

## Evidencias
- Geracao 2, vTPM, Secure Boot e RAM da VM.
- VLAN90 e IP estatico no Windows.
- Conta adm.lab e grupo no AD, restricao de logon a PAW, ausencia em Domain Admins.
- Grupo local de administradores, firewall ativo, RDP inbound desativado.
- Verificacao DNS, canal seguro AD e conectividade administrativa quando o destino estiver disponivel.

## Validacao 2026-11-10 14:55:29
- Infraestrutura da PAW e conta administrativa: APROVADAS pelo script.
- Acessos administrativos aos servidores e bloqueios de clientes: PENDENTES de testes funcionais.
- RSAT: opcional, verificar no Windows.

