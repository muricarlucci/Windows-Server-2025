#requires -Version 5.1
# SmartFactory-GS | ETAPA 11 | GPOs, Windows LAPS e Piloto de Hardening
# Executar no Windows PowerShell 5.1 do HOST como Administrador.
# ACOES: Preparar -> EstruturarGPOs -> PrepararLAPS -> AplicarPiloto ->
#        ProcessarPiloto -> ValidarPiloto -> [Publicar] -> [AtivarLapsDSRM]
#        ReverterPiloto (apenas se houver falha).
# Uma alteracao do schema AD e permanente. Nenhuma senha LAPS e exibida/salva.
[CmdletBinding()]
param(
    [ValidateSet('Preparar','EstruturarGPOs','PrepararLAPS','AplicarPiloto','ProcessarPiloto',
                 'ValidarPiloto','Publicar','AtivarLapsDSRM','ReverterPiloto')]
    [string]$Acao='Preparar'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Base='D:\FIAP\WINDOWS\SmartFactory-GS'
$NomeDC='VM-DC01'; $NomeCliente='CLI-ADM01'; $Domain='smartfactory.corp'
$DN='DC=smartfactory,DC=corp'
$PilotoOU="OU=Piloto_GPO,$DN"
$OriginalOU="OU=Computadores,OU=Administracao,OU=SmartFactory,$DN"
$GruposOU="OU=Grupos,OU=TI,OU=SmartFactory,$DN"
$Log=Join-Path $Base '09-Logs-Testes\13-GPO-LAPS-Piloto-Resultado.txt'
$Relatorio=Join-Path $Base '00-Documentacao\11-GPO-LAPS-Hardening.md'
$Checklist=Join-Path $Base '00-Documentacao\11-GPO-LAPS-Checklist.txt'
$Roteiro=Join-Path $Base '07-Video\Roteiros\Roteiro_Video_Etapa_12.txt'
$Evid=Join-Path $Base '06-Evidencias\11-GPO-LAPS-Hardening'
$PastaBackup=Join-Path $Base '04-Configuracoes\GPOs\Etapa11'
$MarcaPiloto=Join-Path $Base '09-Logs-Testes\13-Piloto-LAPS-APROVADO.txt'
$MarcaPos=Join-Path $Base '09-Logs-Testes\13-Piloto-OU-Original.txt'
$GPOs=@('SF-Domain-Account-Policy','SF-DC-Hardening','SF-MemberServer-Baseline',
        'SF-DMZ-Web-Hardening','SF-Endpoint-Baseline','SF-Audit-Telemetry',
        'SF-LAPS-Workstations','SF-LAPS-Servers','SF-LAPS-DC-DSRM','SF-Firewall-RemoteAdmin')

function Logar([string]$Texto) {
    $linha=(' {0} | {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Texto)
    Add-Content -LiteralPath $Log -Value $linha -Encoding UTF8
    Write-Host $linha
}
function ChecarHost {
    if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'Utilize Windows PowerShell 5.1 no host.' }
    $who=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $who.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Abra PowerShell como Administrador no HOST.'
    }
    if (-not (Test-Path -LiteralPath $Base -PathType Container)) {
        throw "Projeto inexistente: $Base"
    }
    Import-Module Hyper-V -ErrorAction Stop
    foreach($dir in @((Split-Path $Log),(Split-Path $Relatorio),(Split-Path $Checklist),
                      (Split-Path $Roteiro),$Evid,$PastaBackup)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }
}
function ChecarVMs([bool]$ClienteLigado) {
    foreach($nome in @('VM-FW01',$NomeDC)) {
        $vm=Get-VM -Name $nome -ErrorAction Stop
        if ($vm.State -ne 'Running') { throw "$nome precisa estar Running; encontrado: $($vm.State)" }
    }
    $cli=Get-VM -Name $NomeCliente -ErrorAction Stop
    if ($ClienteLigado -and $cli.State -ne 'Running') {
        throw "$NomeCliente precisa estar Running para executar/validar GPO e LAPS."
    }
    if (-not $ClienteLigado -and $cli.State -ne 'Off') {
        throw "$NomeCliente pode ficar desligada nesta operacao. Desligue normalmente para liberar RAM."
    }
    foreach($nome in @('VM-FILE01','VM-WEB01','VM-BKP01','PAW-TI01','VM-WAZUH01')) {
        $vm=Get-VM -Name $nome -ErrorAction SilentlyContinue
        if ($vm -and $vm.State -ne 'Off') {
            throw "Economia de RAM: desligue normalmente $nome e aguarde Off."
        }
    }
}
function CredencialDC { Get-Credential -Message "Credencial administrativa do $NomeDC (SMARTFACTORY\Administrator, sem salvar a senha)" }
function DC([scriptblock]$Bloco,[object[]]$Argumentos=@()) {
    $cred=CredencialDC
    Invoke-Command -VMName $NomeDC -Credential $cred -ScriptBlock $Bloco -ArgumentList $Argumentos -ErrorAction Stop
}
function CriarArquivos {
    if (-not (Test-Path -LiteralPath $Relatorio)) {
@'
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
'@ | Set-Content -LiteralPath $Relatorio -Encoding UTF8
    }
    if (-not (Test-Path -LiteralPath $Checklist)) {
@'
ETAPA 11 | GPOs, Windows LAPS e Hardening
[ ] Preparar: RAM, FW01/DC01, WAZUH OFF; arquivos gerados.
[ ] EstruturarGPOs: backup GPO, Central Store, dez GPOs criadas e valores revisados.
[ ] PrepararLAPS: backup AD confirmado, schema atualizado se necessario, grupos/ACL.
[ ] AplicarPiloto: CLI-ADM01 movida para Piloto_GPO e tres GPOs linkadas.
[ ] ProcessarPiloto: gpupdate + Invoke-LapsPolicyProcessing, sem erros.
[ ] ValidarPiloto: evento 10018, atributo criptografado, GPOs e grupos conferidos.
[ ] Publicar (APOS HOMOLOGACAO): links endpoint e servidor, OU original restaurada.
[ ] DSRM (OPCIONAL e controlado): backup de DC validado, link DC habilitado.
[ ] Evidencias e video 12.
'@ | Set-Content -LiteralPath $Checklist -Encoding UTF8
    }
    if (Test-Path -LiteralPath $Roteiro) { Copy-Item $Roteiro "$Roteiro.bak" -Force }
@'
Nesta etapa configuramos a camada de politicas de seguranca e gerenciamento de senhas da SmartFactory. Como as maquinas compartilham apenas dezesseis gigabytes fisicos, deixamos o Wazuh e todos os servidores membros desligados, mantendo o firewall e o controlador de dominio. A estacao CLI-ADM01 so foi ligada para testar a aplicacao das politicas. Preservamos a memoria dinamica do DC01 e os ajustes de RAM da FW01 e do Wazuh.

Primeiro, executamos o script de preparacao, que conferiu os estados das VMs e criou automaticamente a documentacao, os logs e as pastas de evidencias. Em seguida, utilizando PowerShell Direct, acessamos o controlador de dominio e verificamos sua estrutura, os niveis funcionais e a politica de senhas ja existente.

A automacao instalou as ferramentas de gerenciamento de GPO quando necessario, preservou um backup das politicas existentes e preparou o Central Store dos modelos administrativos, sem sobrescrever um repositorio ja existente. Depois criou GPOs separadas para controladores de dominio, servidores membros, servidores web, estacoes, auditoria, administracao remota e Windows LAPS. Essa separacao evita colocar todas as configuracoes em uma politica monolitica e facilita auditoria e reversao.

A etapa seguinte preparou o Windows LAPS. Verificamos se o esquema do Active Directory precisava da extensao do LAPS e, mediante confirmacao de backup, aplicamos a atualizacao quando necessaria. Criamos grupos distintos para consultar e solicitar a rotacao das senhas e concedemos permissoes especificas a OU piloto. A politica configura armazenamento criptografado no AD, senha de vinte e quatro caracteres, rotacao a cada quatorze dias e gerenciamento automatico da conta local WLapsAdmin.

Para nao impactar de imediato todas as maquinas, movemos temporariamente a estacao de Administracao para a OU Piloto_GPO. Aplicamos ali as politicas de baseline, auditoria PowerShell e LAPS; em seguida forcamos o processamento de politica na estacao. A verificacao consulta gpresult, os eventos operacionais do LAPS e a existencia da senha criptografada no Active Directory, sem revelar credenciais.

Por fim, registramos o resultado da homologacao. A publicacao para as demais OUs e o LAPS da senha DSRM do DC sao operacoes controladas, realizadas somente com aprovacao e backup. Assim demonstramos politicas funcionais com menor privilegio e uma estrategia de rollout que permite interromper ou reverter alteracoes sem comprometer todo o dominio.
'@ | Set-Content -LiteralPath $Roteiro -Encoding UTF8
}

ChecarHost
switch($Acao) {
    'Preparar' {
        ChecarVMs $false
        CriarArquivos
        foreach($n in @('VM-FW01','VM-DC01','VM-WAZUH01','CLI-ADM01')) {
            $vm=Get-VM -Name $n -ErrorAction SilentlyContinue
            if ($vm) {
                Logar ("VM={0}; state={1}; assignedMiB={2:N0}; startupMiB={3:N0}; dynamic={4}" -f
                    $n,$vm.State,($vm.MemoryAssigned/1MB),($vm.MemoryStartup/1MB),$vm.DynamicMemoryEnabled)
            }
        }
        Logar 'Preparacao concluida; nenhum ajuste de memoria ou GPO aplicado.'
    }
    'EstruturarGPOs' {
        ChecarVMs $false
        $res=DC {
            param($domain,$baseDN)
            $names=@('SF-Domain-Account-Policy','SF-DC-Hardening','SF-MemberServer-Baseline',
                'SF-DMZ-Web-Hardening','SF-Endpoint-Baseline','SF-Audit-Telemetry',
                'SF-LAPS-Workstations','SF-LAPS-Servers','SF-LAPS-DC-DSRM','SF-Firewall-RemoteAdmin')
            $ErrorActionPreference='Stop' 
            Import-Module ActiveDirectory -ErrorAction Stop
            if (-not (Get-Module -ListAvailable GroupPolicy)) {
                Install-WindowsFeature GPMC -ErrorAction Stop | Out-Null
            }
            Import-Module GroupPolicy -ErrorAction Stop
            if ((Get-ADDomain).DNSRoot -ne $domain) { throw 'Dominio inesperado; cancelar.' }
            $piloto="OU=Piloto_GPO,$baseDN"
            if (-not (Get-ADOrganizationalUnit -Identity $piloto -ErrorAction SilentlyContinue)) {
                New-ADOrganizationalUnit -Name 'Piloto_GPO' -Path $baseDN -ProtectedFromAccidentalDeletion $true | Out-Null
            }
            $conta=Get-ADDefaultDomainPasswordPolicy
            $antes=Join-Path 'C:\SF-Automacao\GPO-Backups' (Get-Date -Format 'yyyyMMdd-HHmmss')
            New-Item -ItemType Directory -Path $antes -Force | Out-Null
            Backup-GPO -All -Path $antes -ErrorAction Stop | Out-Null
            # Central Store: nao sobrescreve modelos de uma instalacao existente
            $store="\\$domain\SYSVOL\$domain\Policies\PolicyDefinitions"
            $cs='EXISTENTE'
            if (-not (Test-Path -LiteralPath $store)) {
                $templates=@(Get-ChildItem -Path 'C:\Windows\PolicyDefinitions\*.admx' -ErrorAction SilentlyContinue)
                if ($templates.Count -gt 0) {
                    New-Item -ItemType Directory -Path $store -Force | Out-Null
                    Copy-Item 'C:\Windows\PolicyDefinitions\*.admx' -Destination $store -Force -ErrorAction Stop
                    foreach($lang in @('en-US','pt-BR')) {
                        $src="C:\Windows\PolicyDefinitions\$lang"
                        if (Test-Path $src) {
                            New-Item -Path (Join-Path $store $lang) -ItemType Directory -Force | Out-Null
                            Copy-Item (Join-Path $src '*.adml') (Join-Path $store $lang) -Force -ErrorAction Stop
                        }
                    }
                    $cs='CRIADO'
                } else {
                    $cs='PENDENTE: fontes ADMX ausentes no DC Core, RSAT/ADMX necessario'
                }
            }
            foreach($n in $names) {
                if (-not (Get-GPO -Name $n -ErrorAction SilentlyContinue)) {
                    New-GPO -Name $n -Comment 'SmartFactory-GS | GPO modular | Etapa 11' -ErrorAction Stop | Out-Null
                }
            }
            function GPVal($g,$key,$v,$value,[string]$type='DWord') {
                Set-GPRegistryValue -Name $g -Key $key -ValueName $v -Type $type -Value $value -ErrorAction Stop | Out-Null
            }
            $powershell='HKLM\Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
            $dnsclient='HKLM\Software\Policies\Microsoft\Windows NT\DNSClient'
            $autoplay='HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
            GPVal 'SF-Endpoint-Baseline' $dnsclient 'EnableMulticast' 0
            GPVal 'SF-Endpoint-Baseline' $autoplay 'NoDriveTypeAutoRun' 255
            GPVal 'SF-Endpoint-Baseline' 'HKLM\System\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 1
            GPVal 'SF-Endpoint-Baseline' $powershell 'EnableScriptBlockLogging' 1
            GPVal 'SF-Audit-Telemetry' $powershell 'EnableScriptBlockLogging' 1
            GPVal 'SF-MemberServer-Baseline' $powershell 'EnableScriptBlockLogging' 1
            GPVal 'SF-MemberServer-Baseline' 'HKLM\System\CurrentControlSet\Services\LanmanServer\Parameters' 'SMB1' 0
            GPVal 'SF-DMZ-Web-Hardening' $powershell 'EnableScriptBlockLogging' 1
            GPVal 'SF-DMZ-Web-Hardening' $dnsclient 'EnableMulticast' 0
            GPVal 'SF-DC-Hardening' 'HKLM\System\CurrentControlSet\Services\NTDS\Parameters' 'LDAPServerIntegrity' 2
            GPVal 'SF-DC-Hardening' 'HKLM\System\CurrentControlSet\Services\NTDS\Parameters' 'LdapEnforceChannelBinding' 1
            # Firewall remote admin: GPO preparada mas NAO linkada nesta etapa
            Import-Module NetSecurity -ErrorAction Stop
            $policy="$domain\SF-Firewall-RemoteAdmin"
            $f=Get-NetFirewallRule -PolicyStore $policy -Name 'SF-PAW-WinRM-5985' -ErrorAction SilentlyContinue
            if (-not $f) {
                New-NetFirewallRule -PolicyStore $policy -Name 'SF-PAW-WinRM-5985' `
                    -DisplayName 'SmartFactory PAW WinRM 5985' -Direction Inbound `
                    -Protocol TCP -LocalPort 5985 -RemoteAddress '10.20.90.10' `
                    -Action Allow -Profile Domain -Enabled True | Out-Null
            }
            "DOMAIN=$domain;POLICY_BACKUP=$antes;CENTRAL_STORE=$cs;GPO_COUNT=$($names.Count);ACCOUNT_POLICY=minimum:$($conta.MinPasswordLength),history:$($conta.PasswordHistoryCount),lockout:$($conta.LockoutThreshold)"
        } @($Domain,$DN)
        foreach($linha in $res) { Logar ([string]$linha) }
        # Copia o backup do DC01 ao host pela sessao PowerShell Direct, SEM abrir SMB.
        $linhaBackup=@($res | Where-Object { $_ -like '*POLICY_BACKUP=*' } | Select-Object -First 1)
        if ($linhaBackup.Count -gt 0) {
            $origem=([regex]::Match([string]$linhaBackup[0],'POLICY_BACKUP=([^;]+)')).Groups[1].Value
            if ($origem) {
                $sessao=$null
                try {
                    $sessao=New-PSSession -VMName $NomeDC -Credential (CredencialDC) -ErrorAction Stop
                    Copy-Item -FromSession $sessao -Path $origem -Destination $PastaBackup -Recurse -Force -ErrorAction Stop
                    Logar 'Backup das GPOs copiado ao projeto via PowerShell Direct.'
                } catch {
                    Logar ('AVISO: copia do backup ao host nao concluida; original preservado no DC01: '+$origem)
                } finally {
                    if ($sessao) { Remove-PSSession $sessao }
                }
            }
        }
        Add-Content $Relatorio "`n- EstruturarGPOs executado: $((Get-Date).ToString('s'))." -Encoding UTF8
        Logar 'GPOs estruturadas. Nenhuma GPO de hardening de servidores aplicada ao dominio.'
    }
    'PrepararLAPS' {
        ChecarVMs $false
        $c=Read-Host 'ATENCAO: esquema AD permanente. Confirme backup valido do DC01 digitando CONFIRMO-BACKUP-DC01'
        if ($c -ne 'CONFIRMO-BACKUP-DC01') { throw 'Sem confirmacao de backup, esquema nao alterado.' }
        $res=DC {
            param($baseDN,$pilotDN,$groupOU)
            $ErrorActionPreference='Stop'
            Import-Module ActiveDirectory -ErrorAction Stop
            Import-Module LAPS -ErrorAction Stop
            Import-Module GroupPolicy -ErrorAction Stop
            $schema=(Get-ADRootDSE).schemaNamingContext
            $exists=Get-ADObject -SearchBase $schema -LDAPFilter '(lDAPDisplayName=msLAPS-EncryptedPassword)' -ErrorAction Stop
            $schemaStatus='PRESENTE'
            if (-not $exists) {
                Update-LapsADSchema -ErrorAction Stop | Out-Null
                $schemaStatus='ATUALIZADO'
            }
            $groups=@('GG_LAPS_Password_Readers','GG_LAPS_Password_Resetters')
            foreach($g in $groups) {
                if (-not (Get-ADGroup -Identity $g -ErrorAction SilentlyContinue)) {
                    New-ADGroup -Name $g -SamAccountName $g -Path $groupOU `
                        -GroupScope Global -GroupCategory Security -ErrorAction Stop | Out-Null
                }
            }
            $reader='SMARTFACTORY\GG_LAPS_Password_Readers'
            $reset='SMARTFACTORY\GG_LAPS_Password_Resetters'
            foreach($ou in @($pilotDN)) {
                Set-LapsADComputerSelfPermission -Identity $ou -ErrorAction Stop | Out-Null
                Set-LapsADReadPasswordPermission -Identity $ou -AllowedPrincipals @($reader) -ErrorAction Stop | Out-Null
                Set-LapsADResetPasswordPermission -Identity $ou -AllowedPrincipals @($reset) -ErrorAction Stop | Out-Null
            }
            # Conceder leitura a adm.lab (conta nominal restrita a PAW) se existir
            $adm=Get-ADUser -Identity 'adm.lab' -ErrorAction SilentlyContinue
            if ($adm) {
                $members=@(Get-ADGroupMember -Identity 'GG_LAPS_Password_Readers' -ErrorAction Stop |
                    Select-Object -ExpandProperty DistinguishedName)
                if ($members -notcontains $adm.DistinguishedName) {
                    Add-ADGroupMember -Identity 'GG_LAPS_Password_Readers' -Members $adm -ErrorAction Stop
                }
            }
            $root='HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\LAPS'
            foreach($gpo in @('SF-LAPS-Workstations','SF-LAPS-Servers')) {
                $settings=[ordered]@{
                    BackupDirectory=2;PasswordAgeDays=14;PasswordLength=24;PasswordComplexity=5;
                    ADPasswordEncryptionEnabled=1;PasswordExpirationProtectionEnabled=1;
                    PostAuthenticationResetDelay=1;PostAuthenticationActions=3;
                    AutomaticAccountManagementEnabled=1;AutomaticAccountManagementTarget=1;
                    AutomaticAccountManagementEnableAccount=1;AutomaticAccountManagementRandomizeName=0
                }
                foreach($p in $settings.GetEnumerator()) {
                    Set-GPRegistryValue -Name $gpo -Key $root -ValueName $p.Key `
                        -Type DWord -Value $p.Value -ErrorAction Stop | Out-Null
                }
                Set-GPRegistryValue -Name $gpo -Key $root -ValueName 'ADPasswordEncryptionPrincipal' `
                    -Type String -Value $reader -ErrorAction Stop | Out-Null
                Set-GPRegistryValue -Name $gpo -Key $root -ValueName 'AutomaticAccountManagementNameOrPrefix' `
                    -Type String -Value 'WLapsAdmin' -ErrorAction Stop | Out-Null
            }
            # DC: somente conta DSRM; politica nao sera linkada sem confirmacao separada.
            foreach($p in @{BackupDirectory=2;ADPasswordEncryptionEnabled=1;ADBackupDSRMPassword=1}.GetEnumerator()) {
                Set-GPRegistryValue -Name 'SF-LAPS-DC-DSRM' -Key $root -ValueName $p.Key `
                    -Type DWord -Value $p.Value -ErrorAction Stop | Out-Null
            }
            $rights=Find-LapsADExtendedRights -Identity $pilotDN
            "LAPS_SCHEMA=$schemaStatus;LAPS_GROUPS=$($groups -join ',');PILOT_RIGHT_HOLDERS=$($rights.ExtendedRightHolders -join ',')"
        } @($DN,$PilotoOU,$GruposOU)
        foreach($linha in $res) { Logar ([string]$linha) }
        Add-Content $Relatorio "`n- PrepararLAPS: schema e permissoes configuradas, $(Get-Date -Format 's')." -Encoding UTF8
    }
    'AplicarPiloto' {
        ChecarVMs $true
        if (Test-Path $MarcaPos) { throw "Existe marca de piloto anterior: $MarcaPos. Examine antes de repetir." }
        $res=DC {
            param($pilotDN,$defaultOU,$user)
            $ErrorActionPreference='Stop'
            Import-Module ActiveDirectory; Import-Module GroupPolicy
            $comp=Get-ADComputer -Identity $user -ErrorAction Stop
            $current=$comp.DistinguishedName
            if ($current -notlike "*,$defaultOU") {
                throw "CLI-ADM01 fora da OU esperada: $current"
            }
            Move-ADObject -Identity $current -TargetPath $pilotDN -ErrorAction Stop
            foreach($g in @('SF-Endpoint-Baseline','SF-Audit-Telemetry','SF-LAPS-Workstations')) {
                $links=(Get-GPInheritance -Target $pilotDN).GpoLinks
                if (-not ($links | Where-Object { $_.DisplayName -eq $g })) {
                    New-GPLink -Name $g -Target $pilotDN -LinkEnabled Yes -ErrorAction Stop | Out-Null
                }
            }
            'PILOTO_MOVED_AND_LINKED'
        } @($PilotoOU,$OriginalOU,$NomeCliente)
        $res | ForEach-Object { Logar ([string]$_) }
        Set-Content -LiteralPath $MarcaPos -Value $OriginalOU -Encoding UTF8
        Logar 'CLI-ADM01 movida para Piloto_GPO; executar ProcessarPiloto.'
    }
    'ProcessarPiloto' {
        ChecarVMs $true
        $cred=Get-Credential -Message 'Credencial administrativa da CLI-ADM01 (SMARTFACTORY\Administrator, sem usar lab.adm01)'
        $res=Invoke-Command -VMName $NomeCliente -Credential $cred -ScriptBlock {
            $ErrorActionPreference='Stop'
            if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain -ne $true) {
                throw 'CLI-ADM01 fora do dominio.'
            }
            & gpupdate.exe /target:computer /force | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "gpupdate falhou: $LASTEXITCODE" }
            Import-Module LAPS -ErrorAction Stop
            Invoke-LapsPolicyProcessing -ErrorAction Stop | Out-Null
            Start-Sleep -Seconds 8
            $reg='HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\LAPS'
            $v=Get-ItemProperty -Path $reg -ErrorAction Stop
            $ev=Get-WinEvent -FilterHashtable @{
                LogName='Microsoft-Windows-LAPS/Operational'; Id=10018; StartTime=(Get-Date).AddHours(-4)
            } -MaxEvents 1 -ErrorAction SilentlyContinue
            $gp=gpresult.exe /scope computer /r | Out-String
            "LAPS_BACKUP_DIRECTORY=$($v.BackupDirectory);AUTOMATIC_ACCOUNT=$($v.AutomaticAccountManagementEnabled);EVENT_10018=$([bool]$ev);GPO_LAPS_IN_REPORT=$($gp -match 'SF-LAPS-Workstations');GPO_BASELINE_IN_REPORT=$($gp -match 'SF-Endpoint-Baseline')"
        } -ErrorAction Stop
        $res | ForEach-Object { Logar ([string]$_) }
        Logar 'Processamento do piloto executado; validar a evidencia no AD.'
    }
    'ValidarPiloto' {
        ChecarVMs $true
        if (-not (Test-Path $MarcaPos)) { throw 'Piloto nao iniciado pelo script.' }
        $r=DC {
            param($pilotDN,$compName)
            $ErrorActionPreference='Stop'
            Import-Module ActiveDirectory -ErrorAction Stop
            Import-Module LAPS -ErrorAction Stop
            Import-Module GroupPolicy -ErrorAction Stop
            $comp=Get-ADComputer -Identity $compName -Properties `
                'msLAPS-EncryptedPassword','msLAPS-PasswordExpirationTime' -ErrorAction Stop
            $hasEncrypted=[bool]$comp.'msLAPS-EncryptedPassword'
            $inPilot=$comp.DistinguishedName -like "*,$pilotDN"
            $found=Get-LapsADPassword -Identity $compName -ErrorAction Stop
            $hasRecord=[bool]$found
            $links=(Get-GPInheritance -Target $pilotDN).GpoLinks.DisplayName
            $expected=@('SF-LAPS-Workstations','SF-Endpoint-Baseline','SF-Audit-Telemetry')
            $allLinks=@($expected | Where-Object { $links -notcontains $_ }).Count -eq 0
            "ENCRYPTED_PRESENT=$hasEncrypted;IN_PILOT=$inPilot;LAPS_RECORD=$hasRecord;THREE_GPO_LINKS=$allLinks"
            if (-not ($hasEncrypted -and $inPilot -and $hasRecord -and $allLinks)) {
                throw 'PILOTO REPROVADO: dados LAPS/GPO ausentes.'
            }
        } @($PilotoOU,$NomeCliente)
        $r | ForEach-Object { Logar ([string]$_) }
        'APROVADO. Somente estrutura e atributo criptografado; nenhuma senha exportada.' |
            Set-Content -LiteralPath $MarcaPiloto -Encoding UTF8
        Logar 'PILOTO APROVADO. Publicar e uma acao opcional e explicita.'
        # Exporta relatorio de configuracao GPO (XML sem senhas LAPS).
        try {
            $xml=DC { Import-Module GroupPolicy -ErrorAction Stop; Get-GPOReport -All -ReportType Xml -ErrorAction Stop }
            $destino=Join-Path $PastaBackup 'Relatorio-GPOs-Etapa11.xml'
            [string]$xml | Set-Content -LiteralPath $destino -Encoding UTF8
            Logar ('XML das GPOs exportado: '+$destino)
        } catch {
            Logar ('AVISO: exportacao XML nao concluida: '+$_.Exception.Message)
        }
    }
    'Publicar' {
        ChecarVMs $false
        if (-not (Test-Path -LiteralPath $MarcaPiloto)) {
            throw 'Sem piloto aprovado: nao publicar.'
        }
        $conf=Read-Host 'Para linkar GPOs de producao, digite PUBLICAR-GPOS'
        if ($conf -ne 'PUBLICAR-GPOS') { throw 'Publicacao cancelada.' }
        $r=DC {
            param($baseDN,$pilotDN,$originalDN)
            $ErrorActionPreference='Stop'
            Import-Module ActiveDirectory -ErrorAction Stop
            Import-Module GroupPolicy -ErrorAction Stop
            Import-Module LAPS -ErrorAction Stop
            function Vincular($g,$ou) {
                $links=(Get-GPInheritance -Target $ou).GpoLinks
                if (-not ($links | Where-Object DisplayName -eq $g)) {
                    New-GPLink -Name $g -Target $ou -LinkEnabled Yes -ErrorAction Stop | Out-Null
                }
            }
            foreach($setor in @('Administracao','Recursos_Humanos','Financeiro','Engenharia','Producao','Logistica','TI')) {
                $ou="OU=Computadores,OU=$setor,OU=SmartFactory,$baseDN"
                # Verifica existencia para nao fabricar OU incompatível com o projeto
                Get-ADOrganizationalUnit -Identity $ou -ErrorAction Stop | Out-Null
                Set-LapsADComputerSelfPermission -Identity $ou -ErrorAction Stop | Out-Null
                Set-LapsADReadPasswordPermission -Identity $ou `
                    -AllowedPrincipals @('SMARTFACTORY\GG_LAPS_Password_Readers') -ErrorAction Stop | Out-Null
                Set-LapsADResetPasswordPermission -Identity $ou `
                    -AllowedPrincipals @('SMARTFACTORY\GG_LAPS_Password_Resetters') -ErrorAction Stop | Out-Null
                foreach($g in @('SF-Endpoint-Baseline','SF-Audit-Telemetry','SF-LAPS-Workstations')) {
                    Vincular $g $ou
                }
            }
            $member="OU=Servidores_Membros,OU=Infraestrutura,$baseDN"
            $dmz="OU=Servidores_DMZ,OU=Infraestrutura,$baseDN"
            foreach($ou in @($member,$dmz)) {
                Get-ADOrganizationalUnit -Identity $ou -ErrorAction Stop | Out-Null
                Set-LapsADComputerSelfPermission -Identity $ou -ErrorAction Stop | Out-Null
                Set-LapsADReadPasswordPermission -Identity $ou `
                    -AllowedPrincipals @('SMARTFACTORY\GG_LAPS_Password_Readers') -ErrorAction Stop | Out-Null
                Set-LapsADResetPasswordPermission -Identity $ou `
                    -AllowedPrincipals @('SMARTFACTORY\GG_LAPS_Password_Resetters') -ErrorAction Stop | Out-Null
                Vincular 'SF-LAPS-Servers' $ou
            }
            Vincular 'SF-MemberServer-Baseline' $member
            Vincular 'SF-DMZ-Web-Hardening' $dmz
            # DC hardening, DSRM e Firewall-RemoteAdmin ficam desligados ate homologacao separada.
            $computer=Get-ADComputer -Identity 'CLI-ADM01' -ErrorAction Stop
            if ($computer.DistinguishedName -like "*,$pilotDN") {
                Move-ADObject -Identity $computer.DistinguishedName -TargetPath $originalDN -ErrorAction Stop
            }
            'GPOs PUBLICADAS: endpoints e servidores membros; DC hardening/DSRM/remoto NAO vinculados; CLI retornou a OU original.'
        } @($DN,$PilotoOU,$OriginalOU)
        $r | ForEach-Object { Logar ([string]$_) }
        if (Test-Path $MarcaPos) { Remove-Item -LiteralPath $MarcaPos -Force }
        Add-Content $Relatorio "`n- Publicacao autorizada em $(Get-Date -Format s)." -Encoding UTF8
    }
    'AtivarLapsDSRM' {
        ChecarVMs $false
        if (-not (Test-Path $MarcaPiloto)) { throw 'Piloto nao validado.' }
        $conf=Read-Host 'DC01 System State recuperavel CONFIRMADO? Digite ATIVAR-DSRM'
        if ($conf -ne 'ATIVAR-DSRM') { throw 'DSRM nao alterado.' }
        $r=DC {
            $ErrorActionPreference='Stop'
            Import-Module GroupPolicy -ErrorAction Stop
            $ou='OU=Domain Controllers,DC=smartfactory,DC=corp'
            $links=(Get-GPInheritance -Target $ou).GpoLinks
            if (-not ($links | Where-Object DisplayName -eq 'SF-LAPS-DC-DSRM')) {
                New-GPLink -Name 'SF-LAPS-DC-DSRM' -Target $ou -LinkEnabled Yes -ErrorAction Stop | Out-Null
            }
            'GPO DSRM linkada na OU nativa de DC; confirmar processamento, evento 10018 e capacidade de recuperacao.'
        }
        $r | ForEach-Object { Logar ([string]$_) }
    }
    'ReverterPiloto' {
        ChecarVMs $false
        $conf=Read-Host 'Desvincular 3 GPOs da OU piloto e retornar CLI-ADM01? Digite REVERTER-PILOTO'
        if ($conf -ne 'REVERTER-PILOTO') { throw 'Rollback cancelado.' }
        $r=DC {
            param($pilotDN,$originalDN)
            $ErrorActionPreference='Stop'
            Import-Module ActiveDirectory; Import-Module GroupPolicy
            foreach($g in @('SF-Endpoint-Baseline','SF-Audit-Telemetry','SF-LAPS-Workstations')) {
                $links=(Get-GPInheritance -Target $pilotDN).GpoLinks
                if ($links | Where-Object DisplayName -eq $g) {
                    Set-GPLink -Name $g -Target $pilotDN -LinkEnabled No -ErrorAction Stop | Out-Null
                }
            }
            $computer=Get-ADComputer -Identity 'CLI-ADM01'
            if ($computer.DistinguishedName -like "*,$pilotDN") {
                Move-ADObject -Identity $computer.DistinguishedName -TargetPath $originalDN -ErrorAction Stop
            }
            'PILOTO REVERTIDO: links desabilitados, objeto retornado; schema AD permanece atualizado.'
        } @($PilotoOU,$OriginalOU)
        $r | ForEach-Object { Logar ([string]$_) }
        foreach($arquivo in @($MarcaPiloto,$MarcaPos)) {
            if (Test-Path $arquivo) { Remove-Item $arquivo -Force }
        }
    }
}
