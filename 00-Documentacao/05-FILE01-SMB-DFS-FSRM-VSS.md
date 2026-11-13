# Etapa 05 - VM-FILE01 | SmartFactory-GS

Status: EM IMPLANTACAO, sujeito a validacao na VM.

## Escopo
- Windows Server 2025 Standard Server Core, VM Generation 2, VLAN 20, 10.20.20.15/24.
- 3 VHDX: sistema C: 60 GB, dados E: 500 GB, VSS S: 150 GB, todos dinamicos.
- Laboratorio reduzido: 3 GB RAM estatica, 2 vCPU, 1 vNIC (ao contrario do sizing corporativo).
- SMB assinatura obrigatoria e criptografia; pastas NTFS e compartilhamento Dados$.
- AGDLP (grupos existentes no AD), quotas FSRM e file screening ativo.
- DFS Namespace de dominio: \\smartfactory.corp\dados (um unico target FILE01).
- VSS: diff area em S: 120 GB; seg-sex 07:00 e 12:00.
- Data Deduplication (General Purpose, arquivos com >= 3 dias).
- DFSR/alta disponibilidade entre FILE01 e FILE02 NAO IMPLEMENTADOS: FILE02 omitida por RAM.
- Limites fisicos: VHDX de expansao dinamica nao reservam 710 GB de armazenamento real.

## Evidencias pendentes
- Hyper-V: VHDX, SCSI 0/1 e VLAN 20.
- Windows Server: rede, dominio, volumes GPT e NTFS.
- Compartilhamento Dados$, ACLs e sete departamentos.
- Namespace DFS; FSRM quotas e file screening; dedup e tarefas VSS.
- Testes positivos/negativos com usuarios e clientes: pendentes ate haver estacao de teste.

## Fontes
- CP-02 - secoes 20 a 37 e matriz AGDLP.
- CP-03 - Server Core, simplificacao 1 NIC, protecao SMB e DFSR assincrono.

## Validacao automatizada 2026-11-10 06:34:38
- Hyper-V e Windows Server: APROVADOS.
- Testes de login efetivo de usuarios, SMB e restore VSS: PENDENTES ate executar com cliente e arquivos de teste.

