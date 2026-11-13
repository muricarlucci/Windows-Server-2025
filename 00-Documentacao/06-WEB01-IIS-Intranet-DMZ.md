# SmartFactory-GS | Etapa 06: IIS e Intranet RH na DMZ

Status: EM IMPLEMENTACAO. Nao considerar testes com cliente concluidos antecipadamente.

## Arquitetura
- VM-WEB01: Windows Server 2025 Standard Desktop Experience, Gen2, 2 vCPU.
- RAM dinamica: minima 2 GB, inicial 3 GB, maxima 4 GB, buffer 5%.
- VHDX dinamico 80 GB; switch SF-LAN, Access VLAN 100.
- Host: VM-WEB01, IPv4 10.20.100.10/24, GW 10.20.100.1, DNS 10.20.20.11.
- Dominio smartfactory.corp, OU Infraestrutura/Servidores_DMZ/Web_Servers.
- IIS: site HTTPS intranet.smartfactory.corp, porta 443, certificado RSA 2048 autoassinado (laboratorio).
- HTTP porta 80: site separado, redirect permanente 301 para HTTPS.
- Windows Authentication (Negotiate/Kerberos preferencial), Anonymous Authentication off no site HTTPS.
- App Pool dedicado com ApplicationPoolIdentity.
- DNS: CNAME intranet -> vm-web01 e SPN HTTP/intranet.smartfactory.corp na conta VM-WEB01$.
- Firewall Windows: TCP 80/443 de VLANs 30-90; RDP TCP3389 apenas de PAW 10.20.90.10 com NLA; demais entradas sob bloqueio padrao.
- pfSense: ACLs da Etapa 03; WEB01 sem acesso geral para redes de usuarios.

## Restricoes e ressalvas
- O certificado e autoassinado: navegadores sem confianca exibirao aviso.
- Windows Server 2025 tem suporte a TLS 1.3; NAO declaramos TLS 1.3 EXCLUSIVO sem teste de negociacao e hardening posterior.
- A autenticacao Kerberos real e o SSO requerem cliente Windows no dominio e serao testados depois.
- Wazuh, GPO, LAPS e validacao de isolamento com segundo host: etapas posteriores.
- Sem publicacao da intranet na WAN: aplicacao interna apenas.
- Uma VM/host fisico: sem alta disponibilidade de IIS.

## Evidencias
- Hyper-V: Gen2, RAM, Disco, VLAN 100.
- Windows Server: versao, Desktop Experience, hostname, rede e dominio.
- IIS: binding 80/443, certificado, Windows Auth, app pool e redirect.
- DC01: CNAME intranet e SPN HTTP/intranet.smartfactory.corp.
- Logs dos scripts e video 07.
- Acesso de cliente com usuario de dominio: pendente de estacao Windows 11.

## Validacao - 2026-11-10 08:13:25
- Hyper-V: True.
- IIS/Windows Authentication/HTTPS: False.
- CNAME/SPN/OU no AD: True.
- Log: 09-Logs-Testes/08-WEB01-IIS-Intranet-Resultado.txt.
- Testes autenticados com navegador do cliente: aguardando CLI-ADM01.
- TLS1.3 somente: NAO foi imposto globalmente (compatibilidade Schannel).

## Validacao - 2026-11-10 08:19:16
- Hyper-V: True.
- IIS/Windows Authentication/HTTPS: True.
- CNAME/SPN/OU no AD: True.
- Log: 09-Logs-Testes/08-WEB01-IIS-Intranet-Resultado.txt.
- Testes autenticados com navegador do cliente: aguardando CLI-ADM01.
- TLS1.3 somente: NAO foi imposto globalmente (compatibilidade Schannel).
