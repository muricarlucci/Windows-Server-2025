# SmartFactory GS - Etapa 10: Wazuh all-in-one em Ubuntu 24.04

STATUS: Em implantacao ate validar o guest.

## Arquitetura real
- VM-WAZUH01 = Ubuntu Server 24.04 LTS AMD64; sem ingresso no Active Directory.
- Hyper-V Gen2, Linux Secure Boot template Microsoft UEFI Certificate Authority, 4 vCPU, RAM estatica 8 GiB.
- SCSI OS 40 GiB e indexer 80 GiB, ambos VHDX dinamicos. Terceiro VHDX FAT32 256 MiB e apenas de transporte de scripts.
- VLAN 110, IP 10.20.110.10/24, gateway 10.20.110.1.
- DNS de bootstrap: pfSense 10.20.110.1, excepcao temporaria/documentada para instalar sem o DC01 ligado.
- Wazuh 4.14, all-in-one: Manager + Indexer + Dashboard + Filebeat; Ubuntu AppArmor, UFW, SSH somente PAW.
- UFW: PAW-TI01 10.20.90.10 para TCP 22/443; VLANs corporativas para TCP 1514/1515.
- API TCP 55000 e Indexer TCP 9200 NAO expostos via UFW.
- Vulnerability Detection padrao do Wazuh 4.14; FIM/SCA/ingestao agent dependem de deploy e testes posteriores.
- Sem alterar pfSense automaticamente. Regra de DNS de bootstrap adicionada manualmente, com IP origem unico.

## Requisitos corporativos nao simulados
- Nao equivale a Wazuh distribuido para ~220 hosts, nem HA.
- 90 dias de retencao e uma meta de capacidade, nao garantia sem dimensionar volume de alertas.
- Sem 10-15 agentes implantados nesta etapa; serao instalados por grupos e validados na fase de telemetria.
- Credenciais Wazuh ficam apenas no Ubuntu, em /root/smartfactory-wazuh. Nao copiar para repositorio publico.
- Testes T17-T27 dos agentes e Wazuh dependem dos endpoints e da memoria fisica; nao alegar aprovacao agora.

## Evidencias
- Hyper-V com RAM estatica 8 GiB, VLAN110, 2 VHDX e Secure Boot Linux.
- Instalacao Ubuntu no disco 40 GiB, dados ext4 80 GiB montados em /var/lib/wazuh-indexer.
- Estado dos servicos (wazuh-indexer, wazuh-manager, wazuh-dashboard, filebeat).
- HTTPS local no Wazuh, UFW e sysctl; posterior login a partir da PAW com memoria suficiente.
- Log de validacao NAO sigiloso transportado em SFSETUP; credenciais nunca em videos/logs compartilhados.

## Resultado validacao Linux
Ver arquivo 09-Logs-Testes/12-WAZUH01-Resultado-Linux.txt. Nao incluiu credenciais Wazuh.
