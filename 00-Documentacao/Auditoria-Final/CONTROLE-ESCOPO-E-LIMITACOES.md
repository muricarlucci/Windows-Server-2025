# SmartFactory - Matriz de conformidade CP01/CP02/CP03

## Distincao fundamental
- Evidencia de CONFIGURACAO nao equivale a TESTE FUNCIONAL.
- Sem FILE02 e DC02: nao declarar DFS failover, DFSR, DHCP failover e replicacao AD.
- Sem copia fisica externa: nao declarar 3-2-1 ou imutabilidade completos.
- WAZUH01 7680 MiB e FW01 1536 MiB, ambos estaticos; DC01 dinamico.
- Wazuh 4.14.10 no Ubuntu 24.04.5; Manager/Indexer/Dashboard e Filebeat.
- Acesso ao Wazuh por chave e password auth devem ser verificadas, nao pressupostas.
- Testes com Windows+Wazuh simultaneamente podem exigir RAM indisponivel.
- 30 testes CP03 mapeados em MATRIZ_T01-T30.csv e STATUS_T01-T30.csv.
- CP01: segmentos, topologia, SF-LAN, trunk, VLAN99 nativa, gateways, NAT, ACL.
- CP02: AD/DNS/DHCP, IAM, SMB, DFSN, FSRM, VSS, dedup, IIS/HTTPS, backup.
- CP03: GPO/LAPS, PAW, baseline, SIEM/agentes, FIM/SCA/CTI, IR e evidencias.
