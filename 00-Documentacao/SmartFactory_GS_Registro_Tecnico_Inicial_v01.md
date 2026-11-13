# SmartFactory — Registro técnico inicial
**Versão 0.1 | 01/11/2026 | Estado: planejamento e preparação**

Documento incremental para o relatório final. Alterações posteriores devem preservar histórico e registrar evidências.

## Estado e regra de consistência

- A arquitetura corporativa é a dos relatórios CP-01 (rede/Hyper-V), CP-02 (Windows Server/serviços) e CP-03 (segurança). Em conflitos explícitos: CP-03 > CP-02 > CP-01.
- O laboratório abaixo é uma prova de conceito REDUZIDA. Não declarar como implantados ou validados os controles sem evidência real. O professor exige vídeo operacional, relatório reproduzível e apresentação rápida.
- Estado em 01/11/2026: Hyper-V habilitado segundo usuário; ISOs Windows Server, Windows 11, Ubuntu e Netgate baixadas; pastas do projeto já criadas. Nenhuma VM, firewall, VLAN, serviço de domínio, GPO ou backup foi confirmado como implantado.

## Hardware disponível (diagnóstico)

- Windows 11 Pro build 26200; AMD Ryzen 5 5500 (6 núcleos, 12 threads); RAM 16 GB; virtualização de firmware indicada como habilitada.
- C: 116,3 GB totais / 42,1 GB livres (SSD). D: 454,1 GB totais / 174,4 GB livres (HDD, conforme usuário). Dual boot com Linux em partições não utilizadas pelo laboratório.
- Diagnóstico anterior apresentou “Hyper-V: indisponível ou não detectado”, apesar de o usuário informar Hyper-V habilitado; verificar separadamente os recursos e o Gerenciador do Hyper-V antes de provisionar.
- Disco C: reservado ao host; arquivos grandes de VMs e ISOs em D:. Não alterar ou reparticionar as partições do Linux.

## Diretório principal

- Raiz: D:\FIAP\WINDOWS\SmartFactory-GS
- 00-Documentacao — registro técnico, relatórios e diagramas; 01-ISOs — ISOs e hashes; 02-VMs — VHDX/configurações; 03-Scripts — PowerShell/Bash; 04-Configuracoes — exports de firewall/GPO/Wazuh; 05-Backups — cópias de laboratório; 06-Evidencias — capturas e resultados; 07-Video — gravação; 08-Relatorio-Final — entregáveis; 09-Logs-Testes — logs e inventários.
- Backups localizados no mesmo HDD não protegem contra falha desse disco; criar cópia externa/offline assim que possível. Verificar capacidade livre antes de criar novas VMs.

## Conjunto de 8 VMs — meta de prova de conceito

- As 8 VMs não precisam permanecer ligadas ao mesmo tempo. A instalação de todas em D: não está garantida com 174,4 GB disponíveis; medir tamanho físico dos VHDX após cada implantação e suspender expansão quando a margem estiver baixa.
- O dimensionamento abaixo é PROVISÓRIO e visa demonstração em baixa carga, não desempenho de produção. O disco VHDX é DINÂMICO: tamanho lógico máximo ≠ espaço físico efetivamente ocupado.

## Conjunto de 8 VMs (proposto; não executado)

| VM | Sistema | vCPU | RAM | VHDX lógico | Função e IP |
|---|---|---:|---|---|---|
| VM-FW01 | pfSense CE / Hyper-V | 1–2 | 1 GB fixo | 8 GB | Firewall L3, gateways, VLANs, NAT, DHCP Relay; WAN separada da LAN; Secure Boot conforme instrução Netgate — Laboratório |
| VM-DC01 | Windows Server 2025 Core | 2 | 2,5–3 GB dinâmico | 50 GB | AD DS, DNS, DHCP, GPO, LAPS schema/ACLs — 10.20.20.11 / VLAN 20 |
| VM-FILE01 | Windows Server 2025 Core | 2 | 2–3 GB dinâmico | C:45 + E:16 + S:8 GB | SMB/NTFS, AGDLP, DFSN, FSRM, VSS; dados de teste — 10.20.20.15 / VLAN 20 |
| VM-WEB01 | Windows Server 2025 Desktop | 2 | 3–4 GB dinâmico | 55 GB | IIS/Intranet, HTTPS, DMZ e FIM — 10.20.100.10 / VLAN 100 |
| VM-BKP01 | Windows Server 2025 Core * | 2 | 2–3 GB dinâmico | C:45 + B:24 GB | Backup dedicado com armazenamento VHDX separado e restauração real — 10.20.120.10 / VLAN 120 |
| CLI-ADM01 | Windows 11 Pro | 2 | 4 GB mínimo | 64 GB | Cliente corporativo: domínio, GPO, LAPS, acesso normal e testes — DHCP / VLAN 30 |
| PAW-TI01 | Windows 11 Pro | 2 | 4 GB mínimo | 64 GB | Estação administrativa segregada: RSAT, WinRM, SSH, Wazuh — 10.20.90.10 / VLAN 90 |
| VM-WAZUH01 | Ubuntu Server 24.04 LTS | 4 | 8 GB recomendado | OS:32 + dados:25 GB | Wazuh server/indexer/dashboard all-in-one, agente Windows e alertas; retenção curta — 10.20.110.10 / VLAN 110 |

## Adaptações deliberadas e limitações

- BKP01: o CP-03 especifica Desktop Experience, mas propomos Server Core para reduzir RAM e superfície de ataque, com administração PowerShell remota. É uma ALTERAÇÃO DO LABORATÓRIO e deve ser aprovada/documentada; se a demonstração gráfica for exigida, voltar ao Desktop Experience antes da instalação.
- Wazuh: o CP-03 prevê 8 GiB, 4 vCPU, 40 GB SO + 80 GB dados e até 90 dias. Mantemos RAM/CPU recomendadas, porém reduzimos discos e retenção (por exemplo, 1–7 dias de testes), monitorando crescimento. O Wazuh Quickstart recomenda 50 GB para até 25 agentes / 90 dias; retenção menor é adaptação acadêmica, não equivalência.
- DC02 não instalado no recorte: sem DC redundante nem DHCP Failover demonstrado. FILE02 não instalado: sem DFSR nem failover de alvo DFS demonstrado. A arquitetura integral conserva os dois e sua documentação.
- Switch Embedded Teaming físico, dois hosts Hyper-V, storage RAID e alta disponibilidade física não são reproduzidos em host doméstico. Não afirmar tolerância física a falha.
- BKP01 na VLAN120 comprova segregação lógica mediante regras e testes; um VHDX no mesmo disco D: do resto das VMs NÃO constitui backup offline, imutável ou proteção contra quebra do HDD.
- 2 clientes Windows 11 preservam a segregação PAW/usuário comum. Uma VM Windows 11 exige >=4 GB RAM e >=64 GB de disco virtual; não reduzir abaixo disso só para acomodar o host.
- A memória dinâmica do Hyper-V recupera folgas de VMs compatíveis, mas Wazuh all-in-one com 8 GB não cabe confortavelmente ao mesmo tempo que DC01 (3), Windows 11 (4), firewall (1) e Windows hospedeiro em 16 GB. Testes integrados Wazuh+cliente+DC podem exigir PC de outro integrante, upgrade, ou redução experimental sem garantia de estabilidade.

## IPs e segmentação

- Domínio: smartfactory.corp; NetBIOS: SMARTFACTORY; rede-base: 10.20.0.0/16; gateway de cada VLAN em 10.20.X.1.
- VLAN 10 MGMT 10.20.10.0/24; 20 SERVIDORES 10.20.20.0/24; 30 ADM 10.20.30.0/24; 40 RH 10.20.40.0/24; 50 FIN 10.20.50.0/24; 60 ENG 10.20.60.0/24; 70 PROD 10.20.70.0/24; 80 LOG 10.20.80.0/24; 90 TI 10.20.90.0/24; 100 DMZ 10.20.100.0/24; 110 SOC 10.20.110.0/24; 120 BACKUP 10.20.120.0/24; 999 VISITANTES 10.20.200.0/24.
- Reservas não usadas no laboratório reduzido: VM-DC02 10.20.20.12; VM-FILE02 10.20.20.16. Endereços devem permanecer estáveis para facilitar extensão futura.

## Regras de execução, evidência e próximos passos

- Implantação progressiva recomendada: 1) confirmar Hyper-V/discos/ISOs/hash pfSense, 2) criar rede isolada e VM-FW01, 3) VM-DC01/AD, 4) CLI-ADM01 e GPO/LAPS, 5) FILE01/WEB01/BKP01, 6) Wazuh e telemetria com VMs estritamente necessárias ligadas, 7) testes, relatório e vídeo.
- Para o vídeo, registrar comandos, screenshots e resultados positivos/negativos: domínio, GPO gpresult, LAPS autorizado/negado, ACL AGDLP, HTTP→HTTPS, firewall allow/deny, Wazuh/Sysmon/FIM, backup + restore, logs e observações da arquitetura não replicada.
- Próxima ação não executada: verificar que Hyper-V realmente está operacional, identificar o tipo de unidade de D:, inventariar espaço físico usado por ISOs e confirmar integridade/extração do instalador Netgate .iso.gz. Somente depois criar o primeiro switch/VM.
- Script sempre que houver tarefa automatizável; indicar pasta exata no D: para salvar cada artefato e separar o que é manual. Documentar resultado real e evitar afirmações de sucesso antes da validação.

## Referências técnicas

- CP-01: Arquitetura de Rede SmartFactory; CP-02: Plataforma Windows Server 2025; CP-03: Segurança, Hardening, Monitoramento e Resposta a Incidentes.
- Microsoft: https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/dynamic-memory
- Microsoft: https://learn.microsoft.com/pt-br/windows/whats-new/windows-11-requirements
- Microsoft: https://learn.microsoft.com/en-us/windows-server/get-started/hardware-requirements?pivots=windows-server-2025
- Wazuh: https://documentation.wazuh.com/current/quickstart.html
- Netgate: https://docs.netgate.com/pfsense/en/latest/install/download-installer-image.html
- Netgate: https://docs.netgate.com/pfsense/en/latest/install/prepare-installer-media.html
- Netgate: https://docs.netgate.com/pfsense/en/latest/install/netinstaller.html
