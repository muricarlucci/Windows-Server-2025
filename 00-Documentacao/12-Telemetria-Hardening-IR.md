# SmartFactory GS | Etapa 12 - Hardening, Telemetria, Wazuh e IR

## Estado comprovado antes desta etapa
- 8 de 8 VMs implementadas; CP-03 Wazuh all-in-one instalado e validado localmente.
- FW01: 1536 MiB ESTATICOS; WAZUH01: 7680 MiB ESTATICOS; DC01: memoria DINAMICA.
- Wazuh Ubuntu Server 24.04.5 LTS; Wazuh 4.14.10, IP 10.20.110.10/24, DNS 10.20.110.1.
- SO do Wazuh em VHDX 40 GiB; Indexer em VHDX 80 GiB; SFSETUP 256 MiB.
- GPOs e LAPS foram finalizadas na Etapa 11, sem necessidade de reaplicacao aqui.

## Objetivo e metodo
- Preparar e instalar agente Wazuh 4.14.10 nos seis convidados Windows, UM POR VEZ, com WAZUH desligada.
- Configurar eventchannels por perfil, FIM seletivo e coleta de inventario SCA/Syscollector nativos.
- Piloto Sysmon integrado ao Windows 11 quando o recurso estiver disponivel; sem duplo Sysmon.
- Auditar e reforcar root SSH no Ubuntu Wazuh sem eliminar acesso administrativo da PAW.
- Preparar GMUD, playbooks IR, plano de rollback e matriz de evidencias.
- A fase final de testes demonstrara ingestao de eventos no Wazuh, FIM, SCA, CVE, 4104, Sysmon e RBAC.

## Diferencas justificadas do CP-03 corporativo
- Nao aplicamos OSConfig em toda a producao sem homologacao; poderia alterar centenas de configuracoes.
- Nao ativamos resposta automatica destrutiva no Wazuh, principalmente em hosts de producao.
- Indexer e Dashboard estao em um unico host, sem HA, com RAM 7,5 GiB, abaixo dos 8 GiB recomendados.
- O teste simultaneo Wazuh + cliente depende de memoria fisica; a instalacao dos agentes e offline.

## Evidencias desta etapa
- 09-Logs-Testes/14-Telemetria-Hardening-IR-Resultado.txt
- 09-Logs-Testes/14-Agent-<VM>.txt para cada Windows instalado
- 09-Logs-Testes/14-Linux-Wazuh-Resultado.txt
- Capturas em 06-Evidencias/12-Telemetria-Hardening-IR

## Restricao de afirmacoes
Instalar agentes offline nao prova que seus eventos chegaram ao Wazuh. Nao marcar T17-T27 aprovado antes da fase final.
