# SmartFactory-GS | Etapa 06 | VM-WEB01, IIS, Intranet, DNS/SPN e DMZ
# Executar no WINDOWS POWERSHELL 5.1 do HOST como Administrador.
# Acoes sequenciais: Preparar, CriarVM, ConfigurarBase, IngressarDominio, ConfigurarIIS, Validar.
# Nao executa GPO, nao altera as regras pfSense nem desliga o DC01.
[CmdletBinding()]
param(
    [ValidateSet('Preparar','CriarVM','ConfigurarBase','IngressarDominio','ConfigurarIIS','Validar')]
    [string]$Acao='Preparar',
    [string]$IsoPath=''
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Base='D:\FIAP\WINDOWS\SmartFactory-GS'
$VmName='VM-WEB01'
$VmDir=Join-Path $Base '02-VMs\VM-WEB01'
$VhdPath=Join-Path $VmDir 'VM-WEB01-OS.vhdx'
$IsoDir=Join-Path $Base '01-ISOs'
$LogsDir=Join-Path $Base '09-Logs-Testes'
$DocsDir=Join-Path $Base '00-Documentacao'
$RoteirosDir=Join-Path $Base '07-Video\Roteiros'
$EvidenciasDir=Join-Path $Base '06-Evidencias\06-WEB01-IIS-Intranet-DMZ'
$LogPath=Join-Path $LogsDir '08-WEB01-IIS-Intranet-Resultado.txt'
$ReportPath=Join-Path $DocsDir '06-WEB01-IIS-Intranet-DMZ.md'
$CheckPath=Join-Path $DocsDir '06-WEB01-Checklist.txt'
$VideoPath=Join-Path $RoteirosDir 'Roteiro_Video_Etapa_7.txt'
$Fqdn='intranet.smartfactory.corp'

function Log([string]$Mensagem) {
    $linha=('{0} | {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Mensagem)
    Add-Content -LiteralPath $LogPath -Value $linha -Encoding UTF8
    Write-Host $linha
}
function IniciarHost {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $user=[Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $user.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Abra o Windows PowerShell 5.1 como ADMINISTRADOR no computador hospedeiro.'
    }
    if (-not (Test-Path -LiteralPath $Base -PathType Container)) { throw "Pasta base nao encontrada: $Base" }
    Import-Module Hyper-V -ErrorAction Stop
    foreach($p in @($VmDir,$LogsDir,$DocsDir,$RoteirosDir,$EvidenciasDir)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
}
function VerificarInfra {
    foreach($n in @('VM-FW01','VM-DC01')) {
        $vm=Get-VM -Name $n -ErrorAction SilentlyContinue
        if (-not $vm -or $vm.State -ne 'Running') { throw "$n deve estar LIGADA nesta etapa." }
    }
    $file=Get-VM -Name 'VM-FILE01' -ErrorAction SilentlyContinue
    if ($file -and $file.State -ne 'Off') {
        throw 'VM-FILE01 precisa estar DESLIGADA para economizar RAM. Use: Stop-VM -Name "VM-FILE01" -Shutdown (aguarde Off).'
    }
    $sw=Get-VMSwitch -Name 'SF-LAN' -ErrorAction Stop
    if ($sw.SwitchType -ne 'Internal') { throw 'SF-LAN nao e Internal.' }
    $nics=Get-VMNetworkAdapter -VMName 'VM-FW01'
    $fwLan=$nics | Where-Object Name -eq 'LAN' | Select-Object -First 1
    if (-not $fwLan -or $fwLan.SwitchName -ne 'SF-LAN') { throw 'LAN do pfSense nao esta no SF-LAN.' }
    $trunk=Get-VMNetworkAdapterVlan -VMName 'VM-FW01' -VMNetworkAdapterName 'LAN' -ErrorAction Stop
    if ($trunk.OperationMode -ne 'Trunk' -or $trunk.NativeVlanId -ne 99) {
        throw 'Trunk da FW01 nao apresenta VLAN nativa 99. Verificar Etapa 03.'
    }
}
function CredencialConvidado {
    $vm=Get-VM -Name $VmName -ErrorAction Stop
    if ($vm.State -ne 'Running') { throw "Ligue $VmName e aguarde o Windows terminar a inicializacao." }
    Write-Host 'Antes do dominio: credencial LOCAL. Apos o dominio: SMARTFACTORY\Administrator.' -ForegroundColor Cyan
    return (Get-Credential -Message 'Credenciais de administrador da VM-WEB01 (PowerShell Direct)')
}
function GravarResultado($result) {
    foreach($o in @($result)) {
        if ($null -ne $o) {
            $texto=($o | Out-String -Width 240).Trim()
            foreach($l in ($texto -split "`r?`n")) {
                if ($l.Trim()) { Log ('GUEST | '+$l.Trim()) }
            }
        }
    }
}
function RelatoriosIniciais {
    if (-not (Test-Path -LiteralPath $ReportPath)) {
@'
# SmartFactory-GS | Etapa 06: IIS e Intranet RH na DMZ

Status: EM IMPLEMENTACAO. Nao considerar testes com cliente concluidos antecipadamente.

## Arquitetura
- VM-WEB01: Windows Server 2025 Standard Desktop Experience, Gen2, 2 vCPU.
- RAM dinamica: minima 2 GB, inicial 3 GB, maxima 4 GB, buffer 5%.
- VHDX dinamico 80 GB; switch SF-LAN, Access VLAN 100.
- Host: VM-WEB01, IPv4 10.20.100.10/24, GW 10.20.100.1, DNS 10.20.20.11.
- Dominio smartfactory.corp, OU Infraestrutura/Servidores_DMZ/Web_Servers.
- IIS: site HTTPS intranet.smartfactory.corp, porta 443, certificado RSA 2048 autoassinado (laboratorio).
- HTTP porta 80: site separado, redirect permanente 301 para HTTPS.
- Windows Authentication (Negotiate/Kerberos preferencial), Anonymous Authentication off no site HTTPS.
- App Pool dedicado com ApplicationPoolIdentity.
- DNS: CNAME intranet -> vm-web01 e SPN HTTP/intranet.smartfactory.corp na conta VM-WEB01$.
- Firewall Windows: TCP 80/443 de VLANs 30-90; RDP TCP3389 apenas de PAW 10.20.90.10 com NLA; demais entradas sob bloqueio padrao.
- pfSense: ACLs da Etapa 03; WEB01 sem acesso geral para redes de usuarios.

## Restricoes e ressalvas
- O certificado e autoassinado: navegadores sem confianca exibirao aviso.
- Windows Server 2025 tem suporte a TLS 1.3; NAO declaramos TLS 1.3 EXCLUSIVO sem teste de negociacao e hardening posterior.
- A autenticacao Kerberos real e o SSO requerem cliente Windows no dominio e serao testados depois.
- Wazuh, GPO, LAPS e validacao de isolamento com segundo host: etapas posteriores.
- Sem publicacao da intranet na WAN: aplicacao interna apenas.
- Uma VM/host fisico: sem alta disponibilidade de IIS.

## Evidencias
- Hyper-V: Gen2, RAM, Disco, VLAN 100.
- Windows Server: versao, Desktop Experience, hostname, rede e dominio.
- IIS: binding 80/443, certificado, Windows Auth, app pool e redirect.
- DC01: CNAME intranet e SPN HTTP/intranet.smartfactory.corp.
- Logs dos scripts e video 07.
- Acesso de cliente com usuario de dominio: pendente de estacao Windows 11.
'@ | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    }
    if (-not (Test-Path -LiteralPath $CheckPath)) {
@'
[ ] VM-FILE01 desligada com encerramento normal; FW01 e DC01 ligadas
[ ] DC01 permanece em RAM dinamica (sem modificacao nesta etapa)
[ ] ISO Windows Server 2025 funcional selecionada
[ ] VM-WEB01 Gen2, RAM dinamica 2/3/4 GB, 2 vCPU, VLAN 100, VHDX 80GB
[ ] Windows Server 2025 Standard Desktop Experience instalado
[ ] ConfigurarBase: IP 10.20.100.10/24, GW 10.20.100.1, DNS 10.20.20.11
[ ] IngressarDominio: smartfactory.corp; OU Web_Servers
[ ] IIS: site HTTP redirect 301, site HTTPS 443, app pool dedicado
[ ] Certificado RSA 2048 no binding HTTPS
[ ] Windows Auth ON e Anonymous OFF no site HTTPS
[ ] DNS: CNAME intranet.smartfactory.corp e SPN HTTP na VM-WEB01
[ ] Windows Firewall TCP 80/443 restrito as redes 30-90; RDP NLA somente da PAW
[ ] Testes locais de 301 e 401, se suportados pelo ambiente
[ ] Validacao script aprovada; prints e video 07 gravados
[ ] Registrar: certificado autoassinado; TLS1.3 nao imposto de forma exclusiva
[ ] Registrar: SSO/Kerberos por cliente e isolamento de rede aguardam as VMs de testes
'@ | Set-Content -LiteralPath $CheckPath -Encoding UTF8
    }
    if (-not (Test-Path -LiteralPath $VideoPath)) {
@'
Nesta etapa, implementamos a intranet da SmartFactory na maquina virtual VM-WEB01, localizada na VLAN 100, que e a nossa DMZ interna.

Criamos o Windows Server 2025 Standard com Desktop Experience, utilizando memoria dinamica para reduzir o consumo de RAM do computador. Configuramos IP fixo, DNS corporativo e ingressamos o servidor no dominio smartfactory.corp.

Depois, instalamos o IIS, criamos o site intranet.smartfactory.corp com HTTPS na porta 443 e um certificado para o ambiente de laboratorio. A porta HTTP 80 foi configurada somente para redirecionar os acessos para HTTPS.

Tambem habilitamos a autenticacao integrada do Windows, preparamos o Kerberos por meio do registro SPN no Active Directory e isolamos a aplicacao em seu proprio Application Pool. O DNS recebeu o alias da intranet.

Por fim, verificamos os servicos e registramos as evidencias. O acesso de um cliente real e a negociacao Kerberos serao comprovados quando instalarmos a estacao de testes, sem afirmar que esses testes ja foram realizados.
'@ | Set-Content -LiteralPath $VideoPath -Encoding UTF8
    }
}

IniciarHost
Log "INICIO Etapa 06 / Acao $Acao"
try {
    switch($Acao) {
        'Preparar' {
            VerificarInfra
            $status=Get-VM | Where-Object { $_.Name -like 'VM-*' -or $_.Name -like '*-TI01' -or $_.Name -like 'CLI-*' } |
                Select-Object Name,State,MemoryAssigned,MemoryDemand
            Log ('VMs: '+(($status | Out-String -Width 180).Trim() -replace "`r?`n",' | '))
            $dm=Get-VMMemory -VMName 'VM-DC01'
            Log "DC01 RAM: Dinamica=$($dm.DynamicMemoryEnabled); Inicial=$([math]::Round($dm.Startup/1MB))MB; Min=$([math]::Round($dm.Minimum/1MB))MB; Max=$([math]::Round($dm.Maximum/1MB))MB"
            if (-not $dm.DynamicMemoryEnabled) { Write-Warning 'DC01 nao parece estar com RAM dinamica. Confira; nao alterarei automaticamente.' }
            $os=Get-CimInstance Win32_OperatingSystem
            $livreRAM=[math]::Round($os.FreePhysicalMemory*1KB/1GB,2)
            $livreD=[math]::Round((Get-PSDrive -Name D).Free/1GB,2)
            Log "Host RAM disponivel=$livreRAM GB; D: disponivel=$livreD GB"
            if ($livreD -lt 25) { throw 'D: com menos de 25GB livres. Nao criar novo VHDX antes de liberar espaco.' }
            if ($livreRAM -lt 2.7) { Write-Warning 'RAM livre inferior a 2,7GB. Feche apps e reinicie o host, se necessario, antes de iniciar WEB01.' }
            RelatoriosIniciais
            $isos=@(Get-ChildItem -LiteralPath $IsoDir -File -Filter '*.iso' | Where-Object Name -Match 'server|26100')
            Log "ISOs candidatas do Windows Server: $($isos.Count)"
            foreach($iso in $isos) { Log ("ISO: {0}" -f $iso.FullName) }
            Log "PREPARACAO CONCLUIDA. Roteiro: $VideoPath"
        }
        'CriarVM' {
            VerificarInfra
            if (Get-VM -Name $VmName -ErrorAction SilentlyContinue) { throw 'VM-WEB01 ja existe. Nao sera recriada.' }
            if (Test-Path -LiteralPath $VhdPath) { throw 'VHDX de destino ja existe. Nao sera sobrescrito.' }
            if ((Get-PSDrive -Name D).Free -lt 25GB) { throw 'Espaco D: inferior a 25GB.' }
            if (-not $IsoPath) {
                $isos=@(Get-ChildItem -LiteralPath $IsoDir -File -Filter '*.iso' | Where-Object Name -Match 'server|26100')
                if ($isos.Count -ne 1) {
                    foreach($iso in $isos) { Write-Host $iso.FullName }
                    throw 'Existem zero ou multiplas ISOs. Execute -Acao CriarVM -IsoPath "CAMINHO_DA_ISO_VALIDA.iso".'
                }
                $IsoPath=$isos[0].FullName
            }
            if (-not (Test-Path -LiteralPath $IsoPath -PathType Leaf)) { throw "ISO invalida: $IsoPath" }
            if ([IO.Path]::GetExtension($IsoPath) -ine '.iso') { throw 'Use arquivo .iso valido.' }
            New-VM -Name $VmName -Generation 2 -MemoryStartupBytes 3GB -NewVHDPath $VhdPath `
                -NewVHDSizeBytes 80GB -SwitchName 'SF-LAN' -Path $VmDir -ErrorAction Stop | Out-Null
            Set-VMProcessor -VMName $VmName -Count 2
            Set-VMMemory -VMName $VmName -DynamicMemoryEnabled $true -MinimumBytes 2GB `
                -StartupBytes 3GB -MaximumBytes 4GB -Buffer 5 -Priority 40
            Set-VMFirmware -VMName $VmName -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
            Set-VM -Name $VmName -CheckpointType Disabled -AutomaticCheckpointsEnabled $false `
                -AutomaticStartAction Nothing -AutomaticStopAction ShutDown
            $nic=@(Get-VMNetworkAdapter -VMName $VmName)
            if ($nic.Count -ne 1) { throw 'Esperado exatamente um adaptador de rede WEB01.' }
            Rename-VMNetworkAdapter -VMName $VmName -Name $nic[0].Name -NewName 'DMZ'
            Set-VMNetworkAdapterVlan -VMName $VmName -VMNetworkAdapterName DMZ -Access -VlanId 100
            Set-VMNetworkAdapter -VMName $VmName -Name DMZ -DhcpGuard On -RouterGuard On
            $dvd=Get-VMDvdDrive -VMName $VmName -ErrorAction SilentlyContinue
            if ($dvd) { Set-VMDvdDrive -VMName $VmName -Path $IsoPath }
            else { Add-VMDvdDrive -VMName $VmName -Path $IsoPath | Out-Null }
            Set-VMFirmware -VMName $VmName -FirstBootDevice (Get-VMDvdDrive -VMName $VmName | Select-Object -First 1)
            Log "VM CRIADA: $VmName; Gen2; 2vCPU; RAM dinamica 2/3/4GB; VHDX 80GB; VLAN100"
            Log "ISO: $IsoPath"
            Log 'Agora inicie VM-WEB01 e instale Windows Server 2025 STANDARD (DESKTOP EXPERIENCE).'
        }
        'ConfigurarBase' {
            $cred=CredencialConvidado
            $out=Invoke-Command -VMName $VmName -Credential $cred -ErrorAction Stop -ScriptBlock {
                $ErrorActionPreference='Stop'
                $os=Get-CimInstance Win32_OperatingSystem
                if ($os.Caption -notmatch 'Windows Server 2025') { throw "Sistema inesperado: $($os.Caption)" }
                $tipo=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').InstallationType
                if ($tipo -match 'Core') { throw 'Foi instalada versao Server Core. WEB01 exige Desktop Experience.' }
                $adap=@(Get-NetAdapter | Where-Object Status -eq Up)
                if ($adap.Count -ne 1) { throw 'Nao encontrei exatamente uma placa de rede ativa no WEB01.' }
                $i=$adap[0].InterfaceIndex
                Set-NetIPInterface -InterfaceIndex $i -AddressFamily IPv4 -Dhcp Disabled -ErrorAction Stop
                $ips=@(Get-NetIPAddress -InterfaceIndex $i -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object { $_.IPAddress -ne '10.20.100.10' -and $_.PrefixOrigin -ne 'WellKnown' })
                foreach($ip in $ips) { Remove-NetIPAddress -InputObject $ip -Confirm:$false -ErrorAction Stop }
                $ipok=Get-NetIPAddress -InterfaceIndex $i -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object IPAddress -eq '10.20.100.10'
                if (-not $ipok) { New-NetIPAddress -InterfaceIndex $i -IPAddress '10.20.100.10' -PrefixLength 24 `
                    -DefaultGateway '10.20.100.1' -ErrorAction Stop | Out-Null }
                Set-DnsClientServerAddress -InterfaceIndex $i -ServerAddresses @('10.20.20.11') -ErrorAction Stop
                Set-TimeZone -Id 'E. South America Standard Time'
                $a=Resolve-DnsName -Name 'vm-dc01.smartfactory.corp' -Server '10.20.20.11' `
                    -Type A -ErrorAction Stop
                if (-not @($a | Where-Object IPAddress -eq '10.20.20.11').Count) { throw 'DNS do DC01 nao retornou 10.20.20.11.' }
                $port=Test-NetConnection -ComputerName '10.20.20.11' -Port 389 -WarningAction SilentlyContinue
                if (-not $port.TcpTestSucceeded) { throw 'DMZ nao alcança LDAP TCP389 no DC01. Reveja ACL pfSense da Etapa03.' }
                $reboot=$env:COMPUTERNAME -ne 'VM-WEB01'
                if ($reboot) { Rename-Computer -NewName 'VM-WEB01' -Force -ErrorAction Stop }
                "OS=$($os.Caption); IP=10.20.100.10/24; GW=10.20.100.1; DNS=10.20.20.11; LDAP-DC=True; RENOMEADO=$reboot"
                if ($reboot) { shutdown.exe /r /t 15 /c 'SmartFactory - hostname WEB01' | Out-Null
                    'REINICIO AGENDADO EM 15 SEGUNDOS. AGUARDE VOLTAR AO LOGIN.' }
            }
            GravarResultado $out
            Log 'BASE CONFIGURADA. Se nome mudou, aguarde reboot antes de ingressar no dominio.'
        }
        'IngressarDominio' {
            $cred=CredencialConvidado
            $domainCred=Get-Credential -Message 'Credencial SMARTFACTORY\Administrator para ingressar WEB01 no AD'
            $out=Invoke-Command -VMName $VmName -Credential $cred -ArgumentList $domainCred -ErrorAction Stop -ScriptBlock {
                param($adminAD)
                $ErrorActionPreference='Stop'
                if ($env:COMPUTERNAME -ne 'VM-WEB01') { throw 'WEB01 ainda nao foi renomeada/reiniciada.' }
                $c=Get-CimInstance Win32_ComputerSystem
                if ($c.PartOfDomain) {
                    if ($c.Domain -ne 'smartfactory.corp') { throw "Dominio inesperado: $($c.Domain)" }
                    'WEB01 ja pertence a smartfactory.corp.'
                    return
                }
                $ou='OU=Web_Servers,OU=Servidores_DMZ,OU=Infraestrutura,DC=smartfactory,DC=corp'
                $dc=Test-NetConnection -ComputerName '10.20.20.11' -Port 389 -WarningAction SilentlyContinue
                if (-not $dc.TcpTestSucceeded) { throw 'Sem comunicacao LDAP com DC01 pela DMZ.' }
                Add-Computer -DomainName 'smartfactory.corp' -OUPath $ou -Credential $adminAD -ErrorAction Stop
                'INGRESSO NO DOMINIO CONCLUIDO. Reinicio em 15 segundos.'
                shutdown.exe /r /t 15 /c 'SmartFactory - ingresso no dominio' | Out-Null
            }
            GravarResultado $out
            Log 'Aguarde reboot; nas proximas etapas informe SMARTFACTORY\Administrator.'
        }
        'ConfigurarIIS' {
            $cred=CredencialConvidado
            $out=Invoke-Command -VMName $VmName -Credential $cred -ErrorAction Stop -ScriptBlock {
                $ErrorActionPreference='Stop'
                $machine=Get-CimInstance Win32_ComputerSystem
                if (-not $machine.PartOfDomain -or $machine.Domain -ne 'smartfactory.corp') {
                    throw 'O WEB01 ainda nao pertence ao dominio smartfactory.corp.'
                }
                $features=@('Web-Server','Web-Windows-Auth','Web-Http-Redirect',
                    'Web-Mgmt-Tools','Web-Scripting-Tools','Web-Static-Content','Web-Default-Doc','Web-Http-Logging')
                $ret=Install-WindowsFeature -Name $features -IncludeManagementTools -ErrorAction Stop
                if (-not $ret.Success) { throw 'Falha instalando recursos IIS.' }
                if ($ret.RestartNeeded -eq 'Yes') {
                    throw 'IIS requer reinicio. Reinicie WEB01 normalmente e execute ConfigurarIIS de novo.'
                }
                Import-Module WebAdministration -ErrorAction Stop
                $site='SF-Intranet'
                $redirect='SF-HTTP-Redirect'
                $fqdn='intranet.smartfactory.corp'
                $pool='SF-Intranet-Pool'
                $dirSite='C:\inetpub\SmartFactory-Intranet'
                $dirRedirect='C:\inetpub\SmartFactory-Redirect'
                New-Item -Path $dirSite,$dirRedirect -ItemType Directory -Force | Out-Null
                $html=@'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Intranet RH | SmartFactory</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#101b2b;color:#f2f7ff;font-family:Segoe UI,Arial,sans-serif}header{background:#14273e;border-bottom:1px solid #33506b;padding:25px 7%;display:flex;justify-content:space-between;align-items:center}strong{letter-spacing:.1em;color:#81d6ff}main{max-width:970px;margin:70px auto;padding:0 25px}small{color:#a8bdd1}.panel{background:#182d45;padding:34px;border:1px solid #35526b;border-radius:15px}h1{font-size:2.4rem;margin:8px 0 16px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:16px;margin-top:24px}.tile{background:#203750;border-radius:10px;padding:22px}.tile h2{font-size:1.05rem;margin-top:0}.tile p{font-size:.9rem;line-height:1.5;color:#cbdaea}footer{padding:30px;text-align:center;color:#a8bdd1;font-size:.8rem}
</style>
</head>
<body>
<header><strong>SMARTFACTORY / INTRANET</strong><small>Recursos Humanos • Portal Interno</small></header>
<main><section class="panel"><small>AMBIENTE CORPORATIVO PROTEGIDO</small><h1>Bem-vindo à SmartFactory</h1><p>Portal de comunicação interna. O acesso é integrado às credenciais do domínio smartfactory.corp.</p>
<div class="grid"><article class="tile"><h2>Comunicados</h2><p>Área demonstrativa para avisos institucionais.</p></article><article class="tile"><h2>Recursos Humanos</h2><p>Informações e solicitações internas de colaboradores.</p></article><article class="tile"><h2>Segurança</h2><p>Serviço hospedado na DMZ, com HTTPS e autenticação do Windows.</p></article></div></section></main>
<footer>SmartFactory GS • Projeto acadêmico • Sem integração com dados reais de RH</footer>
</body></html>
'@
                $html | Set-Content -Path (Join-Path $dirSite 'index.html') -Encoding UTF8
                if (-not (Test-Path -LiteralPath 'IIS:\AppPools\SF-Intranet-Pool')) {
                    New-WebAppPool -Name $pool | Out-Null
                }
                Set-ItemProperty -Path "IIS:\AppPools\$pool" -Name 'processModel.identityType' -Value 'ApplicationPoolIdentity'
                Set-ItemProperty -Path "IIS:\AppPools\$pool" -Name 'managedRuntimeVersion' -Value ''
                # Removemos somente o website padrao de uma instalacao nova, nao aplicativos externos.
                if (Get-Website -Name 'Default Web Site' -ErrorAction SilentlyContinue) {
                    Stop-Website -Name 'Default Web Site' -ErrorAction SilentlyContinue
                    Remove-Website -Name 'Default Web Site' -ErrorAction Stop
                }
                $cert=Get-ChildItem 'Cert:\LocalMachine\My' | Where-Object {
                    $_.Subject -eq ('CN='+$fqdn) -and $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date).AddDays(30)
                } | Sort-Object NotAfter -Descending | Select-Object -First 1
                if (-not $cert) {
                    $cert=New-SelfSignedCertificate -DnsName $fqdn -CertStoreLocation 'Cert:\LocalMachine\My' `
                        -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 -KeyExportPolicy NonExportable `
                        -NotAfter (Get-Date).AddMonths(12) -FriendlyName 'SmartFactory Intranet - Laboratorio' -ErrorAction Stop
                }
                if (-not (Get-Website -Name $site -ErrorAction SilentlyContinue)) {
                    New-Website -Name $site -Port 443 -IPAddress '*' -HostHeader $fqdn -Ssl `
                        -PhysicalPath $dirSite -ApplicationPool $pool -SslFlags 1 -ErrorAction Stop | Out-Null
                }
                $b=Get-WebBinding -Name $site -Protocol https -ErrorAction SilentlyContinue |
                    Where-Object { $_.bindingInformation -eq "*:443:$fqdn" } | Select-Object -First 1
                if (-not $b) {
                    New-WebBinding -Name $site -Protocol https -IPAddress '*' -Port 443 `
                        -HostHeader $fqdn -SslFlags 1 -ErrorAction Stop
                    $b=Get-WebBinding -Name $site -Protocol https | Where-Object {
                        $_.bindingInformation -eq "*:443:$fqdn"
                    } | Select-Object -First 1
                }
                if (-not $b) { throw 'Nao foi criado o binding HTTPS da Intranet.' }
                # New-Website/New-WebBinding configuram SNI (sslFlags=1).
                $b=Get-WebBinding -Name $site -Protocol https | Where-Object {
                    $_.bindingInformation -eq "*:443:$fqdn"
                } | Select-Object -First 1
                $b.AddSslCertificate($cert.Thumbprint,'My')
                Set-WebConfigurationProperty -PSPath "IIS:\Sites\$site" `
                    -Filter 'system.webServer/security/authentication/anonymousAuthentication' `
                    -Name enabled -Value $false -ErrorAction Stop
                Set-WebConfigurationProperty -PSPath "IIS:\Sites\$site" `
                    -Filter 'system.webServer/security/authentication/windowsAuthentication' `
                    -Name enabled -Value $true -ErrorAction Stop
                Set-WebConfigurationProperty -PSPath "IIS:\Sites\$site" `
                    -Filter 'system.webServer/security/authentication/windowsAuthentication' `
                    -Name useKernelMode -Value $true -ErrorAction Stop
                if (-not (Get-Website -Name $redirect -ErrorAction SilentlyContinue)) {
                    New-Website -Name $redirect -Port 80 -IPAddress '*' -HostHeader $fqdn `
                        -PhysicalPath $dirRedirect -ErrorAction Stop | Out-Null
                }
                Set-WebConfigurationProperty -PSPath "IIS:\Sites\$redirect" -Filter 'system.webServer/httpRedirect' `
                    -Name enabled -Value $true -ErrorAction Stop
                Set-WebConfigurationProperty -PSPath "IIS:\Sites\$redirect" -Filter 'system.webServer/httpRedirect' `
                    -Name destination -Value ('https://'+$fqdn) -ErrorAction Stop
                Set-WebConfigurationProperty -PSPath "IIS:\Sites\$redirect" -Filter 'system.webServer/httpRedirect' `
                    -Name exactDestination -Value $true -ErrorAction Stop
                Set-WebConfigurationProperty -PSPath "IIS:\Sites\$redirect" -Filter 'system.webServer/httpRedirect' `
                    -Name httpResponseStatus -Value 'Permanent' -ErrorAction Stop
                # Liberar apenas HTTP/HTTPS da rede corporativa de clientes. A DMZ nao deve ficar aberta ao mundo.
                $redes=@('10.20.30.0/24','10.20.40.0/24','10.20.50.0/24','10.20.60.0/24',
                    '10.20.70.0/24','10.20.80.0/24','10.20.90.0/24')
                # Remove regras largas automaticas do IIS que nao possuem filtro por origem.
                Get-NetFirewallRule -DisplayGroup 'World Wide Web Services (HTTP)' -ErrorAction SilentlyContinue |
                    Disable-NetFirewallRule -ErrorAction SilentlyContinue | Out-Null
                Get-NetFirewallRule -DisplayGroup 'World Wide Web Services (HTTPS)' -ErrorAction SilentlyContinue |
                    Disable-NetFirewallRule -ErrorAction SilentlyContinue | Out-Null
                Get-NetFirewallRule -Name 'IIS-WebServerRole-HTTP-In-TCP','IIS-WebServerRole-HTTPS-In-TCP' `
                    -ErrorAction SilentlyContinue | Disable-NetFirewallRule -ErrorAction SilentlyContinue | Out-Null
                foreach($r in @('SF-Intranet-HTTP-Corporativo','SF-Intranet-HTTPS-Corporativo')) {
                    Get-NetFirewallRule -DisplayName $r -ErrorAction SilentlyContinue |
                        Remove-NetFirewallRule -ErrorAction SilentlyContinue | Out-Null
                }
                New-NetFirewallRule -DisplayName 'SF-Intranet-HTTP-Corporativo' -Direction Inbound `
                    -Action Allow -Protocol TCP -LocalPort 80 -RemoteAddress $redes -Profile Domain -ErrorAction Stop | Out-Null
                New-NetFirewallRule -DisplayName 'SF-Intranet-HTTPS-Corporativo' -Direction Inbound `
                    -Action Allow -Protocol TCP -LocalPort 443 -RemoteAddress $redes -Profile Domain -ErrorAction Stop | Out-Null
                # Acesso RDP preparado para futura PAW: NLA + regra exclusiva do IP 10.20.90.10.
                Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' `
                    -Name fDenyTSConnections -Value 0 -ErrorAction Stop
                Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
                    -Name UserAuthentication -Value 1 -ErrorAction Stop
                Get-NetFirewallRule -DisplayName 'SF-RDP-PAW' -ErrorAction SilentlyContinue |
                    Remove-NetFirewallRule -ErrorAction SilentlyContinue | Out-Null
                New-NetFirewallRule -DisplayName 'SF-RDP-PAW' -Direction Inbound -Action Allow -Protocol TCP `
                    -LocalPort 3389 -RemoteAddress '10.20.90.10' -Profile Domain -ErrorAction Stop | Out-Null
                if ((Get-Website -Name $site).State -ne 'Started') { Start-Website -Name $site -ErrorAction Stop }
                if ((Get-Website -Name $redirect).State -ne 'Started') { Start-Website -Name $redirect -ErrorAction Stop }
                "IIS_CONFIGURADO=TRUE; HTTPS=$fqdn; CERT_THUMBPRINT=$($cert.Thumbprint); AUTH=Windows; REDIRECT=301"
            }
            GravarResultado $out
            # DNS e SPN devem ser configurados no DC01 com credencial de dominio.
            $credDC=Get-Credential -Message 'SMARTFACTORY\Administrator para criar CNAME e SPN no DC01'
            $dc=Invoke-Command -VMName 'VM-DC01' -Credential $credDC -ErrorAction Stop -ScriptBlock {
                $ErrorActionPreference='Stop'
                Import-Module DnsServer,ActiveDirectory -ErrorAction Stop
                $zone='smartfactory.corp'
                $fqdn='intranet.smartfactory.corp'
                $a=Get-DnsServerResourceRecord -ZoneName $zone -Name 'vm-web01' -RRType A -ErrorAction SilentlyContinue
                if (-not $a) {
                    Add-DnsServerResourceRecordA -ZoneName $zone -Name 'vm-web01' -IPv4Address '10.20.100.10' -ErrorAction Stop
                } elseif (-not @($a | Where-Object { $_.RecordData.IPv4Address.ToString() -eq '10.20.100.10' }).Count) {
                    throw 'Registro A de vm-web01 existe, mas aponta para IP diferente de 10.20.100.10.'
                }
                $alias=Get-DnsServerResourceRecord -ZoneName $zone -Name 'intranet' -RRType CNAME -ErrorAction SilentlyContinue
                if (-not $alias) {
                    Add-DnsServerResourceRecordCName -ZoneName $zone -Name 'intranet' `
                        -HostNameAlias 'vm-web01.smartfactory.corp' -ErrorAction Stop
                } elseif ($alias.RecordData.HostNameAlias.ToString().TrimEnd('.') -ine 'vm-web01.smartfactory.corp') {
                    throw 'CNAME intranet existente aponta para host inesperado.'
                }
                $ptr=Get-DnsServerResourceRecord -ZoneName '20.10.in-addr.arpa' -Name '10.100' `
                    -RRType PTR -ErrorAction SilentlyContinue
                if (-not $ptr) {
                    Add-DnsServerResourceRecordPtr -ZoneName '20.10.in-addr.arpa' -Name '10.100' `
                        -PtrDomainName 'vm-web01.smartfactory.corp' -ErrorAction Stop
                }
                $computer=Get-ADComputer -Identity 'VM-WEB01' -Properties ServicePrincipalName -ErrorAction Stop
                $spn='HTTP/intranet.smartfactory.corp'
                $outros=@(Get-ADObject -LDAPFilter "(servicePrincipalName=$spn)" -Properties servicePrincipalName)
                if (@($outros | Where-Object DistinguishedName -ne $computer.DistinguishedName).Count -gt 0) {
                    throw 'SPN HTTP/intranet esta registrado em outra conta. Corrija duplicidade antes de continuar.'
                }
                if ($spn -notin @($computer.ServicePrincipalName)) {
                    Set-ADComputer -Identity $computer -Add @{servicePrincipalName=$spn} -ErrorAction Stop
                }
                "DNS_A=10.20.100.10; CNAME=$fqdn; SPN=$spn; TARGET=VM-WEB01"
            }
            GravarResultado $dc
            Log 'CONFIGURAR IIS CONCLUIDO. Certificado AUTOASSINADO: testes de cliente exigem confiar no certificado.'
        }
        'Validar' {
            VerificarInfra
            $vm=Get-VM -Name $VmName -ErrorAction Stop
            if ($vm.State -ne 'Running') { throw 'VM-WEB01 nao esta ligada.' }
            $nic=Get-VMNetworkAdapterVlan -VMName $VmName -VMNetworkAdapterName DMZ -ErrorAction Stop
            if ($nic.OperationMode -ne 'Access' -or $nic.AccessVlanId -ne 100) { throw 'WEB01 nao esta na VLAN Access 100.' }
            $mem=Get-VMMemory -VMName $VmName
            $vmChecks=($vm.Generation -eq 2 -and $mem.DynamicMemoryEnabled)
            $cred=CredencialConvidado
            $out=Invoke-Command -VMName $VmName -Credential $cred -ErrorAction Stop -ScriptBlock {
                $ErrorActionPreference='Stop'
                Import-Module WebAdministration -ErrorAction Stop
                $os=Get-CimInstance Win32_OperatingSystem
                $cs=Get-CimInstance Win32_ComputerSystem
                $ip=Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object IPAddress -eq '10.20.100.10' | Select-Object -First 1
                $site=Get-Website -Name 'SF-Intranet' -ErrorAction Stop
                $redirect=Get-Website -Name 'SF-HTTP-Redirect' -ErrorAction Stop
                $binding=@(Get-WebBinding -Name 'SF-Intranet' -Protocol https | Where-Object {
                    $_.bindingInformation -eq '*:443:intranet.smartfactory.corp'
                })
                $https=@(Get-WebBinding -Name 'SF-Intranet' -Protocol https)
                $isAnon=(Get-WebConfigurationProperty -PSPath 'IIS:\Sites\SF-Intranet' `
                    -Filter 'system.webServer/security/authentication/anonymousAuthentication' -Name enabled).Value
                $isWin=(Get-WebConfigurationProperty -PSPath 'IIS:\Sites\SF-Intranet' `
                    -Filter 'system.webServer/security/authentication/windowsAuthentication' -Name enabled).Value
                $r301=(Get-WebConfigurationProperty -PSPath 'IIS:\Sites\SF-HTTP-Redirect' `
                    -Filter 'system.webServer/httpRedirect' -Name httpResponseStatus)
                $tls=Get-ChildItem 'Cert:\LocalMachine\My' | Where-Object {
                    $_.Subject -eq 'CN=intranet.smartfactory.corp' -and $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date)
                } | Select-Object -First 1
                $pool=Get-WebAppPoolState -Name 'SF-Intranet-Pool'
                $rules=@(Get-NetFirewallRule -DisplayName 'SF-Intranet-*' -ErrorAction SilentlyContinue |
                    Where-Object Enabled -eq 'True')
                $ok=(
                    $os.Caption -match '2025' -and
                    $cs.Domain -eq 'smartfactory.corp' -and $cs.PartOfDomain -and
                    $env:COMPUTERNAME -eq 'VM-WEB01' -and
                    $null -ne $ip -and $site.State -eq 'Started' -and $redirect.State -eq 'Started' -and
                    $binding.Count -eq 1 -and $https.Count -ge 1 -and
                    $isWin -eq $true -and $isAnon -eq $false -and
                    $null -ne $tls -and $pool.Value -eq 'Started' -and $rules.Count -ge 2 -and
                    "$r301" -match 'Permanent|301'
                )
                [pscustomobject]@{Aprovado=$ok;Hostname=$env:COMPUTERNAME;Dominio=$cs.Domain;
                    IP=$ip.IPAddress;HTTPSBindings=$binding.Count;AutenticacaoWindows=$isWin;
                    AnonimaHabilitada=$isAnon;Redirect301=$r301;CertValido=[bool]$tls;
                    AppPool=$pool.Value;FirewallRules=$rules.Count}
            }
            GravarResultado $out
            $guestOK=@($out | Where-Object { $_.PSObject.Properties['Aprovado'] -and $_.Aprovado -eq $true }).Count -gt 0
            $credDC=Get-Credential -Message 'SMARTFACTORY\Administrator DC01 para validar CNAME e SPN'
            $dns=Invoke-Command -VMName 'VM-DC01' -Credential $credDC -ErrorAction Stop -ScriptBlock {
                Import-Module DnsServer,ActiveDirectory -ErrorAction Stop
                $al=Get-DnsServerResourceRecord -ZoneName smartfactory.corp -Name intranet -RRType CNAME -ErrorAction Stop
                $pc=Get-ADComputer -Identity VM-WEB01 -Properties ServicePrincipalName -ErrorAction Stop
                [pscustomobject]@{AliasCorreto=($al.RecordData.HostNameAlias.ToString().TrimEnd('.') -ieq 'vm-web01.smartfactory.corp');
                    SPNExiste=('HTTP/intranet.smartfactory.corp' -in @($pc.ServicePrincipalName));
                    OU=$pc.DistinguishedName}
            }
            GravarResultado $dns
            $dnsOK=@($dns | Where-Object { $_.AliasCorreto -and $_.SPNExiste -and $_.OU -like '*OU=Web_Servers,*' }).Count -gt 0
            Log "HyperV_OK=$vmChecks, IIS_OK=$guestOK, DNS_SPN_OK=$dnsOK"
            if (Test-Path -LiteralPath $ReportPath) {
                Add-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"

## Validacao - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
- Hyper-V: $vmChecks.
- IIS/Windows Authentication/HTTPS: $guestOK.
- CNAME/SPN/OU no AD: $dnsOK.
- Log: 09-Logs-Testes/08-WEB01-IIS-Intranet-Resultado.txt.
- Testes autenticados com navegador do cliente: aguardando CLI-ADM01.
- TLS1.3 somente: NAO foi imposto globalmente (compatibilidade Schannel).
"@
            }
            if (-not ($vmChecks -and $guestOK -and $dnsOK)) {
                throw 'VALIDACAO FALHOU: veja detalhes no log. Nao avance sem corrigir.'
            }
            Log 'VALIDACAO APROVADA (estrutura Hyper-V, IIS, DNS e SPN). Teste SSO cliente pendente.'
        }
    }
}
catch {
    Log ('ERRO: '+$_.Exception.Message)
    throw
}

