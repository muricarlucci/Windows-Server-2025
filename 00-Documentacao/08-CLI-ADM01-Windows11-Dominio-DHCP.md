# SmartFactory-GS — Etapa 08: CLI-ADM01 / Windows 11

Status: EM EXECUCAO. Somente marcar como concluida apos validacao real.

## Escopo e arquitetura
- Cliente comum de Administracao, NAO uma PAW administrativa.
- Windows 11 Pro, Hyper-V Gen2, 2 vCPU, TPM virtual, Secure Boot, VHDX dinamico de 80 GB.
- RAM dinamica com minimo/inicial de 4 GB e maximo de 6 GB; nao reduzir abaixo do minimo oficial.
- SF-LAN, adaptador CLIENTES em Access VLAN 30; DHCP obrigatorio (sem IP estatico).
- IP previsto entre 10.20.30.21 e 10.20.30.254, gateway 10.20.30.1, DNS 10.20.20.11.
- DHCP Relay na FW01 -> DHCP no DC01; dominio smartfactory.corp.
- OU: Computadores > Administracao > SmartFactory.
- Usuario de laboratorio comum: lab.adm01, membro de GG_Administracao, sem Domain Admins.

## Dependencias e reducao
- Necessario durante esta etapa: VM-FW01 + VM-DC01 + CLI-ADM01.
- Desligar FILE01, WEB01, BKP01 para reduzir consumo de memoria.
- DC01 ja utiliza RAM dinamica; nao alterar preventivamente.
- Acesso efetivo a SMB, DFS, IIS, Kerberos SSO e testes de bloqueio serao demonstrados na bateria final.
- Windows 11 Home nao pode ingressar no dominio; escolher Pro na instalacao.

## Evidencias
- VM: Gen2, TPM, Secure Boot, adaptador VLAN 30, memoria e disco.
- DHCP: IP da faixa, gateway, DNS e lease no DC01.
- Registros DNS SRV e resolucao do DC.
- Conta lab.adm01 no grupo GG_Administracao, sem privilegios de dominio.
- Cliente ingressado em smartfactory.corp na OU esperada.
- Test-ComputerSecureChannel = True.
- Login interativo SMARTFACTORY\lab.adm01, quando realizado.
- Roteiro do video 09, capturas e log 10-CLI-ADM01-Windows11-Dominio-DHCP-Resultado.txt.

## Validacao 2026-11-10 13:16:06
- Hyper-V/TPM/RAM: aprovado
- DHCP / DNS / ingresso no dominio: aprovado
- Usuario comum e grupo: conferidos
- Testes finais de SMB, DFS, IIS, Kerberos e bloqueios: PENDENTES de bateria integral

