# SmartFactory-GS | Etapa 07 | BKP01, repositorio, backup offline, System State e restauracao
# Execute no Windows PowerShell 5.1 do HOST, como Administrador.
# Os discos de VMs so sao montados offline quando a VM correspondente esta DESLIGADA.
[CmdletBinding()]
param(
    [ValidateSet('Preparar','CriarVM','ConfigurarBase','IngressarDominio','ConfigurarRepositorio',
                 'PrepararTesteFILE01','BackupFILE01Offline','TestarRestauracao','BackupEstadoDC','ArquivarEstadoDC','Validar')]
    [string]$Acao = 'Preparar',
    [string]$IsoPath = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Base = 'D:\FIAP\WINDOWS\SmartFactory-GS'
$VM = 'VM-BKP01'
$VMDir = Join-Path $Base '02-VMs\VM-BKP01'
$VhdOS = Join-Path $VMDir 'VM-BKP01-OS.vhdx'
$VhdRepo = Join-Path $VMDir 'VM-BKP01-REPOSITORIO-B.vhdx'
$VhdFILE = Join-Path $Base '02-VMs\VM-FILE01\VM-FILE01-DADOS-E.vhdx'
$VhdDCStage = Join-Path $Base '02-VMs\VM-DC01\VM-DC01-WSB-STAGING.vhdx'
$LogPath = Join-Path $Base '09-Logs-Testes\09-BKP01-Backup-Restauracao-Resultado.txt'
$DocPath = Join-Path $Base '00-Documentacao\07-BKP01-Backup-Restauracao.md'
$CheckPath = Join-Path $Base '00-Documentacao\07-BKP01-Checklist.txt'
$RoteiroPath = Join-Path $Base '07-Video\Roteiros\Roteiro_Video_Etapa_8.txt'
$EvDir = Join-Path $Base '06-Evidencias\07-BKP01-Backup-Restauracao'
$IsoDir = Join-Path $Base '01-ISOs'

function Registrar([string]$Mensagem) {
    $l = ('{0} | {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Mensagem)
    Add-Content -LiteralPath $LogPath -Value $l -Encoding UTF8
    Write-Host $l
}
function VerificarHost {
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Abra o WINDOWS POWERSHELL 5.1 como Administrador no HOST.'
    }
    if (-not (Test-Path -LiteralPath $Base -PathType Container)) { throw "Pasta base inexistente: $Base" }
    Import-Module Hyper-V -ErrorAction Stop
    foreach ($p in @($VMDir,(Split-Path $LogPath), (Split-Path $DocPath),
                      (Split-Path $RoteiroPath),$EvDir)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
}
function ObterVM([string]$Nome) {
    $v = Get-VM -Name $Nome -ErrorAction SilentlyContinue
    if (-not $v) { throw "VM inexistente: $Nome" }
    return $v
}
function ExigirEstado([string]$Nome,[string]$Estado) {
    $v = ObterVM $Nome
    if ($v.State.ToString() -ne $Estado) { throw "$Nome precisa estar $Estado, mas esta $($v.State)." }
}
function VerificarRecursos {
    ExigirEstado 'VM-FW01' 'Running'
    ExigirEstado 'VM-DC01' 'Running'
    ExigirEstado 'VM-FILE01' 'Off'
    ExigirEstado 'VM-WEB01' 'Off'
    $switch = Get-VMSwitch -Name 'SF-LAN' -ErrorAction Stop
    if ($switch.SwitchType -ne 'Internal') { throw 'Switch SF-LAN nao e Internal.' }
}
function CredencialBKP {
    ExigirEstado $VM 'Running'
    Write-Host 'Antes de ingressar no dominio: Administrator LOCAL; depois: SMARTFACTORY\Administrator.' -ForegroundColor Cyan
    return (Get-Credential -Message 'Administrador da VM-BKP01 (PowerShell Direct)')
}
function GravarSaida($Saida) {
    foreach($linha in @(($Saida | Out-String -Width 220) -split "`r?`n")) {
        if ($linha.Trim()) { Registrar ('GUEST | ' + $linha.Trim()) }
    }
}
function CriarDocumentos {
    if (-not (Test-Path -LiteralPath $DocPath)) {
@'
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
'@ | Set-Content -LiteralPath $DocPath -Encoding UTF8
    }
    if (-not (Test-Path -LiteralPath $CheckPath)) {
@'
[ ] FW01 e DC01 ligadas; FILE01 e WEB01 desligadas antes de instalar BKP01
[ ] Preparar aprovado e ISO validada
[ ] BKP01 Gen2, Desktop Experience, VLAN120, RAM dinamica 2/3/4 GB
[ ] Disco C: 60 GB, disco B: 200 GB, VHDX dinamicos e GPT/NTFS
[ ] BKP01 10.20.120.10/24, gateway .1, DNS DC01
[ ] Ingresso no dominio e OU Backup_Servers
[ ] Repositorio e compartilhamento administrativo com SMB encryption
[ ] PrepararTesteFILE01 criou TXT de teste com FILE01 ligada e BKP01 desligada
[ ] FILE01 desligada antes de montar seu VHDX em modo somente leitura
[ ] BackupFILE01Offline executado e snapshot identificado
[ ] TestarRestauracao: hash SHA256 igual ao arquivo copiado
[ ] System State DC01 pelo wbadmin, em disco staging separado (opcional pesado)
[ ] DC01 e BKP01 desligadas durante ArquivarEstadoDC
[ ] T29: procedimento de recuperacao AD documentado; teste destrutivo nao executado
[ ] Copia offline externa/imutavel REAL: pendente de midia ou servico independente
[ ] Evidencias, relatorio e video 08 registrados
'@ | Set-Content -LiteralPath $CheckPath -Encoding UTF8
    }
    if (-not (Test-Path -LiteralPath $RoteiroPath)) {
@'
Nesta etapa, implementamos o servidor de backup da SmartFactory, chamado VM-BKP01, isolado na VLAN 120.

Criamos a maquina virtual com Windows Server 2025, memoria dinamica e um disco separado para o repositorio. Ingressamos o servidor no dominio smartfactory.corp e configuramos o armazenamento e o compartilhamento administrativo protegido.

Como nosso computador possui apenas 16 gigabytes de RAM, executamos a copia dos arquivos do FILE01 com as maquinas desligadas, lendo o VHDX de dados em modo somente leitura. Isso permitiu preservar uma copia datada sem precisar executar quatro servidores ao mesmo tempo.

Tambem preparamos o backup do estado do sistema do controlador de dominio usando o Windows Server Backup. Depois validamos a recuperacao de um arquivo em um destino de testes, comparando o hash SHA256 para comprovar sua integridade.

A arquitetura corporativa continua prevendo retencao 3-2-1 e copia externa imutavel, mas essa protecao ainda depende de armazenamento fisicamente independente. Por fim, registramos os testes, as limitacoes e as evidencias do laboratorio.
'@ | Set-Content -LiteralPath $RoteiroPath -Encoding UTF8
    }
}
function MontarDiscoVirtual([string]$Path,[bool]$SomenteLeitura,[string]$Rotulo) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "VHDX ausente: $Path" }
    # VMs Off conferidas antes; Mount-VHD abortara caso o VHDX esteja em uso.
    $vhd = Mount-VHD -Path $Path -ReadOnly:$SomenteLeitura -Passthru -ErrorAction Stop
    try {
        $disk = $vhd | Get-Disk -ErrorAction Stop
        $parts = @(Get-Partition -DiskNumber $disk.Number -ErrorAction Stop)
        foreach ($part in $parts) {
            $vol = $part | Get-Volume -ErrorAction SilentlyContinue
            if ($vol -and $vol.FileSystemLabel -eq $Rotulo -and $vol.FileSystem -eq 'NTFS') {
                if (-not $part.DriveLetter) {
                    $usada = $null
                    foreach ($c in @('Z','Y','X','W','V','U')) {
                        if (-not (Get-Volume -DriveLetter $c -ErrorAction SilentlyContinue)) { $usada = $c; break }
                    }
                    if (-not $usada) { throw 'Sem letra de unidade livre para montar o VHDX.' }
                    Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber -AccessPath "${usada}:\" -ErrorAction Stop
                    $letter = $usada
                }
                else { $letter = $part.DriveLetter }
                return [pscustomobject]@{ VHD=$Path; DiskNumber=$disk.Number; Root="${letter}:\"; Label=$Rotulo }
            }
        }
        throw "Volume NTFS com rotulo $Rotulo nao encontrado no VHDX $Path"
    }
    catch {
        Dismount-VHD -Path $Path -ErrorAction SilentlyContinue
        throw
    }
}
function DesmontarSeMontado([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        Dismount-VHD -Path $Path -ErrorAction Stop
    }
}
function GuardarLogNoRelatorio([string]$Texto) {
    Add-Content -LiteralPath $DocPath -Encoding UTF8 -Value ("`n- " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ": " + $Texto)
}

VerificarHost
Registrar "ETAPA 07 - ACAO: $Acao"
try {
    switch ($Acao) {
        'Preparar' {
            VerificarRecursos
            CriarDocumentos
            $livre = [math]::Round((Get-PSDrive -Name D).Free/1GB,2)
            $ram = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1KB/1GB,2)
            Registrar "RAM disponivel no host: ${ram}GB; D livre: ${livre}GB"
            $dm = Get-VMMemory -VMName 'VM-DC01'
            Registrar "DC01: dinamica=$($dm.DynamicMemoryEnabled), minimo=$([int]($dm.Minimum/1MB))MB, inicial=$([int]($dm.Startup/1MB))MB, maximo=$([int]($dm.Maximum/1MB))MB"
            if ($livre -lt 25) { throw 'Menos de 25GB livres em D:. Liberar espaco antes de criar BKP01.' }
            if ($ram -lt 3) { Write-Warning 'Pouca RAM disponivel para ligar BKP01. Pare processos nao essenciais antes da instalacao.' }
            Get-VM | Select-Object Name,State,MemoryAssigned,MemoryDemand | Format-Table -AutoSize
            Registrar "PREPARACAO CONCLUIDA. Roteiro: $RoteiroPath"
        }
        'CriarVM' {
            VerificarRecursos
            if (Get-VM -Name $VM -ErrorAction SilentlyContinue) { throw 'VM-BKP01 ja existe; nao sera sobrescrita.' }
            foreach ($path in @($VhdOS,$VhdRepo)) {
                if (Test-Path -LiteralPath $path) { throw "VHDX existente: $path" }
            }
            if ((Get-PSDrive D).Free -lt 25GB) { throw 'D: abaixo de 25GB livres.' }
            if (-not $IsoPath) {
                $isos = @(Get-ChildItem -Path $IsoDir -Filter '*.iso' -File | Where-Object Name -Match '(SERVER|WindowsServer|26100)')
                if ($isos.Count -ne 1) {
                    $isos | Select-Object FullName
                    throw 'Escolha a ISO usada anteriormente, passando -IsoPath "CAMINHO_COMPLETO.iso".'
                }
                $IsoPath = $isos[0].FullName
            }
            if (-not (Test-Path -LiteralPath $IsoPath -PathType Leaf) -or ([IO.Path]::GetExtension($IsoPath) -ne '.iso')) { throw 'ISO invalida.' }
            New-VM -Name $VM -Generation 2 -MemoryStartupBytes 3GB -NewVHDPath $VhdOS -NewVHDSizeBytes 60GB -SwitchName 'SF-LAN' -Path $VMDir -ErrorAction Stop | Out-Null
            Set-VMProcessor -VMName $VM -Count 2
            Set-VMMemory -VMName $VM -DynamicMemoryEnabled $true -MinimumBytes 2GB -StartupBytes 3GB -MaximumBytes 4GB -Buffer 5
            Set-VM -Name $VM -CheckpointType Disabled -AutomaticCheckpointsEnabled $false -AutomaticStartAction Nothing -AutomaticStopAction ShutDown
            Set-VMFirmware -VMName $VM -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
            $nic = @(Get-VMNetworkAdapter -VMName $VM)
            if ($nic.Count -ne 1) { throw 'Quantidade inesperada de placas de rede.' }
            Rename-VMNetworkAdapter -VMName $VM -Name $nic[0].Name -NewName 'BACKUP'
            Set-VMNetworkAdapterVlan -VMName $VM -VMNetworkAdapterName 'BACKUP' -Access -VlanId 120
            Set-VMNetworkAdapter -VMName $VM -VMNetworkAdapterName 'BACKUP' -RouterGuard On -DhcpGuard On
            $controllers=@(Get-VMScsiController -VMName $VM | Select-Object -ExpandProperty ControllerNumber)
            if (1 -notin $controllers) { Add-VMScsiController -VMName $VM | Out-Null }
            New-VHD -Path $VhdRepo -Dynamic -SizeBytes 200GB -ErrorAction Stop | Out-Null
            Add-VMHardDiskDrive -VMName $VM -ControllerType SCSI -ControllerNumber 1 -ControllerLocation 0 -Path $VhdRepo -ErrorAction Stop
            $dvd = Add-VMDvdDrive -VMName $VM -Path $IsoPath -Passthru -ErrorAction Stop
            Set-VMFirmware -VMName $VM -FirstBootDevice $dvd
            CriarDocumentos
            Registrar 'VM-BKP01 CRIADA: Gen2 2vCPU, RAM dinamica 2/3/4GB, VLAN120, OS60GB + REPO200GB.'
            Registrar 'Instale Windows Server 2025 STANDARD DESKTOP EXPERIENCE e crie a senha local.'
        }
        'ConfigurarBase' {
            $cred = CredencialBKP
            $out = Invoke-Command -VMName $VM -Credential $cred -ErrorAction Stop -ScriptBlock {
                $ErrorActionPreference='Stop'
                $os = Get-CimInstance Win32_OperatingSystem
                $type = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').InstallationType
                if ($os.Caption -notmatch 'Windows Server 2025' -or $type -notmatch 'Server') { throw 'Windows Server 2025 nao identificado.' }
                if ($type -match 'Core') { throw "Selecione Desktop Experience. Modo instalado: $type" }
                $nic = @(Get-NetAdapter | Where-Object Status -eq 'Up')
                if ($nic.Count -ne 1) { throw 'Esperada exatamente uma placa de rede ativa.' }
                $alias = $nic[0].Name
                Set-NetIPInterface -InterfaceAlias $alias -AddressFamily IPv4 -Dhcp Disabled -ErrorAction Stop
                $ips = @(Get-NetIPAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object IPAddress -notlike '169.254*')
                foreach($ip in $ips) {
                    if ($ip.IPAddress -ne '10.20.120.10') {
                        Remove-NetIPAddress -InterfaceAlias $alias -IPAddress $ip.IPAddress -Confirm:$false -ErrorAction Stop
                    }
                }
                if (-not (Get-NetIPAddress -InterfaceAlias $alias -IPAddress '10.20.120.10' -ErrorAction SilentlyContinue)) {
                    New-NetIPAddress -InterfaceAlias $alias -IPAddress '10.20.120.10' -PrefixLength 24 -DefaultGateway '10.20.120.1' -ErrorAction Stop | Out-Null
                }
                Set-DnsClientServerAddress -InterfaceAlias $alias -ServerAddresses '10.20.20.11' -ErrorAction Stop
                Set-TimeZone -Id 'E. South America Standard Time' -ErrorAction Stop
                $ldap = Test-NetConnection '10.20.20.11' -Port 389 -WarningAction SilentlyContinue
                if (-not $ldap.TcpTestSucceeded) { throw 'LDAP DC01 nao acessivel a partir da VLAN120. Verifique a regra BKP->DC no pfSense.' }
                if ($env:COMPUTERNAME -ne 'VM-BKP01') {
                    Rename-Computer -NewName 'VM-BKP01' -Force -ErrorAction Stop
                    'Hostname alterado; reinicio em 15 segundos.'
                    shutdown.exe /r /t 15 /c 'SmartFactory: BKP01 hostname' | Out-Null
                }
                else { 'Host ja e VM-BKP01; rede configurada.' }
                'IP=10.20.120.10/24; Gateway=10.20.120.1; DNS=10.20.20.11'
            }
            GravarSaida $out
            Registrar 'ConfigurarBase concluida. Aguarde eventual reinicializacao.'
        }
        'IngressarDominio' {
            $cred = CredencialBKP
            $dcCred = Get-Credential -Message 'Conta com permissao para ingressar BKP01 no AD (SMARTFACTORY\Administrator)'
            $out = Invoke-Command -VMName $VM -Credential $cred -ArgumentList $dcCred -ErrorAction Stop -ScriptBlock {
                param($adminAD)
                $ErrorActionPreference='Stop'
                if ($env:COMPUTERNAME -ne 'VM-BKP01') { throw 'Aguarde renomeacao e reboot de BKP01.' }
                $computer = Get-CimInstance Win32_ComputerSystem
                if ($computer.PartOfDomain) {
                    if ($computer.Domain -ne 'smartfactory.corp') { throw 'BKP01 em dominio inesperado.' }
                    'Ja esta no dominio smartfactory.corp.'; return
                }
                $ou = 'OU=Backup_Servers,OU=Servidores_Membros,OU=Infraestrutura,DC=smartfactory,DC=corp'
                Add-Computer -DomainName 'smartfactory.corp' -OUPath $ou -Credential $adminAD -ErrorAction Stop
                'Ingresso no dominio concluido. Reinicio em 15 segundos.'
                shutdown.exe /r /t 15 /c 'SmartFactory: ingresso BKP01' | Out-Null
            }
            GravarSaida $out
        }
        'ConfigurarRepositorio' {
            $cred = CredencialBKP
            $out = Invoke-Command -VMName $VM -Credential $cred -ErrorAction Stop -ScriptBlock {
                $ErrorActionPreference = 'Stop'
                $computer = Get-CimInstance Win32_ComputerSystem
                if (-not $computer.PartOfDomain -or $computer.Domain -ne 'smartfactory.corp') { throw 'BKP01 ainda nao esta no dominio.' }
                $disk = @(Get-Disk | Where-Object { $_.Size -gt 199GB -and $_.Size -lt 201GB })
                if ($disk.Count -ne 1) { throw 'Disco de 200GB nao identificado de maneira unica.' }
                if ($disk[0].PartitionStyle -eq 'RAW') {
                    if (Get-Volume -DriveLetter B -ErrorAction SilentlyContinue) { throw 'Unidade B ja em uso; formato cancelado.' }
                    Initialize-Disk -Number $disk[0].Number -PartitionStyle GPT -ErrorAction Stop | Out-Null
                    $partition = New-Partition -DiskNumber $disk[0].Number -UseMaximumSize -DriveLetter 'B' -ErrorAction Stop
                    Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel 'SF_BKP_REPO' -AllocationUnitSize 4096 -Confirm:$false -ErrorAction Stop | Out-Null
                }
                else {
                    $v = Get-Volume -DriveLetter B -ErrorAction SilentlyContinue
                    if (-not $v -or $v.FileSystemLabel -ne 'SF_BKP_REPO') { throw 'Disco preexistente nao esta identificado como B: SF_BKP_REPO. Nao formatar.' }
                }
                $dir = 'B:\Repositorio'
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
                # Root NTFS apenas para SYSTEM e Administradores locais (inclui Domain Admins).
                $acl = Get-Acl -LiteralPath $dir
                $acl.SetAccessRuleProtection($true,$false)
                foreach ($entry in @($acl.Access)) { [void]$acl.RemoveAccessRuleSpecific($entry) }
                foreach ($sidText in @('S-1-5-18','S-1-5-32-544')) {
                    $sid = New-Object System.Security.Principal.SecurityIdentifier($sidText)
                    $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
                        $sid, [System.Security.AccessControl.FileSystemRights]::FullControl,
                        ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
                        [System.Security.AccessControl.PropagationFlags]::None,
                        [System.Security.AccessControl.AccessControlType]::Allow)
                    [void]$acl.AddAccessRule($rule)
                }
                Set-Acl -LiteralPath $dir -AclObject $acl -ErrorAction Stop
                foreach($sub in @('FILE01\Full','DC01\SystemState','Restauracoes_TESTE','Politicas')) {
                    New-Item -Path (Join-Path $dir $sub) -ItemType Directory -Force | Out-Null
                }
                $share=Get-SmbShare -Name 'SF_Repositorio$' -ErrorAction SilentlyContinue
                if (-not $share) {
                    New-SmbShare -Name 'SF_Repositorio$' -Path $dir -FullAccess 'SMARTFACTORY\Domain Admins' `
                        -EncryptData $true -FolderEnumerationMode AccessBased -ErrorAction Stop | Out-Null
                }
                else {
                    if ($share.Path -ne $dir) { throw 'SF_Repositorio$ ja existe apontando para caminho diferente.' }
                    Set-SmbShare -Name 'SF_Repositorio$' -EncryptData $true -FolderEnumerationMode AccessBased -Force -ErrorAction Stop | Out-Null
                }
                $rule = Get-NetFirewallRule -Name 'SF-BKP-Admin-SMB' -ErrorAction SilentlyContinue
                if (-not $rule) {
                    New-NetFirewallRule -Name 'SF-BKP-Admin-SMB' -DisplayName 'SmartFactory BKP01 SMB administrativo restrito' `
                        -Direction Inbound -Action Allow -Protocol TCP -LocalPort 445 -RemoteAddress '10.20.90.10','10.20.20.11','10.20.20.15' `
                        -Profile Domain -Enabled True -ErrorAction Stop | Out-Null
                }
                Set-SmbServerConfiguration -EnableSMB1Protocol $false -RequireSecuritySignature $true -Force -ErrorAction Stop | Out-Null
                'Repositorio pronto: B:\Repositorio, NTFS, SMB criptografado, acesso de administracao e VLAN120.'
            }
            GravarSaida $out
            GuardarLogNoRelatorio 'Repositorio B: e SMB configurados. Backup e restauração ainda pendentes.'
        }
        'PrepararTesteFILE01' {
            ExigirEstado 'VM-FILE01' 'Running'
            ExigirEstado 'VM-BKP01' 'Off'
            $cred=Get-Credential -Message 'SMARTFACTORY\Administrator na VM-FILE01'
            $out=Invoke-Command -VMName 'VM-FILE01' -Credential $cred -ErrorAction Stop -ScriptBlock {
                $ErrorActionPreference='Stop'
                $p='E:\Dados\TI\SF-TESTE-RESTAURACAO.txt'
                if (-not (Test-Path -LiteralPath $p)) {
                    ("SmartFactory - teste de backup e restauracao, gerado em {0}." -f (Get-Date -Format 's')) |
                        Set-Content -LiteralPath $p -Encoding UTF8
                }
                $hash=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
                "Arquivo de teste: $p; SHA256=$hash"
            }
            GravarSaida $out
            Registrar 'Arquivo de teste criado/identificado. Desligue FILE01 normalmente antes do backup offline.'
        }
        'BackupFILE01Offline' {
            ExigirEstado 'VM-FILE01' 'Off'
            ExigirEstado 'VM-BKP01' 'Off'
            if ((Get-PSDrive D).Free -lt 12GB) { throw 'D: tem menos de 12GB livres. Nao iniciar copia offline.' }
            $src=$null; $dst=$null
            try {
                $src = MontarDiscoVirtual -Path $VhdFILE -SomenteLeitura $true -Rotulo 'SF_DADOS'
                $dst = MontarDiscoVirtual -Path $VhdRepo -SomenteLeitura $false -Rotulo 'SF_BKP_REPO'
                $dados = Join-Path $src.Root 'Dados'
                if (-not (Test-Path -LiteralPath $dados -PathType Container)) { throw 'Diretorio Dados nao encontrado no disco E: da FILE01.' }
                $originais = @(Get-ChildItem -LiteralPath $dados -File -Recurse -Force -ErrorAction Stop)
                $tam = ($originais | Measure-Object -Property Length -Sum).Sum
                if ($null -eq $tam) { $tam = 0 }
                $livreB = (Get-Volume -DriveLetter ($dst.Root.Substring(0,1)) -ErrorAction Stop).SizeRemaining
                $livreHost = (Get-PSDrive -Name D).Free
                if ($tam -gt ($livreB - 2GB) -or $tam -gt ($livreHost - 5GB)) {
                    throw "Espaco insuficiente: dados=$tam bytes; disponivel no BKP=$livreB; livre no host=$livreHost."
                }
                $data = Get-Date -Format 'yyyyMMdd_HHmmss'
                $snapshot=Join-Path $dst.Root "Repositorio\FILE01\Full\$data"
                New-Item -ItemType Directory -Path $snapshot -Force | Out-Null
                $logRobo = Join-Path $env:TEMP ("SF-BackupFILE01-{0}.log" -f $data)
                & robocopy.exe $dados $snapshot /E /B /COPY:DAT /DCOPY:DAT /R:2 /W:1 /XJ /NP "/LOG:$logRobo" | Out-Null
                $exit = $LASTEXITCODE
                if ($exit -ge 8) { throw "Robocopy falhou com codigo $exit. Leia $logRobo" }
                $files = @(Get-ChildItem -Path $snapshot -File -Recurse -Force -ErrorAction Stop)
                $bytes = ($files | Measure-Object -Property Length -Sum).Sum
                if ($null -eq $bytes) { $bytes=0 }
                @("Snapshot=$data","Origem=$dados","Destino=$snapshot","Arquivos=$($files.Count)","Bytes=$bytes","RobocopyExit=$exit") |
                    Set-Content -LiteralPath (Join-Path $snapshot '_METADADOS_BACKUP.txt') -Encoding UTF8
                Registrar "BACKUP FILE01 OFFLINE: $($files.Count) arquivos, $bytes bytes, snapshot=$data, Robocopy=$exit"
                GuardarLogNoRelatorio "Backup FILE01 offline criado em B:\Repositorio\FILE01\Full\$data, Robocopy=$exit."
            }
            finally {
                if ($dst) { DesmontarSeMontado $VhdRepo }
                if ($src) { DesmontarSeMontado $VhdFILE }
            }
        }
        'TestarRestauracao' {
            ExigirEstado 'VM-BKP01' 'Off'
            $dst=$null
            try {
                $dst = MontarDiscoVirtual -Path $VhdRepo -SomenteLeitura $false -Rotulo 'SF_BKP_REPO'
                $root=Join-Path $dst.Root 'Repositorio\FILE01\Full'
                $snap=@(Get-ChildItem -Path $root -Directory -ErrorAction Stop | Sort-Object Name -Descending)
                if ($snap.Count -eq 0) { throw 'Nao existe backup FILE01 para restaurar.' }
                $itens=@(Get-ChildItem -LiteralPath $snap[0].FullName -Recurse -File -ErrorAction Stop |
                    Where-Object { $_.Name -ne '_METADADOS_BACKUP.txt' -and $_.Length -gt 0 })
                if ($itens.Count -eq 0) { throw 'Snapshot sem arquivos de usuario. Crie um TXT em E:\Dados\TI na FILE01 e repita o backup.' }
                $amostra = $itens | Sort-Object Length | Select-Object -First 1
                $dir=Join-Path $dst.Root ('Repositorio\Restauracoes_TESTE\'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
                $restaurado=Join-Path $dir $amostra.Name
                Copy-Item -LiteralPath $amostra.FullName -Destination $restaurado -ErrorAction Stop
                $original=(Get-FileHash -LiteralPath $amostra.FullName -Algorithm SHA256).Hash
                $hash=(Get-FileHash -LiteralPath $restaurado -Algorithm SHA256).Hash
                if ($original -ne $hash) { throw 'FALHA: hash SHA256 do arquivo restaurado diverge.' }
                Registrar "T28 RESTAURACAO APROVADA: arquivo=$($amostra.Name), SHA256=$hash"
                GuardarLogNoRelatorio "T28 validado: recuperacao isolada de $($amostra.Name), SHA256 igual."
            }
            finally { if ($dst) { DesmontarSeMontado $VhdRepo } }
        }
        'BackupEstadoDC' {
            ExigirEstado 'VM-DC01' 'Running'
            ExigirEstado 'VM-BKP01' 'Off'
            ExigirEstado 'VM-FILE01' 'Off'
            if (-not (Test-Path -LiteralPath $VhdDCStage)) {
                if ((Get-PSDrive D).Free -lt 30GB) { throw 'Menos de 30GB livres em D:; nao iniciar System State ate liberar espaco.' }
                New-VHD -Path $VhdDCStage -Dynamic -SizeBytes 48GB -ErrorAction Stop | Out-Null
            }
            $disc=@(Get-VMHardDiskDrive -VMName 'VM-DC01' | Where-Object Path -eq $VhdDCStage)
            if ($disc.Count -eq 0) {
                Add-VMHardDiskDrive -VMName 'VM-DC01' -ControllerType SCSI -Path $VhdDCStage -ErrorAction Stop
                Registrar 'Disco de System State anexado ao DC01.'
            }
            $cred=Get-Credential -Message 'SMARTFACTORY\Administrator do VM-DC01 (PowerShell Direct)'
            $out=Invoke-Command -VMName 'VM-DC01' -Credential $cred -ErrorAction Stop -ScriptBlock {
                $ErrorActionPreference='Stop'
                $disk=@(Get-Disk | Where-Object { $_.Size -gt 47GB -and $_.Size -lt 49GB -and $_.BusType -ne 'USB' })
                if ($disk.Count -ne 1) { throw 'Disco staging 48GB nao identificado unicamente; nao formatar.' }
                $vol=Get-Volume -DriveLetter R -ErrorAction SilentlyContinue
                if ($disk[0].PartitionStyle -eq 'RAW') {
                    if ($vol) { throw 'R: ja usada no DC01; pare antes de formatar.' }
                    Initialize-Disk -Number $disk[0].Number -PartitionStyle GPT -ErrorAction Stop | Out-Null
                    $part=New-Partition -DiskNumber $disk[0].Number -UseMaximumSize -DriveLetter R -ErrorAction Stop
                    Format-Volume -Partition $part -FileSystem NTFS -NewFileSystemLabel 'SF_DC01_SYSTEMSTATE' -Confirm:$false -ErrorAction Stop | Out-Null
                }
                elseif (-not $vol -or $vol.FileSystemLabel -ne 'SF_DC01_SYSTEMSTATE') { throw 'R: nao e o disco staging esperado; pare.' }
                $feat=Get-WindowsFeature -Name Windows-Server-Backup
                if (-not $feat.Installed) {
                    $ret=Install-WindowsFeature -Name Windows-Server-Backup -ErrorAction Stop
                    if (-not $ret.Success) { throw 'Falha ao instalar Windows Server Backup no DC01.' }
                }
                $output=& wbadmin.exe start systemstatebackup '-backupTarget:R:' -quiet 2>&1
                $exit=$LASTEXITCODE
                if ($exit -ne 0) { throw "WBADMIN falhou ($exit): $($output | Out-String)" }
                "WBADMIN System State DC01: sucesso; $((Get-Date).ToString('s'))"
                (& wbadmin.exe get versions 2>&1 | Out-String)
            }
            GravarSaida $out
            GuardarLogNoRelatorio 'System State DC01 criado usando Windows Server Backup, em VHDX staging R:. Arquivamento separado pendente.'
        }
        'ArquivarEstadoDC' {
            ExigirEstado 'VM-DC01' 'Off'
            ExigirEstado 'VM-BKP01' 'Off'
            $src=$null; $dst=$null
            try {
                $src=MontarDiscoVirtual -Path $VhdDCStage -SomenteLeitura $true -Rotulo 'SF_DC01_SYSTEMSTATE'
                $dst=MontarDiscoVirtual -Path $VhdRepo -SomenteLeitura $false -Rotulo 'SF_BKP_REPO'
                $wb=Join-Path $src.Root 'WindowsImageBackup'
                if (-not (Test-Path -LiteralPath $wb -PathType Container)) { throw 'WindowsImageBackup nao existe no staging DC01.' }
                $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
                $repo=Join-Path $dst.Root "Repositorio\DC01\SystemState\$stamp\WindowsImageBackup"
                New-Item -ItemType Directory -Path $repo -Force | Out-Null
                $robo=Join-Path $env:TEMP "SF-SystemStateDC01-$stamp.log"
                & robocopy.exe $wb $repo /E /B /COPY:DAT /DCOPY:DAT /R:2 /W:1 /XJ /NP "/LOG:$robo" | Out-Null
                $result=$LASTEXITCODE
                if ($result -ge 8) { throw "Robocopy System State falhou ($result): $robo" }
                $n=@(Get-ChildItem -LiteralPath $repo -Recurse -File -ErrorAction Stop).Count
                if ($n -eq 0) { throw 'Arquivo System State vazio apos copiar.' }
                Registrar "System State DC01 arquivado: $stamp, arquivos=$n, Robocopy=$result"
                GuardarLogNoRelatorio "System State DC01 arquivado em B:\Repositorio\DC01\SystemState\$stamp (nao executar restauracao destrutiva)."
            }
            finally {
                if ($dst) { DesmontarSeMontado $VhdRepo }
                if ($src) { DesmontarSeMontado $VhdDCStage }
            }
        }
        'Validar' {
            $v=ObterVM $VM
            $n=Get-VMNetworkAdapterVlan -VMName $VM -VMNetworkAdapterName 'BACKUP'
            $discos=@(Get-VMHardDiskDrive -VMName $VM)
            $ram=Get-VMMemory -VMName $VM
            $cond=($v.Generation -eq 2 -and $n.OperationMode -eq 'Access' -and $n.AccessVlanId -eq 120 -and
                   $discos.Count -eq 2 -and $ram.DynamicMemoryEnabled)
            Registrar "Hyper-V BKP01: estado=$($v.State); Gen=$($v.Generation); NIC-VLAN=$($n.AccessVlanId); VHDX=$($discos.Count); RAM-Dinamica=$($ram.DynamicMemoryEnabled)"
            if (-not $cond) { throw 'Validacao Hyper-V BKP01 reprovada.' }
            if ($v.State -eq 'Running') {
                $cred=CredencialBKP
                $out=Invoke-Command -VMName $VM -Credential $cred -ErrorAction Stop -ScriptBlock {
                    $ErrorActionPreference='Stop'
                    $computer=Get-CimInstance Win32_ComputerSystem
                    if (-not $computer.PartOfDomain -or $computer.Domain -ne 'smartfactory.corp') { throw 'BKP01 fora do dominio.' }
                    $ipv4=Get-NetIPAddress -IPAddress '10.20.120.10' -ErrorAction Stop
                    $repo=Get-Volume -DriveLetter B -ErrorAction Stop
                    if ($repo.FileSystemLabel -ne 'SF_BKP_REPO') { throw 'Volume B: incorreto.' }
                    $share=Get-SmbShare -Name 'SF_Repositorio$' -ErrorAction Stop
                    if ($share.Path -ne 'B:\Repositorio' -or -not $share.EncryptData) { throw 'Share de backup incorreta ou nao criptografada.' }
                    "AD=$($computer.Domain); IP=$($ipv4.IPAddress); B:=$($repo.FileSystemLabel); share=$($share.Name); EncryptData=$($share.EncryptData)"
                    "Snapshots FILE01=$(@(Get-ChildItem 'B:\Repositorio\FILE01\Full' -Directory -ErrorAction SilentlyContinue).Count)"
                    "Arquivos SystemState DC01=$(@(Get-ChildItem 'B:\Repositorio\DC01\SystemState' -Directory -ErrorAction SilentlyContinue).Count)"
                    "Restauracoes TESTE=$(@(Get-ChildItem 'B:\Repositorio\Restauracoes_TESTE' -Directory -ErrorAction SilentlyContinue).Count)"
                }
                GravarSaida $out
            }
            else { Registrar 'BKP01 esta desligada; ligue-a para validacao interna via PowerShell Direct.' }
            Registrar 'VALIDACAO ESTRUTURAL CONCLUIDA. Verifique snapshots, restore e System State nos logs.'
        }
    }
}
catch {
    Registrar ('ERRO: '+$_.Exception.Message)
    throw
}
