#Requires -Version 5.1
<#
SmartFactory-GS - Script 15: AUDITORIA FINAL CONTROLADA (CP01, CP02 e CP03)
Autor: pacote de apoio a laboratorio. Leitura e validacao; nao executa ataques ou restauracoes.
Fases: Preparar, Inventario, Firewall, Dominio, Arquivos, Intranet, Backup, Cliente,
       PAW, WazuhPreparar, WazuhColetar, VisitantesAtivar, VisitantesRestaurar,
       Registrar, Consolidar.
As fases de Windows usam PowerShell Direct e credencial administrativa do respectivo guest.
Nunca imprime senhas LAPS, DSRM, Wazuh, certificados privados nem hashes de senha.
#>
[CmdletBinding()]
param(
  [ValidateSet('Preparar','Inventario','Firewall','Dominio','Arquivos','Intranet','Backup',
               'Cliente','PAW','WazuhPreparar','WazuhColetar','VisitantesAtivar',
               'VisitantesRestaurar','Registrar','Consolidar')]
  [string]$Fase='Preparar',
  [string]$XmlPfSense='',
  [string]$Teste='',
  [ValidateSet('PENDENTE','VALIDADO','VALIDADO_ADAPTADO','FALHOU','LIMITACAO','NAO_APLICAVEL')]
  [string]$Status='PENDENTE',
  [string]$Evidencia='',
  [string]$Observacao=''
)
$ErrorActionPreference='Stop'
$Base='D:\FIAP\WINDOWS\SmartFactory-GS'
$Docs=Join-Path $Base '00-Documentacao\Auditoria-Final'
$Logs=Join-Path $Base '09-Logs-Testes\15-Auditoria-Final'
$Evs=Join-Path $Base '06-Evidencias\Auditoria-Final'
$Video=Join-Path $Base '07-Video\Roteiros'
$CsvMatriz=Join-Path $Docs 'MATRIZ_T01-T30.csv'
$CsvStatus=Join-Path $Docs 'STATUS_T01-T30.csv'
$CsvCP=Join-Path $Docs 'STATUS_C01-C40.csv'
$CsvChecks=Join-Path $Logs 'VERIFICACOES_TECNICAS.csv'
$Log=Join-Path $Logs ("15-{0}-{1}.txt" -f $Fase,(Get-Date -Format 'yyyyMMdd_HHmmss'))
$SFSETUP=Join-Path $Base '02-VMs\VM-WAZUH01\VM-WAZUH01-SFSETUP-256MB.vhdx'
$BashName='03-Auditar-Wazuh-Final.sh'
$BashLocal=Join-Path $Base ('03-Scripts\Gerados-Auditoria-Final\'+$BashName)
$Resultados=New-Object System.Collections.ArrayList

if(-not (Test-Path -LiteralPath $Base)){throw "Pasta base inexistente: $Base"}
foreach($d in @($Docs,$Logs,$Evs,$Video,(Split-Path $BashLocal -Parent))){
  if(-not(Test-Path -LiteralPath $d)){New-Item -Path $d -ItemType Directory -Force | Out-Null}
}
function Nota([string]$Texto){
  $l='[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Texto
  Write-Host $l
  Add-Content -LiteralPath $Log -Value $l -Encoding UTF8
}
function Check([string]$Id,[string]$Requisito,[bool]$Ok,[string]$Evid='', [string]$Detalhe=''){
  $st=if($Ok){'APROVADO'}else{'FALHOU'}
  [void]$Resultados.Add([pscustomobject]@{
    Fase=$Fase;ID=$Id;Verificacao=$Requisito;Resultado=$st;
    Evidencia=$Evid;Detalhe=$Detalhe;Data=(Get-Date).ToString('s')
  })
  Nota ('{0} | {1} | {2} {3}' -f $st,$Id,$Requisito,$Detalhe)
}
function Pend([string]$Id,[string]$Requisito,[string]$Motivo){
  [void]$Resultados.Add([pscustomobject]@{
    Fase=$Fase;ID=$Id;Verificacao=$Requisito;Resultado='NAO_EXECUTADO';
    Evidencia='';Detalhe=$Motivo;Data=(Get-Date).ToString('s')
  })
  Nota ('NAO_EXECUTADO | {0} | {1}: {2}' -f $Id,$Requisito,$Motivo)
}
function Rodando([string]$Vm){
  $v=Get-VM -Name $Vm -ErrorAction SilentlyContinue
  return ($null -ne $v -and $v.State -eq 'Running')
}
function Convidado([string]$Vm,[scriptblock]$Bloco,[object[]]$Args=@()){
  if(-not (Rodando $Vm)){throw "$Vm nao esta Running. Nao vou iniciar VM automaticamente."}
  $cred=Get-Credential -Message "Administrador de $Vm. Credencial apenas para PowerShell Direct."
  return Invoke-Command -VMName $Vm -Credential $cred -ScriptBlock $Bloco -ArgumentList $Args -ErrorAction Stop
}
function SalvarChecks(){
  if($Resultados.Count -eq 0){return}
  $anterior=@()
  if(Test-Path -LiteralPath $CsvChecks){$anterior=@(Import-Csv -LiteralPath $CsvChecks -Encoding UTF8)}
  $anterior=@($anterior | Where-Object {$_.Fase -ne $Fase})
  @($anterior)+@($Resultados.ToArray()) |
    Export-Csv -LiteralPath $CsvChecks -NoTypeInformation -Encoding UTF8
  Nota "Verificacoes gravadas: $CsvChecks"
}
function PrecisaPreparar(){
  if(-not (Test-Path -LiteralPath $CsvStatus)){throw 'Execute -Fase Preparar antes desta operacao.'}
}
function MontarSF([bool]$SomenteLeitura){
  if((Get-VM -Name VM-WAZUH01 -ErrorAction Stop).State -ne 'Off'){
    throw 'WAZUH01 precisa estar Off para montar SFSETUP no hospedeiro.'
  }
  if(-not(Test-Path -LiteralPath $SFSETUP)){throw "SFSETUP nao localizado: $SFSETUP"}
  Mount-VHD -Path $SFSETUP -ReadOnly:$SomenteLeitura -ErrorAction Stop | Out-Null
  try {
    $d=Get-DiskImage -ImagePath $SFSETUP | Get-Disk
    $vol=@($d | Get-Partition | Get-Volume | Where-Object { $_.FileSystemLabel -eq 'SFSETUP' -and $_.FileSystem -eq 'FAT32' }) | Select-Object -First 1
    if(-not $vol){throw 'Volume FAT32 SFSETUP nao identificado; NADA sera formatado.'}
    if(-not $vol.DriveLetter){throw 'SFSETUP sem letra; interrompido, sem alterar particoes.'}
    return ('{0}:\' -f $vol.DriveLetter)
  } catch {Dismount-VHD -Path $SFSETUP -ErrorAction SilentlyContinue;throw}
}
function DesmontarSF(){Dismount-VHD -Path $SFSETUP -ErrorAction SilentlyContinue}

$MATRIZ_CSV = @'
ID;Area;VMs_necessarias;Procedimento;Resultado_esperado;Classificacao;Nota_tecnica
T01;Rede/ACL;FW01 + CLI-ADM01 + host RH dedicado;Cliente ADM TCP445 para host RH;Bloqueio com log da regra no pfSense;LIMITACAO;Sem segundo endpoint na VLAN40, teste negativo contra gateway RH NAO equivale a firewall inter-host.
T02;Rede/SMB;"FW01 + FILE01 + CLI-ADM01; DC01 desligavel apos DHCP";Test-NetConnection 10.20.20.15 -Port 445;TcpTestSucceeded True, serviço SMB em FILE01;ADAPTADO;"TCP445 pode ser medido com DC desligado; acesso NTFS/AGDLP exige autenticação do domínio."
T03;Visitantes;FW01 + DC01 + CLI-ADM01 (temporariamente na VLAN999);Concessão 10.20.200.x e teste de destinos privados;10.20.0.0/16 bloqueado com log e DNS publico;EXECUTAVEL;"Restaurar CLI-ADM01 para Access VLAN30 no final; testar sem alterar sua conta AD."
T04;DMZ/IIS;"FW01 + CLI-ADM01 + WEB01; DC01 se couber";Test-NetConnection 10.20.100.10 -Port 443;Porta 443 alcançável, HTTPS/401 do IIS;EXECUTAVEL;Teste HTTPS autenticado/SSO precisa do DC01 online.
T05;Rede/ACL;FW01 + WEB01 + host real RH;WEB01 tenta iniciar conexão a host RH;Negado e registrado no firewall;LIMITACAO;"Destino RH ausente; teste contra gateway RH nao demonstra bloqueio a endpoint."
T06;Admin;FW01 + CLI-ADM01 + WEB01;CLI-ADM01 tenta TCP3389 no WEB01;Negado pela ACL com log;ADAPTADO;Sem log pfSense nao declarar que firewall causou a falha.
T07;Admin;FW01 + PAW-TI01 + WEB01, DC01 para credencial NLA;PAW abre RDP com NLA ao WEB01;Sessao administrativa autenticada;ADAPTADO;Se nao couberem FW+DC+PAW+WEB, verificar TCP3389 e registrar limitação de autenticação.
T08;Admin;FW01 + DC01 + PAW-TI01;Test-WSMan VM-DC01 a partir da PAW;WinRM/Kerberos funcional;EXECUTAVEL;"Com credencial admin autorizada; nao usar Basic ou TrustedHosts=*."
T09;Admin/SIEM;FW01 + WAZUH01 + host Windows como origem nao PAW;Test-NetConnection 10.20.110.10 -Port 22;"Porta inacessivel para origem nao PAW; log";ADAPTADO;"Host (VLAN10) substitui estacao comum da TI; verificar regras pfSense/UFW."
T10;Admin/SIEM;FW01 + WAZUH01 + PAW-TI01;ssh -i chave sfadmin@10.20.110.10;Login por chave somente da PAW;LIMITACAO;7,5 + 1,5 + pelo menos 4 GiB excedem capacidade livre atual.
T11;Linux/SSH;WAZUH01 isolado + console;sshd -T e teste de PasswordAuthentication;PasswordAuthentication no;PENDENCIA_CONFIG;Script anterior manteve password auth habilitada ate chave de PAW comprovada.
T12;GPO;FW01 + DC01 + CLI-ADM01;gpresult /r /scope computer;GPO baseline e LAPS efetivamente aplicadas;EXECUTAVEL;Anexar gpresult HTML sem dados sensíveis.
T13;LAPS;FW01 + DC01;Get-LapsADPassword autorizado sem imprimir Password;Consulta e decriptação autorizadas;EXECUTAVEL;Nao exportar senha nem -AsPlainText para arquivos de evidencia.
T14;LAPS;FW01 + DC01 + CLI-ADM01 em login lab.adm01;Get-LapsADPassword na sessao de usuario comum;Acesso negado;EXECUTAVEL;Anotar somente mensagem de Access Denied, nao senhas.
T15;LAPS;FW01 + DC01 + CLI-ADM01;Reset-LapsPassword e consultar evento 10018;Nova expiração e sucesso de escrita no AD;EXECUTAVEL_COM_CUIDADO;"Altera senha local; executar conscientemente e guardar acesso de contingência."
T16;LAPS/rollback;Clone descartavel isolado + AD seguro;Rollback de VM e nova rotacao de LAPS;Senha antiga nao reutilizavel;LIMITACAO;"Checkpoint/rollback de endpoint dominio pode causar trust/cache; nao executar em VM unica de produção de laboratório."
T17;Wazuh/eventos;FW01 + WAZUH01 + Windows agente ativo;Falhas logon repetidas controladas e consulta alerta;Alerta no Dashboard;LIMITACAO;"Requer simultaneidade SIEM e endpoint; alternativa logtest so prova regra, nao ponta a ponta."
T18;Wazuh/eventos;FW01 + WAZUH01 + DC01;Criar usuário teste e localizar 4720 no Wazuh;Evento 4720 ingerido;LIMITACAO;"Nao repetir criacao de usuario sem necessidade; requisito exige agente e Wazuh online juntos."
T19;Wazuh/eventos;FW01 + WAZUH01 + DC01;Mudanca controlada em grupo privilegiado e alerta;Alerta crítico;RISCO_NAO_AUTOMATIZAR;"Nao modificar Domain Admins para testar; usar laboratorio descartavel e GMUD."
T20;Wazuh/eventos;VM Windows de testes descartavel + WAZUH;Limpar log Security no endpoint descartavel;Evento 1102 crítico no Dashboard;RISCO_NAO_AUTOMATIZAR;"Limpeza destrói evidencias; nao executar automaticamente em host real."
T21;FIM;FW01 + WAZUH01 + WEB01;Alterar arquivo teste no diretorio real do IIS;Alerta FIM visível no Wazuh;LIMITACAO;"Host de intranet real C:\inetpub\SmartFactory-Intranet; simultaneidade excede RAM."
T22;PowerShell/telemetria;FW01 + WAZUH01 + endpoint Windows;Gerar evento 4104 benigno e consultar Wazuh;Evento 4104 ingerido;LIMITACAO;"Evento local 4104 separado da ingestão; testar ambos quando coexistência viável."
T23;Sysmon;FW01 + WAZUH01 + CLI-ADM01;Processo benigno, canal Sysmon EventID 1;Evento 1 ingerido;LIMITACAO;Sysmon local pode provar geracao, nao entrega ao SIEM sem VMs juntas.
T24;Defender;FW01 + WAZUH01 + endpoint Windows;Consultar evento historico benigno do Defender;Evento de Defender ingerido;LIMITACAO;Nao desabilitar Defender nem baixar amostras suspeitas para produzir teste.
T25;Vulnerability Detection;WAZUH01 isolada;Dashboard Vulnerabilities ou Manager configuracao;Inventario/CVE ou evidência de ausencia;ADAPTADO;"Pode conferir Indexer/Manager; CVEs de agente Windows precisam de ingestao."
T26;Auditoria ACL;FW01 + WAZUH01 + FILE01;Altera ACL em arquivo teste e busca 4670;Evento 4670 no Dashboard;LIMITACAO;"4670 depende de SACL/Audit Policy; requer simultaneidade de Wazuh e FILE01."
T27;Agente offline;FW01 + WAZUH01;agent_control -l e status do agente previamente cadastrado;Offline detectado apos janela de timeout;ADAPTADO;"Valido se agente ja tiver registrado em algum momento; nao prova canal ativo."
T28;Backup/restore;BKP01 ou offline VHDX de repositorio;Comparar SHA256 do arquivo original arquivado e restaurado;Hashes identicos e backup com timestamp;EXECUTAVEL;"Teste ja relatado executado na etapa de backup; recolher evidencia sem restaurar por cima."
T29;System State;DC01 clone descartavel ou ambiente de recuperacao;Catalogar wbadmin e descrever restore controlado;Restore validado sem perder dominio;RISCO_NAO_AUTOMATIZAR;"No DC unico, fazer restore real nao e seguro; comprovacao de backup != restore."
T30;DFS failover;FILE01 e FILE02 com destinos redundantes;Desligar FILE01 e manter DFS em FILE02;\\smartfactory.corp\dados acessivel via FILE02;NAO_APLICAVEL;"FILE02 nao foi implantado; demonstrar somente DFS Namespace de destino unico, sem alegar failover."
'@
$CP_CSV = @'
ID;Controle;Comprovacao_ou_limite
C01;Host Hyper-V e switches;`Get-VMSwitch`, nome/tipo SF-LAN, host IP 10.20.10.10
C02;VLAN tags e nativa;"VLAN99 nativa; VLAN10 tagged; VLANs 20–120 e 999; pfSense XML+GUI"
C03;Gateways;`.1/24` por VLAN e ping/TCP de endpoint compatível
C04;Firewall deny + allow;logs e states por regra, **origem e destino reais**
C05;NAT outbound;modo automático + conexão Internet a partir de endpoint
C06;DHCP Relay;opção oito interfaces e concessão real VLAN30 e VLAN999
C07;WAN;"IP DHCP NAT do Default Switch; sem inbound aberto"
C08;Gestão do firewall;host ou PAW, exceção de laboratório host documentada
C09;Host físico redundante e SET;não implementado, ambiente único Windows 11 Pro
C10;AD DS domínio;`Get-ADDomain`, `Get-ADForest`, SYSVOL e DC Locator SRV
C11;IAM/OUs/AGDLP;7 departamentos, OUs de contas, GG→DL→NTFS
C12;Níveis funcionais AD 2025;Get-ADDomain e Get-ADForest
C13;DNS integrado AD;zonas direta/reversa, SRV/A/PTR, secure dynamic update
C14;DNS forwarder;Get-DnsServerForwarder e resolve externo
C15;DHCP autorizado AD;Get-DhcpServerInDC, 8 scopes, lease/exclusions/options
C16;DHCP Failover;não implementado sem DC02
C17;SMB 3.1.1 assinatura/criptografia;Get-SmbServerConfiguration/Get-SmbConnection, conta comum quando couber
C18;DFS Namespace 7 pastas;Get-DfsnRoot/Get-DfsnFolder e destino FILE01
C19;DFSR/FILE02;não implementado sem FILE02
C20;ACL por departamento;icacls + prova de acesso autorizado/negado
C21;FSRM quotas hard/soft;"Get-FsrmQuota; 7 departamentos e seus limites"
C22;FSRM triagem;Get-FsrmFileScreen e arquivo teste não executável
C23;VSS volume S:;vssadmin list shadowstorage/shadows e scheduled task
C24;Data Dedup;Get-DedupVolume e Get-DedupStatus
C25;NTFS/GPT/VHDX dinâmico;Get-Disk/Get-Volume e Get-VMHardDiskDrive
C26;IIS HTTP301;curl -I HTTP + Location HTTPS
C27;IIS HTTPS certificado/TLS;bindings, cert e handshake real
C28;WindowsAuth/Kerberos;política IIS, CNAME/SPN, login cliente/klist
C29;DMZ WEB;VLAN100, NLA e firewall local por origem
C30;BKP01 repositório;VLAN120, NTFS/SMB, snapshot+hash T28
C31;DC01 System State;catálogo wbadmin + cópia offline (restore não testado)
C32;Hardening Server Core;SConfig, OS build, firewall local, SMB1 e WinRM
C33;GPOs modular/piloto;GPMC links, backups, gpresult, rollback da OU Piloto_GPO
C34;LAPS AD cifrado e delegação;atributo cifrado, ACL readers/resetters, eventos 10018
C35;PAW e contas adm.*;IP reservado, fonte WinRM/RDP, local admin escopado
C36;Ubuntu/Wazuh;24.04.5, 4.14.10, Indexer/Manager/Dashboard/Filebeat, UFW/AppArmor
C37;Agentes Windows;WazuhSvc + ossec.conf (local), cadastro/ingestao remota pendente
C38;Sysmon/FIM/SCA/vulnerabilidade;canais, scan, alertas de detecção, limitações de RAM
C39;Backup 3-2-1 e DR;política documentada, não implementado fisicamente
C40;Resposta a incidente e GMUD;playbooks, cronologia, rollback, documentação e evidência
'@
$ROTEIRO_AUDITORIA = @'
SMARTFACTORY — VIDEO 14 | AUDITORIA FINAL DOS TRES CPS
Duração-alvo: aproximadamente 3 minutos. Este é um roteiro-base: substitua os campos de resultado antes de gravar.

Depois de concluirmos as doze etapas de configuração da SmartFactory, iniciamos a auditoria final para verificar se a infraestrutura realmente entrega os serviços previstos nos três CPs. Diferentemente dos vídeos anteriores, aqui não basta demonstrar que os comandos foram executados: precisamos apresentar o comportamento real de cada controle, suas evidências e também as limitações do laboratório.

Primeiro, revisamos o inventário do Hyper-V e comparamos as oito máquinas, os discos e as VLANs com a arquitetura planejada. Mantivemos as adaptações necessárias ao computador de dezesseis gigabytes de RAM: a FW01 com um gigabyte e meio, o Wazuh com sete gigabytes e meio e o controlador de domínio com memória dinâmica. Os testes foram divididos por combinações pequenas de máquinas, evitando executar todo o ambiente simultaneamente.

No bloco de rede, conferimos o trunk com VLAN nativa noventa e nove, as treze VLANs etiquetadas, os gateways, as regras de firewall, o NAT e o DHCP Relay. Para demonstrar os bloqueios, relacionamos as tentativas de acesso aos logs do pfSense; uma porta fechada, isoladamente, não prova que a regra funcionou. O resultado observado neste bloco foi: [INSERIR RESUMO VERIFICADO].

Depois validamos o controlador de domínio, as zonas DNS, os oito escopos DHCP, as unidades organizacionais, os grupos de segurança, as GPOs e o Windows LAPS. Na estação cliente, usamos endereço obtido por DHCP, conta comum do domínio e relatórios gpresult. Nas máquinas de arquivos e intranet, conferimos SMB, DFS, quotas, Shadow Copies, IIS, certificado HTTPS, autenticação Windows e os registros de DNS e Kerberos. Os resultados documentados foram: [INSERIR EVIDENCIAS REAIS].

Também examinamos a BKP01 e os backups já produzidos. A restauração de um arquivo foi comprovada pela comparação SHA-256. O backup de estado do sistema foi verificado, mas não realizamos uma restauração destrutiva sobre o único controlador de domínio.

Finalmente, auditamos o Ubuntu e os componentes do Wazuh: Manager, Indexer, Filebeat, Dashboard, portas, UFW, AppArmor e agentes cadastrados. Por limitação física de memória, os testes que exigem Wazuh e endpoints Windows ao mesmo tempo foram registrados separadamente, sem alegar coleta que não comprovamos. Do mesmo modo, os testes que dependem de DC02 ou FILE02 foram identificados como não aplicáveis à versão reduzida.

Encerramos com a matriz de trinta testes do CP3, verificações adicionais dos CPs 01 e 02, capturas e logs organizados. O resultado final consolidado foi: [INSERIR CONTAGENS DE VALIDADO, ADAPTADO, LIMITADO E PENDENTE].
'@
$WAZUH_BASH = @'
#!/usr/bin/env bash
# SmartFactory - auditoria nao destrutiva Wazuh 4.14.10; nao exporta credenciais.
set -u
OUT="/root/smartfactory-wazuh/AUDITORIA_WAZUH_FINAL.txt"
mkdir -p /root/smartfactory-wazuh
exec > >(tee "$OUT") 2>&1
printf 'SMARTFACTORY WAZUH AUDITORIA %s\n' "$(date -Is)"
cat /etc/os-release | grep -E '^(NAME|VERSION_ID)=' || true
hostnamectl --static || hostname
ip -br -4 addr || true
free -h
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS
printf '\nSTATUS DOS SERVICOS\n'
for svc in wazuh-manager wazuh-indexer wazuh-dashboard filebeat; do
  printf '%s: ' "$svc";systemctl is-active "$svc" 2>/dev/null || true
done
printf '\nDISCO INDEXER / MOUNT\n'
findmnt /var/lib/wazuh-indexer || true
df -h / /var/lib/wazuh-indexer || true
printf '\nHARDENING LINUX\n'
sysctl vm.max_map_count || true
sudo ufw status numbered || true
sudo aa-status --enabled || true
printf '\nPORTAS LOCAIS DE ESCUTA\n'
ss -lnt | grep -E '(:22 |:443 |:1514 |:1515 |:55000 |:9200 )' || true
printf '\nHTTPS LOCAL\n'
curl -sk -o /dev/null -w 'HTTP_CODE=%{http_code}\n' --max-time 10 https://127.0.0.1/ || true
printf '\nAGENTES CADASTRADOS\n'
/var/ossec/bin/agent_control -l 2>&1 | head -65 || true
printf '\nSSH CONFIGURACAO EFETIVA (sem segredos)\n'
/usr/sbin/sshd -T 2>/dev/null | grep -E '^(permitrootlogin|passwordauthentication|pubkeyauthentication)' || true
printf '\nVULNERABILITY (configuracao NAO comprova CVEs)\n'
grep -A 5 '<vulnerability-detection>' /var/ossec/etc/ossec.conf || true
printf '\nCONCLUSAO\nValidar Dashboard, agente online e alertas separadamente. ESTE ARQUIVO NAO PROVA INGESTAO WINDOWS.\n'
if mountpoint -q /mnt/sfsetup; then
  cp -f "$OUT" /mnt/sfsetup/AUDITORIA_WAZUH_FINAL.txt && sync && echo 'RELATORIO COPIADO PARA SFSETUP'
else
  echo 'SFSETUP nao montada: saida permanece em /root/smartfactory-wazuh/AUDITORIA_WAZUH_FINAL.txt'
fi
'@

try {
  switch($Fase){
    'Preparar' {
      if(-not(Test-Path -LiteralPath $CsvMatriz)){
        $MATRIZ_CSV | Set-Content -LiteralPath $CsvMatriz -Encoding UTF8
      }
      if(-not(Test-Path -LiteralPath $CsvCP)){
        @(ConvertFrom-Csv -InputObject ($CP_CSV -split "`n") -Delimiter ';') | ForEach-Object {
          [pscustomobject]@{ID=$_.ID;Controle=$_.Controle;Status='PENDENTE';
            Evidencia='';Observacao='';Atualizado=''}
        } | Export-Csv -LiteralPath $CsvCP -NoTypeInformation -Encoding UTF8
      }
      if(-not(Test-Path -LiteralPath $CsvStatus)){
        $rows=@(ConvertFrom-Csv -InputObject ($MATRIZ_CSV -split "`n") -Delimiter ';')
        $rows | ForEach-Object {
          [pscustomobject]@{ID=$_.ID;Area=$_.Area;Classificacao=$_.Classificacao;
            Status='PENDENTE';Evidencia='';Observacao='';Atualizado=''}
        } | Export-Csv -LiteralPath $CsvStatus -NoTypeInformation -Encoding UTF8
      }
      if(-not(Test-Path -LiteralPath $BashLocal)){
        [System.IO.File]::WriteAllText($BashLocal, $WAZUH_BASH,
          ([System.Text.UTF8Encoding]::new($false)))
      }
      $videoDestino=Join-Path $Video 'Roteiro_Video_Etapa_14.txt'
      if(-not(Test-Path -LiteralPath $videoDestino)){
        $ROTEIRO_AUDITORIA | Set-Content -LiteralPath $videoDestino -Encoding UTF8
      }
      $guide=Join-Path $PSScriptRoot 'GUIA-AUDITORIA-FINAL-COMPLETO.md'
      $target=Join-Path $Docs 'GUIA-AUDITORIA-FINAL-COMPLETO.md'
      if((Test-Path -LiteralPath $guide) -and -not(Test-Path -LiteralPath $target)){
        Copy-Item -LiteralPath $guide -Destination $target
      }
      $cp=@'
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
'@
      $cp | Set-Content -LiteralPath (Join-Path $Docs 'CONTROLE-ESCOPO-E-LIMITACOES.md') -Encoding UTF8
      Check 'A00' 'Matriz de 30 testes criada' (Test-Path -LiteralPath $CsvStatus)
      Check 'A01' 'Script Linux de auditoria criado' (Test-Path -LiteralPath $BashLocal)
      Check 'A02' 'Matriz C01-C40 criada' (Test-Path -LiteralPath $CsvCP)
      Nota 'PREPARACAO CONCLUIDA: script apenas criou documentos e matriz. Nao mudou VM.'
    }
    'Inventario' {
      Import-Module Hyper-V -ErrorAction Stop
      $vms=@('VM-FW01','VM-DC01','VM-FILE01','VM-WEB01','VM-BKP01','CLI-ADM01','PAW-TI01','VM-WAZUH01')
      foreach($vm in $vms){
        $v=Get-VM -Name $vm -ErrorAction SilentlyContinue
        Check ("HV-"+$vm) ("VM existente: "+$vm) ($null -ne $v) '' $(if($v){'State='+$v.State}else{'Nao encontrada'})
        if($v){
          $m=Get-VMMemory -VMName $vm
          $nic=@(Get-VMNetworkAdapter -VMName $vm | Where-Object SwitchName -eq 'SF-LAN' | Select-Object -First 1)
          $vlan=if($nic.Count){Get-VMNetworkAdapterVlan -VMName $vm -VMNetworkAdapterName $nic[0].Name}else{$null}
          Nota ("{0}: State={1}; MemAssigned={2:N2}GiB; Startup={3:N2}GiB; Dynamic={4}; VLAN={5}" -f $vm,$v.State,($v.MemoryAssigned/1GB),($m.Startup/1GB),$m.DynamicMemoryEnabled,$vlan.AccessVlanId)
        }
      }
      $mem=Get-CimInstance Win32_OperatingSystem
      Nota ('HOST RAM Livre={0:N2} GiB' -f ($mem.FreePhysicalMemory/1MB))
      Check 'HV09' 'FW01 estatico 1536MiB' ((Get-VMMemory VM-FW01).Startup -eq 1536MB -and -not (Get-VMMemory VM-FW01).DynamicMemoryEnabled)
      Check 'HV10' 'WAZUH01 estatico 7680MiB' ((Get-VMMemory VM-WAZUH01).Startup -eq 7680MB -and -not (Get-VMMemory VM-WAZUH01).DynamicMemoryEnabled)
      Check 'HV11' 'DC01 memoria dinamica' ([bool](Get-VMMemory VM-DC01).DynamicMemoryEnabled)
    }
    'Firewall' {
      Import-Module Hyper-V -ErrorAction Stop
      if(Rodando 'VM-FW01'){
        $vpn=Get-VMNetworkAdapterVlan -VMName 'VM-FW01' -VMNetworkAdapterName 'LAN'
        Check 'RE01' 'Trunk LAN NativeVlan 99' ($vpn.OperationMode -eq 'Trunk' -and $vpn.NativeVlanId -eq 99)
        $https=Test-NetConnection -ComputerName '10.20.10.1' -Port 443 -WarningAction SilentlyContinue
        Check 'RE02' 'pfSense HTTPS da VLAN MGMT' ([bool]$https.TcpTestSucceeded)
      }else{Pend 'RE01' 'Trunk e HTTPS pfSense' 'Ligue FW01 e execute novamente.'}
      if($XmlPfSense -and (Test-Path -LiteralPath $XmlPfSense)){
        # XML original pode conter SEGREDOS. Lemos localmente sem copia-lo ao relatorio.
        [xml]$x=Get-Content -LiteralPath $XmlPfSense -Raw -Encoding UTF8
        if($x.DocumentElement.LocalName -ne 'pfsense'){throw 'XML fornecido nao e configuracao pfSense.'}
        $vlan=@($x.pfsense.vlans.vlan)
        $tags=@($vlan | ForEach-Object {[string]$_.tag})
        $wanted=@('10','20','30','40','50','60','70','80','90','100','110','120','999')
        Check 'RE03' '13 VLANs previstas, sem VLAN99 tagged' (($wanted | Where-Object {$_ -notin $tags}).Count -eq 0 -and $tags -notcontains '99' -and $vlan.Count -eq 13)
        $gateways=@('10.20.10.1','10.20.20.1','10.20.30.1','10.20.40.1','10.20.50.1','10.20.60.1','10.20.70.1','10.20.80.1','10.20.90.1','10.20.100.1','10.20.110.1','10.20.120.1','10.20.200.1')
        $actual=@($x.pfsense.interfaces.ChildNodes | Where-Object Name -ne 'wan' | ForEach-Object {[string]$_.ipaddr})
        Check 'RE04' '13 gateways .1/24' (($gateways|Where-Object {$_ -notin $actual}).Count -eq 0) '' ($actual -join ',')
        $nRule=@($x.pfsense.filter.rule).Count
        Check 'RE05' 'Regras pfSense >=47' ($nRule -ge 47) '' ('Numero='+$nRule)
        $nAlias=@($x.pfsense.aliases.alias).Count
        Check 'RE06' 'Aliases pfSense >=20' ($nAlias -ge 20) '' ('Numero='+$nAlias)
        Check 'RE07' 'Outbound NAT automatico' ([string]$x.pfsense.nat.outbound.mode -eq 'automatic')
        $relayInterfaces=([string]$x.pfsense.dhcrelay.interface).Split(',')
        Check 'RE08' 'DHCP Relay para DC01 e 8 interfaces' ([string]$x.pfsense.dhcrelay.server -eq '10.20.20.11' -and $relayInterfaces.Count -eq 8)
        Pend 'RE09' 'ACLs de permit/deny comprovadas' 'Apenas ler XML nao prova filtragem; usar pacote real + firewall log/States.'
        Nota 'XML analisado localmente; arquivo completo nao foi copiado (contem segredos).'
      }else{Pend 'RE03' 'Revisao da configuracao pfSense atual' 'Exporte XML atual do pfSense e informe -XmlPfSense CAMINHO, sem enviar XML bruto.'}
    }
    'Dominio' {
      if(-not(Rodando 'VM-DC01')){Pend 'AD00' 'DC01 ativo' 'Ligue DC01 (e FW01) antes';break}
      try {
        $r=Convidado 'VM-DC01' {
          Import-Module ActiveDirectory -ErrorAction Stop
          $domain=Get-ADDomain -ErrorAction Stop
          $forest=Get-ADForest -ErrorAction Stop
          $scopes=@(Get-DhcpServerv4Scope -ErrorAction SilentlyContinue)
          $dnszones=@(Get-DnsServerZone -ErrorAction SilentlyContinue)
          $ous=@(Get-ADOrganizationalUnit -Filter * -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
          $gpo=@();try{Import-Module GroupPolicy;$gpo=@(Get-GPO -All | Select-Object -ExpandProperty DisplayName)}catch{}
          $laps=$null;try{$laps=Get-ADComputer -Identity 'CLI-ADM01' -Properties 'msLAPS-EncryptedPassword' -ErrorAction Stop}catch{}
          $srvs=@(Get-ADDomainController -Filter * -ErrorAction SilentlyContinue)
          $shares=@(Get-SmbShare -Name SYSVOL,NETLOGON -ErrorAction SilentlyContinue)
          $dcdiag=& dcdiag.exe /q 2>&1 | Out-String
          $exit=$LASTEXITCODE
          [pscustomobject]@{Domain=$domain.DNSRoot;NetBIOS=$domain.NetBIOSName;
            DomainMode=[string]$domain.DomainMode;ForestMode=[string]$forest.ForestMode;
            Controllers=$srvs.Count;ScopeCount=$scopes.Count;Scopes=@($scopes.ScopeId.IPAddressToString);
            Zones=@($dnszones.ZoneName);OUs=$ous;Gpos=$gpo;
            LapsEncrypted=[bool]($laps -and $laps.'msLAPS-EncryptedPassword');
            Shares=@($shares.Name);DcdiagCode=$exit;DcdiagOutput=$dcdiag.Trim()}
        }
        Check 'AD01' 'Dominio smartfactory.corp' ($r.Domain -eq 'smartfactory.corp') '' ($r.Domain)
        Check 'AD02' 'NetBIOS SMARTFACTORY' ($r.NetBIOS -eq 'SMARTFACTORY')
        Check 'AD03' 'Nivel funcional 2025' ($r.DomainMode -match '2025' -and $r.ForestMode -match '2025') '' ("Dominio="+$r.DomainMode+' Floresta='+$r.ForestMode)
        Check 'AD04' 'Zona DNS integrada smartfactory.corp' ($r.Zones -contains 'smartfactory.corp')
        Check 'AD05' 'Zona DNS reversa /16' ($r.Zones -contains '20.10.in-addr.arpa')
        Check 'AD06' '8 escopos DHCP ativos/configurados' ($r.ScopeCount -eq 8) '' ($r.Scopes -join ',')
        Check 'AD07' 'SYSVOL/NETLOGON' (($r.Shares -contains 'SYSVOL') -and ($r.Shares -contains 'NETLOGON'))
        Check 'AD08' 'OUs Infraestrutura, SmartFactory, Piloto_GPO' (($r.OUs -contains 'Infraestrutura') -and ($r.OUs -contains 'SmartFactory') -and ($r.OUs -contains 'Piloto_GPO'))
        Check 'AD09' 'GPO Endpoint, Audit, LAPS' (($r.Gpos -contains 'SF-Endpoint-Baseline') -and ($r.Gpos -contains 'SF-Audit-Telemetry') -and ($r.Gpos -contains 'SF-LAPS-Workstations'))
        Check 'AD10' 'LAPS criptografado CLI-ADM01 existe no AD' $r.LapsEncrypted
        Check 'AD11' 'DCDIAG sem erros (modo /q)' ($r.DcdiagCode -eq 0 -and [string]::IsNullOrWhiteSpace($r.DcdiagOutput)) '' ($r.DcdiagOutput.Substring(0,[Math]::Min(350,$r.DcdiagOutput.Length)))
        Pend 'AD12' 'Replicacao AD/DC failover' 'Nao existe DC02 na topologia reduzida.'
        Pend 'AD13' 'LAPS autorizado/negado e rotacao' 'Testes T13-T15 requerem usuarios/credenciais adequados; nao exportar senhas.'
      }catch{Pend 'AD00' 'Conexao PowerShell Direct DC01' $_.Exception.Message}
    }
    'Arquivos' {
      if(-not(Rodando 'VM-FILE01')){Pend 'FS00' 'FILE01 ativo' 'Ligue FILE01. Mantenha FW01/DC01 se necessarios.';break}
      try {
        $r=Convidado 'VM-FILE01' {
          $share=Get-SmbShare -Name 'Dados$' -ErrorAction SilentlyContinue
          $smb=Get-SmbServerConfiguration
          $roots=@();$folders=@();try{$roots=@(Get-DfsnRoot -ErrorAction Stop | Select-Object -ExpandProperty Path);$folders=@(Get-DfsnFolder -Path '\\smartfactory.corp\dados\*' -ErrorAction SilentlyContinue)}catch{}
          $quotas=@();try{$quotas=@(Get-FsrmQuota -Path 'E:\Dados\*' -ErrorAction SilentlyContinue)}catch{}
          $screen=$null;try{$screen=Get-FsrmFileScreen -Path 'E:\Dados' -ErrorAction SilentlyContinue}catch{}
          $ded=$null;try{$ded=Get-DedupVolume -Volume 'E:' -ErrorAction SilentlyContinue}catch{}
          $vss=(& vssadmin.exe list shadowstorage /for=E: 2>&1 | Out-String)
          $vols=@(Get-Volume -DriveLetter E,S -ErrorAction SilentlyContinue | Select-Object DriveLetter,FileSystem)
          [pscustomobject]@{ShareExists=[bool]$share;SharePath=[string]$share.Path;
            ShareEncrypted=[bool]$share.EncryptData;RequireSigning=[bool]$smb.RequireSecuritySignature;
            SMB1Enabled=[bool]$smb.EnableSMB1Protocol;DFSRoot=@($roots -contains '\\smartfactory.corp\dados');
            DFSFolders=$folders.Count;Quotas=$quotas.Count;ScreenActive=[bool]($screen -and $screen.Active);
            Dedup=[bool]$ded;VSSonS=($vss -match 'S:');Volumes=$vols}
        }
        Check 'FS01' 'Dados$ em E:\Dados' ($r.ShareExists -and $r.SharePath -eq 'E:\Dados')
        Check 'FS02' 'Dados$ SMB criptografado' $r.ShareEncrypted
        Check 'FS03' 'SMB assinatura obrigatoria, SMB1 off' ($r.RequireSigning -and -not $r.SMB1Enabled)
        Check 'FS04' 'DFS Namespace dominio unico' ([bool]$r.DFSRoot) '' ('Links='+$r.DFSFolders)
        Check 'FS05' 'FSRM >=7 quotas' ($r.Quotas -ge 7) '' ('Quotas='+$r.Quotas)
        Check 'FS06' 'FSRM FileScreen ativo' $r.ScreenActive
        Check 'FS07' 'Desduplicacao ativa em E:' $r.Dedup
        Check 'FS08' 'VSS diff area em S:' $r.VSSonS
        Check 'FS09' 'Volumes E e S em NTFS' (($r.Volumes|Where-Object {$_.FileSystem -eq 'NTFS'}).Count -eq 2)
        Pend 'FS10' 'Acesso funcional de usuario RH/ADM a suas pastas' 'Requer autenticacao como usuario comum e DC junto de FILE e cliente.'
        Pend 'FS11' 'Failover DFSR' 'Nao implementado: apenas FILE01.'
      }catch{Pend 'FS00' 'PowerShell Direct FILE01' $_.Exception.Message}
    }
    'Intranet' {
      if(-not(Rodando 'VM-WEB01')){Pend 'WEB00' 'WEB01 ativo' 'Ligue WEB01 com FW01; DC01 se necessario.';break}
      try{
        $r=Convidado 'VM-WEB01' {
          Import-Module WebAdministration -ErrorAction Stop
          $site=Get-Website -Name 'SF-Intranet' -ErrorAction SilentlyContinue
          $bindings=@(Get-WebBinding -Name 'SF-Intranet' -ErrorAction SilentlyContinue)
          $win=$null;$anon=$null
          try {$win=(Get-WebConfigurationProperty -PSPath 'IIS:\Sites\SF-Intranet' -Filter 'system.webServer/security/authentication/windowsAuthentication' -Name enabled).Value}catch{}
          try {$anon=(Get-WebConfigurationProperty -PSPath 'IIS:\Sites\SF-Intranet' -Filter 'system.webServer/security/authentication/anonymousAuthentication' -Name enabled).Value}catch{}
          $pool=$null;try{$pool=Get-WebAppPoolState -Name 'SF-Intranet-Pool'}catch{}
          $https=@($bindings | Where-Object protocol -eq 'https')
          $all=@(Get-Website -ErrorAction SilentlyContinue)
          $fw=@(Get-NetFirewallRule -DisplayName 'SF-Intranet-*' -ErrorAction SilentlyContinue)
          $certs=@(Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object {$_.Subject -match 'intranet.smartfactory.corp'})
          [pscustomobject]@{Site=[bool]$site;Dir=(Test-Path 'C:\inetpub\SmartFactory-Intranet');
            Https=$https.Count;Sites=$all.Count;AppPool=([string]$pool.Value);
            WindowsAuth=[bool]$win;AnonymousAuth=[bool]$anon;Cert=$certs.Count;
            FirewallRules=$fw.Count}
        }
        Check 'WEB01' 'IIS site SF-Intranet presente' $r.Site
        Check 'WEB02' 'Diretorio real da intranet' $r.Dir
        Check 'WEB03' 'Binding HTTPS presente' ($r.Https -gt 0)
        Check 'WEB04' 'ApplicationPool SF-Intranet-Pool Started' ($r.AppPool -eq 'Started')
        Check 'WEB05' 'WindowsAuth ligado e anonimo desligado' ($r.WindowsAuth -and -not $r.AnonymousAuth)
        Check 'WEB06' 'Certificado local intranet' ($r.Cert -gt 0)
        Check 'WEB07' 'Regras locais da intranet' ($r.FirewallRules -ge 2)
        Pend 'WEB08' 'HTTP 301, TLS negociado, login Kerberos' 'Exige teste HTTP real de um cliente com DC; validar no roteiro.'
      }catch{Pend 'WEB00' 'PowerShell Direct WEB01' $_.Exception.Message}
    }
    'Backup' {
      if(-not(Rodando 'VM-BKP01')){Pend 'BKP00' 'BKP01 ativo' 'Ligue BKP01 e mantenha FILE01 Off para nao pressionar RAM.';break}
      try{
        $r=Convidado 'VM-BKP01' {
          $sh=Get-SmbShare -Name 'SF_Repositorio$' -ErrorAction SilentlyContinue
          $root='B:\Repositorio'
          $snap=@(Get-ChildItem -Path (Join-Path $root 'FILE01\Full') -Directory -ErrorAction SilentlyContinue)
          $rests=@(Get-ChildItem -Path (Join-Path $root 'Restauracoes_TESTE') -Directory -ErrorAction SilentlyContinue)
          $sys=@(Get-ChildItem -Path (Join-Path $root 'DC01\SystemState') -Directory -ErrorAction SilentlyContinue)
          $vol=Get-Volume -DriveLetter B -ErrorAction SilentlyContinue
          [pscustomobject]@{Repo=(Test-Path $root);Ntfs=($vol.FileSystem -eq 'NTFS');
            Share=[bool]$sh;Encrypted=[bool]$sh.EncryptData;
            Snapshots=$snap.Count;Restauracoes=$rests.Count;SystemStates=$sys.Count}
        }
        Check 'BKP01' 'Repositorio B:\Repositorio e NTFS' ($r.Repo -and $r.Ntfs)
        Check 'BKP02' 'Compartilhamento backup criptografado' ($r.Share -and $r.Encrypted)
        Check 'BKP03' 'Ao menos um snapshot FILE01' ($r.Snapshots -ge 1) '' ('Snapshots='+$r.Snapshots)
        Check 'BKP04' 'Ao menos uma restauracao teste' ($r.Restauracoes -ge 1) '' ('Pastas='+$r.Restauracoes)
        Pend 'BKP05' 'Hash SHA256 do teste T28' 'Comparar origens e restauracao, documentar ambas as hashes sem revelar dados privados.'
        Check 'BKP06' 'Arquivo SystemState DC01 catalogado' ($r.SystemStates -ge 1) '' ('Pastas='+$r.SystemStates)
        Pend 'BKP07' 'Restore real System State' 'Nao executar no unico DC01. Cópia de backup != restore.'
      }catch{Pend 'BKP00' 'PowerShell Direct BKP01' $_.Exception.Message}
    }
    'Cliente' {
      if(-not(Rodando 'CLI-ADM01')){Pend 'CLI00' 'Cliente ADM online' 'Ligue CLI-ADM01 e FW01/DC01.';break}
      try{
        $r=Convidado 'CLI-ADM01' {
          $ipv=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                 Where-Object {$_.IPAddress -like '10.20.*' -and $_.AddressState -eq 'Preferred'}) | Select-Object -First 1
          $ip=$null;$orig='';if($ipv){$ip=$ipv.IPAddress;$orig=[string]$ipv.PrefixOrigin}
          $dns=@(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            ForEach-Object {$_.ServerAddresses})
          $channel=$false;try{$channel=[bool](Test-ComputerSecureChannel -ErrorAction Stop)}catch{}
          $srv=$false;try{$srv=[bool](Resolve-DnsName -Name '_ldap._tcp.dc._msdcs.smartfactory.corp' -Type SRV -Server '10.20.20.11' -ErrorAction Stop)}catch{}
          $gp=(& gpresult.exe /r /scope computer 2>&1 | Out-String)
          $laps=@(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-LAPS/Operational';Id=10018;StartTime=(Get-Date).AddDays(-30)} -MaxEvents 1 -ErrorAction SilentlyContinue)
          $pslog=@(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-PowerShell/Operational';Id=4104;StartTime=(Get-Date).AddDays(-7)} -MaxEvents 1 -ErrorAction SilentlyContinue)
          $w=Get-Service -Name WazuhSvc -ErrorAction SilentlyContinue
          [pscustomobject]@{IP=$ip;Origin=$orig;DNS=$dns;Channel=$channel;SRV=$srv;
           GpoBaseline=($gp -match 'SF-Endpoint-Baseline');GpoLaps=($gp -match 'SF-LAPS-Workstations');
           LapsEvent=($laps.Count -gt 0);PowerShellEvent=($pslog.Count -gt 0);
           Agent=([bool]$w);AgentState=([string]$w.Status)}
        }
        $is30=($r.IP -match '^10\.20\.30\.(2[1-9]|[3-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-4])$')
        Check 'CLI01' 'DHCP VLAN30 pool .21-.254' ($is30 -and $r.Origin -eq 'Dhcp') '' ('IPv4='+$r.IP)
        Check 'CLI02' 'DNS corporativo entregue' ($r.DNS -contains '10.20.20.11')
        Check 'CLI03' 'Canal seguro dominio' $r.Channel
        Check 'CLI04' 'SRV do dominio resolvido' $r.SRV
        Check 'CLI05' 'GPO Baseline e LAPS no gpresult' ($r.GpoBaseline -and $r.GpoLaps)
        Check 'CLI06' 'Evento LAPS 10018 presente ultimos 30 dias' $r.LapsEvent
        Check 'CLI07' 'Evento PowerShell 4104 presente ultimos 7 dias' $r.PowerShellEvent
        Check 'CLI08' 'Wazuh Agent instalado e em execucao' ($r.Agent -and $r.AgentState -eq 'Running')
        Pend 'CLI09' 'T14 acesso LAPS negado usuario comum' 'Logar como SMARTFACTORY\\lab.adm01, consultar sem imprimir senha, guardar Access Denied.'
      }catch{Pend 'CLI00' 'PowerShell Direct CLI-ADM01' $_.Exception.Message}
    }
    'PAW' {
      if(-not(Rodando 'PAW-TI01')){Pend 'PAW00' 'PAW-TI01 online' 'Ligue PAW e FW01/DC01.';break}
      try{
        $r=Convidado 'PAW-TI01' {
          $ip=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object {$_.IPAddress -eq '10.20.90.10'}) | Select-Object -First 1
          $channel=$false;try{$channel=Test-ComputerSecureChannel -ErrorAction Stop}catch{}
          $fw=@(Get-NetFirewallProfile | Where-Object Enabled -ne 'True')
          $rdp=(Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction SilentlyContinue).fDenyTSConnections
          $wsman=$false;try{$wsman=[bool](Test-WSMan -ComputerName '10.20.20.11' -ErrorAction Stop)}catch{}
          $tcp=$false;try{$tcp=[bool](Test-NetConnection -ComputerName '10.20.20.11' -Port 5985 -WarningAction SilentlyContinue).TcpTestSucceeded}catch{}
          [pscustomobject]@{IP=[bool]$ip;Prefix=$ip.PrefixLength;Static=($ip.PrefixOrigin -ne 'Dhcp');
            Domain=$channel;FWOn=($fw.Count -eq 0);RDPoff=($rdp -eq 1);WSMAN=$wsman;TCP5985=$tcp}
        }
        Check 'PAW01' 'IP 10.20.90.10/24 estatico' ($r.IP -and $r.Static -and $r.Prefix -eq 24)
        Check 'PAW02' 'Secure channel AD' $r.Domain
        Check 'PAW03' 'Firewall local ativo' $r.FWOn
        Check 'PAW04' 'RDP recebido desabilitado na PAW' $r.RDPoff
        Check 'PAW05' 'PAW -> DC01 WinRM 5985' $r.TCP5985 '' ('Test-WSMan='+$r.WSMAN)
        Pend 'PAW06' 'RDP real WEB/BKP e SSH Wazuh' 'Exige combinar VMs e, para NLA, autenticacao do dominio; verificar limitação RAM.'
      }catch{Pend 'PAW00' 'PowerShell Direct PAW-TI01' $_.Exception.Message}
    }
    'WazuhPreparar' {
      Import-Module Hyper-V -ErrorAction Stop
      if(-not(Test-Path -LiteralPath $BashLocal)){
        [System.IO.File]::WriteAllText($BashLocal, $WAZUH_BASH,
          ([System.Text.UTF8Encoding]::new($false)))
      }
      $drive=$null
      try{
        $drive=MontarSF $false
        Copy-Item -LiteralPath $BashLocal -Destination (Join-Path $drive $BashName) -Force
        Check 'WZ00' 'Bash de auditoria colocado na SFSETUP' (Test-Path -LiteralPath (Join-Path $drive $BashName))
      }finally{if($drive){DesmontarSF}}
      Nota 'Agora inicie SOMENTE FW01 + WAZUH01, execute Bash via console e desligue normalmente para coletar.'
    }
    'WazuhColetar' {
      Import-Module Hyper-V -ErrorAction Stop
      $drive=$null
      try{
        $drive=MontarSF $true
        $src=Join-Path $drive 'AUDITORIA_WAZUH_FINAL.txt'
        if(-not(Test-Path -LiteralPath $src)){Pend 'WZ01' 'Relatorio Wazuh na SFSETUP' 'Execute Bash e copie arquivo antes de desligar Ubuntu.'}
        else{
          $dst=Join-Path $Logs '15-AUDITORIA_WAZUH_FINAL.txt'
          Copy-Item -LiteralPath $src -Destination $dst -Force
          Check 'WZ01' 'Relatorio Linux de auditoria coletado' (Test-Path -LiteralPath $dst) $dst
          Nota 'Saida Wazuh e local; verificacao humana e painel ainda necessarios. Sem segredo no log.'
        }
      }finally{if($drive){DesmontarSF}}
    }
    'VisitantesAtivar' {
      Import-Module Hyper-V -ErrorAction Stop
      $vm='CLI-ADM01';$marker=Join-Path $Docs 'VLAN_TEMPORARIA_VISITANTES.txt'
      if((Get-VM -Name $vm).State -ne 'Off'){throw 'Desligue CLI-ADM01 normalmente antes da mudanca de VLAN.'}
      if(Test-Path -LiteralPath $marker){throw 'Ja existe marcacao de VLAN temporaria. Primeiro restaure/avalie estado.'}
      $nic=@(Get-VMNetworkAdapter -VMName $vm | Where-Object SwitchName -eq 'SF-LAN') | Select-Object -First 1
      if(-not $nic){throw 'NIC SF-LAN nao encontrada em CLI-ADM01.'}
      $v=Get-VMNetworkAdapterVlan -VMName $vm -VMNetworkAdapterName $nic.Name
      if($v.OperationMode -ne 'Access' -or $v.AccessVlanId -ne 30){throw 'CLI nao esta na Access VLAN30; alteracao cancelada.'}
      $s=Read-Host 'MUDANCA TEMPORARIA para VLAN999. Digite VISITANTES999'
      if($s -ne 'VISITANTES999'){throw 'Cancelado.'}
      Set-VMNetworkAdapterVlan -VMName $vm -VMNetworkAdapterName $nic.Name -Access -VlanId 999 -ErrorAction Stop
      ('VM={0};NIC={1};ANTIGA=30;NOVA=999;DATA={2}' -f $vm,$nic.Name,(Get-Date -Format 's')) |
        Set-Content -LiteralPath $marker -Encoding UTF8
      Nota 'CLI em VLAN999. Ligue FW01+DC01+CLI. Valide IP 10.20.200.10-254, bloqueio de rede privada e DNS publico. Depois desligue a CLI e execute VisitantesRestaurar.'
    }
    'VisitantesRestaurar' {
      Import-Module Hyper-V -ErrorAction Stop
      $marker=Join-Path $Docs 'VLAN_TEMPORARIA_VISITANTES.txt'
      if((Get-VM -Name 'CLI-ADM01').State -ne 'Off'){throw 'Desligue CLI-ADM01 antes de restaurar VLAN30.'}
      $nic=@(Get-VMNetworkAdapter -VMName 'CLI-ADM01' | Where-Object SwitchName -eq 'SF-LAN')|Select-Object -First 1
      $v=Get-VMNetworkAdapterVlan -VMName 'CLI-ADM01' -VMNetworkAdapterName $nic.Name
      if($v.AccessVlanId -ne 999){throw 'CLI nao esta na VLAN999. Nao alterar automaticamente.'}
      if(-not(Test-Path -LiteralPath $marker)){throw 'Marcador de troca ausente. Revisao manual necessaria.'}
      $s=Read-Host 'Restaurar CLI-ADM01 Access VLAN30? Digite RESTAURAR30'
      if($s -ne 'RESTAURAR30'){throw 'Cancelado.'}
      Set-VMNetworkAdapterVlan -VMName 'CLI-ADM01' -VMNetworkAdapterName $nic.Name -Access -VlanId 30 -ErrorAction Stop
      Rename-Item -LiteralPath $marker -NewName ('VLAN_VISITANTES_RESTAURADA_{0}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
      Check 'RE10' 'VLAN original CLI restaurada para 30' ((Get-VMNetworkAdapterVlan -VMName 'CLI-ADM01' -VMNetworkAdapterName $nic.Name).AccessVlanId -eq 30)
    }
    'Registrar' {
      PrecisaPreparar
      if($Teste -notmatch '^(T(0[1-9]|[12][0-9]|30)|C(0[1-9]|[1-3][0-9]|40))$'){throw 'Informe -Teste T01..T30 ou C01..C40.'}
      $matrizEscolhida=if($Teste -like 'T*'){$CsvStatus}else{$CsvCP}
      $rows=@(Import-Csv -LiteralPath $matrizEscolhida -Encoding UTF8)
      $selected=@($rows | Where-Object ID -eq $Teste)
      if($selected.Count -ne 1){throw 'Teste nao localizado ou duplicado na matriz.'}
      if($Status -in @('VALIDADO','VALIDADO_ADAPTADO')){
        if([string]::IsNullOrWhiteSpace($Evidencia) -or -not (Test-Path -LiteralPath $Evidencia)){
          throw 'Para VALIDADO/VALIDADO_ADAPTADO, informe -Evidencia com caminho de arquivo existente (PNG/TXT/PDF).'
        }
      }
      $selected[0].Status=$Status;$selected[0].Evidencia=$Evidencia
      $selected[0].Observacao=$Observacao;$selected[0].Atualizado=(Get-Date).ToString('s')
      $rows | Export-Csv -LiteralPath $matrizEscolhida -NoTypeInformation -Encoding UTF8
      Nota ("{0} registrado como {1}. Evidencia={2}" -f $Teste,$Status,$Evidencia)
    }
    'Consolidar' {
      PrecisaPreparar
      $rows=@(Import-Csv -LiteralPath $CsvStatus -Encoding UTF8)
      $cprows=@(Import-Csv -LiteralPath $CsvCP -Encoding UTF8)
      $checks=if(Test-Path -LiteralPath $CsvChecks){@(Import-Csv -LiteralPath $CsvChecks -Encoding UTF8)}else{@()}
      $now=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
      $report=Join-Path $Docs 'RELATORIO-FINAL-RESULTADOS.md'
      $text=@()
      $text+='# SmartFactory-GS - Relatorio final de testes'
      $text+="Gerado em $now. Estados declarados apenas quando evidenciados."
      $text+=''
      $text+='## Situacao dos 30 testes CP03'
      foreach($s in @('VALIDADO','VALIDADO_ADAPTADO','FALHOU','LIMITACAO','NAO_APLICAVEL','PENDENTE')){
        $c=@($rows | Where-Object Status -eq $s).Count
        $text+="- $s : $c"
      }
      $text+=''
      $text+='| ID | Estado | Classificacao | Evidencia |'
      $text+='|---|---|---|---|'
      foreach($r in $rows){$text+=('|' + $r.ID+'|'+$r.Status+'|'+$r.Classificacao+'|'+($r.Evidencia -replace '\|','/')+'|')}
      $text+=''
      $text+='## Conformidade complementar CP01/CP02'
      foreach($st in @('VALIDADO','VALIDADO_ADAPTADO','FALHOU','LIMITACAO','NAO_APLICAVEL','PENDENTE')){
        $text+=('- '+$st+': '+@($cprows|Where-Object Status -eq $st).Count)
      }
      foreach($r in $cprows){
        $text+=('- '+$r.ID+' ['+$r.Status+'] '+$r.Controle)
      }
      $text+=''
      $text+='## Verificacoes tecnicas automatizadas'
      $text+=("Total de verificacoes registradas: {0}" -f $checks.Count)
      foreach($s in @('APROVADO','FALHOU','NAO_EXECUTADO')){
        $text+=('- {0}: {1}' -f $s,@($checks | Where-Object Resultado -eq $s).Count)
      }
      $text+=''
      $text+='## Limites declarados'
      $text+='- Nao foi implantado DC02 ou FILE02; nao demonstrar replicacao/DFS failover.'
      $text+='- O repositório do BKP01 nao implementa 3-2-1 fisico completo.'
      $text+='- Wazuh 7,5 GiB e FW01 1,5 GiB em VM estatica, DC01 dinamico.'
      $text+='- Testes Windows->SIEM simultaneos dependem de RAM que pode nao estar disponivel.'
      $text+='- Aprovacao exige prova de efeito, e nao somente configuracao.'
      $text | Set-Content -LiteralPath $report -Encoding UTF8
      Nota "RELATORIO CONSOLIDADO: $report"
    }
  }
}
catch{
  Nota ('ERRO NA FASE '+$Fase+': '+$_.Exception.Message)
  throw
}
finally{SalvarChecks}
