# SmartFactory-GS - Etapa 07: BKP01 e recuperacao

STATUS: EM IMPLEMENTACAO. Confirmar os testes antes de declarar concluido.

## Arquitetura
- VM-BKP01: Windows Server 2025 Standard Desktop Experience; Hyper-V Gen2; 2 vCPU.
- RAM dinamica: inicial 3 GB, minima 2 GB, maxima 4 GB (ajustar somente se necessario).
- VLAN 120, IP 10.20.120.10/24, gateway 10.20.120.1, DNS 10.20.20.11.
- Dominio smartfactory.corp; OU=Backup_Servers,OU=Servidores_Membros,OU=Infraestrutura.
- C: VHDX dinamico 60 GB; B: VHDX dinamico 200 GB (lab; CP02 previa 1 TB em producao).
- Compartilhamento de administracao SF_Repositorio$ com SMB encryption e acesso restrito.
- Dados FILE01: backup consistente OFFLINE do VHDX E: (VM-FILE01 desligada), versao datada, sem excluir copias anteriores.
- Restore: copia de arquivo do snapshot para pasta de teste e comparacao SHA256.
- DC01: System State verdadeiro com Windows Server Backup em VHDX separado. Arquivo transferido a BKP01 com ambas as VMs desligadas.

## Limitacoes documentadas
- Nesta maquina existe um UNICO disco fisico HDD para os VHDX: copia no BKP01 nao e offsite, imutavel nem 3-2-1 real.
- Metodo offline de arquivo e uma adaptacao consciente para nao ligar quatro VMs no host de 16 GB.
- Nao ha copia incremental diaria nem agenda independente quando as VMs ficam desligadas; plano corporativo: completo sabado e incremental/diferencial seg-sex.
- Backup de System State nao e equivalente a recuperacao do AD realizada; recuperacao destrutiva do DC nao sera executada no DC de producao do laboratorio.
- O armazenamento real no HDD continua limitado apesar dos VHDX dinamicos.
- FILE02, DC02, backup imutavel e alta disponibilidade nao foram implementados.

## Evidencias
- Hyper-V: BKP01, RAM, VLAN 120, discos C/B.
- Repositorio B: GPT, NTFS, share SMB e firewall.
- Backup offline FILE01: snapshot com data e arquivos copiados.
- Teste de restore: hashes de origem e destino iguais.
- Windows Server Backup no DC01 e identificacao do backup, se executado.
- Copia arquivada do System State no repositorio, se executada.
- Video 08 e log 09-BKP01-Backup-Restauracao-Resultado.txt.

- 2026-11-10 09:58:08: Repositorio B: e SMB configurados. Backup e restauraÃ§Ã£o ainda pendentes.

- 2026-11-10 09:59:04: Repositorio B: e SMB configurados. Backup e restauraÃ§Ã£o ainda pendentes.

- 2026-11-10 10:06:42: Backup FILE01 offline criado em B:\Repositorio\FILE01\Full\20261110_100642, Robocopy=1.

- 2026-11-10 10:16:43: T28 validado: recuperacao isolada de SF-TESTE-RESTAURACAO.txt, SHA256 igual.

- 2026-11-10 10:54:06: System State DC01 criado usando Windows Server Backup, em VHDX staging R:. Arquivamento separado pendente.

- 2026-11-10 11:04:49: System State DC01 arquivado em B:\Repositorio\DC01\SystemState\20261110_110311 (nao executar restauracao destrutiva).
