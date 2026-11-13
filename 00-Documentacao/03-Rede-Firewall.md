# SmartFactory - Etapa 03 - VLANs, Firewall, NAT e DHCP Relay

Data: 2026-11-10 01:10:29

## Base utilizada

- Origem: backup integral da VM-FW01 fornecido pelo usuario.
- Revisao de configuracao: 24.6 (NAO e versao do produto).
- Interfaces fisicas pfSense: hn0 WAN, hn1 LAN.
- WAN: DHCP sobre Default Switch, sem bloqueio RFC1918 devido ao NAT privado do Hyper-V.
- LAN: hn1.10, IP 10.20.10.1/24.
- Hyper-V: SF-LAN e VLAN nativa 99; host Access VLAN 10.
- DHCP IPv4 pfSense: nao habilitado; range obsoleto da LAN removido.
- DHCPv6/RA da LAN: desabilitado para o laboratorio IPv4.
- IPv6 WAN preservado conforme backup original.

## Segmentos

- VLAN 10 | MGMT | 10.20.10.1/24 | lan
- VLAN 20 | SERVIDORES | 10.20.20.1/24 | opt1
- VLAN 30 | ADMIN | 10.20.30.1/24 | opt2
- VLAN 40 | RH | 10.20.40.1/24 | opt3
- VLAN 50 | FINANCEIRO | 10.20.50.1/24 | opt4
- VLAN 60 | ENGENHARIA | 10.20.60.1/24 | opt5
- VLAN 70 | PRODUCAO | 10.20.70.1/24 | opt6
- VLAN 80 | LOGISTICA | 10.20.80.1/24 | opt7
- VLAN 90 | TI | 10.20.90.1/24 | opt8
- VLAN 100 | DMZ | 10.20.100.1/24 | opt9
- VLAN 110 | SECURITY_SOC | 10.20.110.1/24 | opt10
- VLAN 120 | BACKUP | 10.20.120.1/24 | opt11
- VLAN 999 | VISITANTES | 10.20.200.1/24 | opt12

VLAN 99: somente nativa, sem interface IP e sem gateway.

## Politicas

- Aliases criados: 20.
- Regras criadas: 47 (log habilitado nas regras de block).
- Grupo CLIENTES: VLANs 30,40,50,60,70,80,90.
- Anti-lockout desabilitado; regra explicita de gestao do host 10.20.10.10.
- Gestao PAW: 10.20.90.10, habilitada somente para destinos e portas previstas.
- Acesso inter-VLAN somente por autorizacoes especificas; demais fluxos privados negados.
- Visitantes: bloqueio de RFC1918, DNS publico e HTTP/HTTPS externos.
- NAT outbound: automatic.
- DHCP Relay: interfaces opt2 a opt8 e opt12 para 10.20.20.11.
- DHCP Relay somente sera funcional depois que DC01/Windows DHCP estiver configurado.
- Servicos AD/DFS/SMB/Wazuh dependem da instalacao das VMs previstas.
- Trafego na mesma VLAN nao atravessa pfSense; usar firewall local Windows.

## Reducoes e pendencias

- VMs DC02 e FILE02 planejadas no CP02 mas nao instaladas por limite de hardware.
- DHCP Failover e DFSR entre 2 servidores nao serao demonstrados fisicamente neste laboratorio.
- Interface WAN usa Default Switch do Hyper-V, nao uplink fisico redundante.
- VLANs no pfSense nao representam isoladamente testes de conectividade entre clientes.
- Testes reais de ACLs, AD, SMB, Wazuh, DHCP e backup serao executados apos criacao das VMs.

## Evidencias

- Backup antes: 04-Configuracoes/pfSense/backup-ANTES-Etapa03.xml.
- Arquivo para restaurar: 04-Configuracoes/pfSense/config-SmartFactory-Etapa03-IMPORTAR.xml.
- Log PowerShell: 09-Logs-Testes/05-Etapa03-Resultado.txt.
- Capturas: 06-Evidencias/03-Rede-Firewall/.
- Roteiro: 07-Video/Roteiros/Roteiro_Video_Etapa_4.txt.
- Video: 04 - SmartFactory - VLANs, Firewall, NAT e DHCP Relay.mp4.

## Critério de encerramento

Marcar concluida somente quando restore, trunk, HTTPS, inspeção das regras e backup posterior forem confirmados. Demais testes permanecem pendentes ate implantar os hosts.
