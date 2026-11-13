# SmartFactory - Etapa 02: VM-FW01 (pfSense CE)

Data de provisionamento: 2026-11-02 19:09:56

## Estado
- VM criada no Hyper-V; **instalacao do pfSense ainda nao validada**.
- ISO: netgate-installer-v1.2-RELEASE-amd64.iso.
- SO previsto: pfSense Community Edition, versao a registrar apos instalacao.
- VM: VM-FW01, Geracao 2, 2 vCPU, 2 GiB RAM estatica, VHDX dinamico de 16 GiB.
- WAN: Default Switch (DHCP/NAT do Hyper-V).
- LAN: SF-LAN, trunk 802.1Q; VLAN 10 nativa, demais VLANs permitidas para implementacao posterior.
- LAN a configurar no pfSense: 10.20.10.1/24; host Windows: 10.20.10.10/24 (VLAN 10).
- Secure Boot: desativado somente nesta VM, conforme guia Netgate Hyper-V.
- O switch FIAP e os adaptadores fisicos nao foram modificados.
- Pasta de VM: D:\FIAP\WINDOWS\SmartFactory-GS\02-VMs\VM-FW01.
- Log de provisionamento: D:\FIAP\WINDOWS\SmartFactory-GS\09-Logs-Testes\03-Provisionamento-VM-FW01.txt.

## Pendente apos provisionamento
- Iniciar instalador na console; confirmar pfSense CE, instalacao no VHDX, WAN DHCP.
- Atribuir interfaces de WAN e LAN pelos MACs, alterar LAN para 10.20.10.1/24.
- Testar HTTPS e conectividade; trocar senha administrativa padrao; remover ISO de boot.
- Coletar evidencias e gravar video da instalacao, com omissao de senhas na captura.

## Limites da demonstracao
- A segmentacao das demais VLANs e as regras inter-VLAN nao foram configuradas nesta etapa.
- A WAN usa NAT do Windows 11 e nao e uma interface de firewall perimetral fisica.
- Esta VM e um laboratorio em um unico host, sem tolerancia a falha fisica.

## Verificacao automatizada - 2026-11-09 02:01:18

- Estado da VM: Off.
- IP do host: 10.20.10.10.
- Estado do IP: Preferred.
- HTTPS pfSense: TCP 443 inacessivel; investigar conectividade.
- Internet do Windows: True.
- Log: 09-Logs-Testes/04-Validacao-PfSense.txt.
- Versao do pfSense e conectividade WAN: validar manualmente.
