# SmartFactory-GS | Etapa 11 — GPOs, Windows LAPS e Hardening

**Status inicial: nao executado.** Atualizar a conclusao somente com evidencias.

## Estado previo e limitacoes
- FW01 pfSense: 1536 MiB estaticos; WAZUH01 Ubuntu 24.04.5/Wazuh 4.14.10: 7680 MiB estaticos.
- WAZUH01 instalada e inicialmente validada; nao reiniciar instalador, nao recriar VM.
- DC01 RAM dinamica conforme ajuste anterior. Mantida sem alteracao.
- Nesta etapa, manter FW01 e DC01; ligar CLI-ADM01 somente no piloto; outras VMs Off.
- Nao alterar GPOs padrao Default Domain Policy/Default Domain Controllers Policy.
- Atualizacao Windows LAPS do schema AD e unidirecional. Backups e consentimento explicito.
- GPOs de servidores e de DC sao preparadas em modo faseado, sem link amplo automatico.

## Requisitos CP-03
- GPOs modulares para dominio, DC, member servers, DMZ, workstations, telemetria, LAPS, administracao remota.
- OU nativa Domain Controllers mantida; OU Piloto_GPO para teste real com CLI-ADM01.
- Baseline de contas existente no dominio: >=14 caracteres, historico 24, sem expiracao fixa, lockout 10/15min.
- Windows LAPS criptografado no AD, gerencia conta WLapsAdmin personalizada, senha 24, complexidade 5, 14 dias.
- Readers e Resetters separados; direitos estendidos auditados; senha nunca exibida em logs.
- Politica DC DSRM separada, com ativacao explicita apos verificar backup.
- Registrar gpresult, Windows LAPS event 10018, msLAPS-EncryptedPassword presente, sem segredo.

## Reducoes e pendencias
- Ainda nao aplicar baseline irrestrita em todos os servidores antes da prova piloto.
- Testes de SACL, GPO de producao, OSConfig, Sysmon e Wazuh ficam na proxima fase/homologacao.
- Extensao de schema AD nao e revertida com rollback de GPO.

## Registro de execucao

- EstruturarGPOs executado: 2026-11-12T21:57:53.

- PrepararLAPS: schema e permissoes configuradas, 2026-11-12T22:07:18.

- Publicacao autorizada em 2026-11-12T22:23:44.
