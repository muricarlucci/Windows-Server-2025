# SmartFactory - Etapa 02 - Provisionamento da VM-FW01
# Executar no Windows PowerShell 5.1 como Administrador.
# Nao inicializa a VM, nao muda a rede fisica e nao altera switches existentes.
$ErrorActionPreference = 'Stop'
$root = 'D:\FIAP\WINDOWS\SmartFactory-GS'
$isos = Join-Path $root '01-ISOs'
$vmDir = Join-Path $root '02-VMs\VM-FW01'
$logs = Join-Path $root '09-Logs-Testes'
$docs = Join-Path $root '00-Documentacao'
$nomeVM = 'VM-FW01'
$vhd = Join-Path $vmDir 'VM-FW01-SO.vhdx'

$admin = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Abra o PowerShell como Administrador.' }
foreach ($p in @($root,$isos)) { if (-not (Test-Path -LiteralPath $p)) { throw "Pasta inexistente: $p" } }
Import-Module Hyper-V -ErrorAction Stop
Get-VMHost -ErrorAction Stop | Out-Null
if (Get-VM -Name $nomeVM -ErrorAction SilentlyContinue) { throw "A VM $nomeVM ja existe. Nao sera alterada automaticamente." }
foreach ($sw in @('Default Switch','SF-LAN')) { if (-not (Get-VMSwitch -Name $sw -ErrorAction SilentlyContinue)) { throw "Switch '$sw' nao encontrado." } }
if ((Get-VMSwitch -Name 'SF-LAN').SwitchType -ne 'Internal') { throw 'SF-LAN nao e um switch interno.' }
$hostIP = Get-NetIPAddress -InterfaceAlias 'vEthernet (SF-LAN)' -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress -eq '10.20.10.10' -and $_.PrefixLength -eq 24 } | Select-Object -First 1
if (-not $hostIP) { throw 'IP 10.20.10.10/24 nao configurado na SF-LAN.' }
if ($hostIP.AddressState -ne 'Preferred') { throw "O IP do host esta em estado '$($hostIP.AddressState)', nao Preferred. Aguarde e investigue antes de prosseguir." }
$volume = Get-PSDrive -Name D -ErrorAction Stop
if ($volume.Free -lt 30GB) { throw 'Menos de 30 GB livres em D:. Libere espaco antes de prosseguir.' }
New-Item -ItemType Directory -Force -Path $vmDir,$logs,$docs | Out-Null

# Localizar ISO ja extraida ou descompactar a ISO oficial baixada (.iso.gz).
$iso = Get-ChildItem -LiteralPath $isos -File -Filter 'netgate-installer-*-amd64.iso' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$gz = Get-ChildItem -LiteralPath $isos -File -Filter 'netgate-installer-*-amd64.iso.gz' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $iso -and -not $gz) { throw "Netgate Installer .iso ou .iso.gz nao encontrado em $isos" }
# SHA256 oficial da Netgate para netgate-installer-v1.2-RELEASE-amd64.iso.gz.
if ($gz -and $gz.Name -eq 'netgate-installer-v1.2-RELEASE-amd64.iso.gz') {
    $shaEsperado = '184514FE7DF0D339362C1E33FA051C464577A450528759B343ADE894C7C57955'
    $shaAtual = (Get-FileHash -LiteralPath $gz.FullName -Algorithm SHA256).Hash
    if ($shaAtual -ne $shaEsperado) { throw 'SHA256 do instalador Netgate v1.2 diferente do oficial. Nao prossiga.' }
    Write-Host 'SHA256 do instalador Netgate v1.2 validado.' -ForegroundColor Green
} elseif ($gz) {
    Write-Warning 'Versao da ISO nao possui checksum fixado no script: compare manualmente com a Netgate.'
} else {
    Write-Warning 'Somente ISO descompactada encontrada: integridade do arquivo comprimido nao validada.'
}
if (-not $iso) {
    $destISO = Join-Path $isos ($gz.Name -replace '\.gz$','')
    if (Test-Path -LiteralPath $destISO) { throw "Arquivo ISO inesperado ja existe: $destISO" }
    Write-Host "Descompactando $($gz.Name)..."
    $entrada = [System.IO.File]::OpenRead($gz.FullName)
    $saida = $null; $gzip = $null
    try {
        $gzip = [System.IO.Compression.GZipStream]::new($entrada,[System.IO.Compression.CompressionMode]::Decompress)
        $saida = [System.IO.File]::Create($destISO)
        $gzip.CopyTo($saida)
    } catch {
        if ($saida) { $saida.Dispose(); $saida = $null }
        if (Test-Path -LiteralPath $destISO) { Remove-Item -LiteralPath $destISO -Force }
        throw
    } finally {
        if ($saida) { $saida.Dispose() }
        if ($gzip) { $gzip.Dispose() }
        $entrada.Dispose()
    }
    $iso = Get-Item -LiteralPath $destISO
}
if ($iso.Length -lt 10MB) { throw 'ISO muito pequena. Verifique a integridade do download.' }

# Criacao de disco VHDX dinamico e VM Generation 2.
Write-Host 'Criando VM-FW01 no disco D: ...'
New-VM -Name $nomeVM -Generation 2 -MemoryStartupBytes 2GB `
    -SwitchName 'Default Switch' -Path $vmDir `
    -NewVHDPath $vhd -NewVHDSizeBytes 16GB | Out-Null
Set-VMProcessor -VMName $nomeVM -Count 2
Set-VMMemory -VMName $nomeVM -DynamicMemoryEnabled $false
Set-VM -Name $nomeVM -AutomaticStartAction Nothing -AutomaticStopAction ShutDown -CheckpointType Disabled
$adaptadorWAN = Get-VMNetworkAdapter -VMName $nomeVM | Select-Object -First 1
Rename-VMNetworkAdapter -VMName $nomeVM -Name $adaptadorWAN.Name -NewName 'WAN'
Add-VMNetworkAdapter -VMName $nomeVM -Name 'LAN' -SwitchName 'SF-LAN'
Set-VMNetworkAdapterVlan -VMName $nomeVM -VMNetworkAdapterName 'WAN' -Untagged
Set-VMNetworkAdapterVlan -VMName $nomeVM -VMNetworkAdapterName 'LAN' -Trunk `
    -NativeVlanId 10 -AllowedVlanIdList '10,20,30,40,50,60,70,80,90,100,110,120,999'
Set-VMFirmware -VMName $nomeVM -EnableSecureBoot Off
$dvd = Get-VMDvdDrive -VMName $nomeVM | Select-Object -First 1
if (-not $dvd) { Add-VMDvdDrive -VMName $nomeVM -Path $iso.FullName; $dvd = Get-VMDvdDrive -VMName $nomeVM | Select-Object -First 1 }
else { Set-VMDvdDrive -VMName $nomeVM -Path $iso.FullName }
Set-VMFirmware -VMName $nomeVM -FirstBootDevice $dvd

# Evidencias: PowerShell + relatorio academico (provisionada != instalada).
$vm = Get-VM -Name $nomeVM
$nic = Get-VMNetworkAdapter -VMName $nomeVM
$vlanInfo = Get-VMNetworkAdapterVlan -VMName $nomeVM
$hashComprimido = if ($gz) { (Get-FileHash -LiteralPath $gz.FullName -Algorithm SHA256).Hash } else { 'Arquivo .gz nao localizado' }
$hashISO = (Get-FileHash -LiteralPath $iso.FullName -Algorithm SHA256).Hash
$log = Join-Path $logs '03-Provisionamento-VM-FW01.txt'
@(
    "SmartFactory Etapa 02 - $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
    'STATUS: VM CRIADA / INSTALACAO DO PFSENSE PENDENTE'
    "ISO: $($iso.FullName)"
    "SHA256 comprimido: $hashComprimido"
    "SHA256 ISO: $hashISO"
    "VHDX: $vhd"
    ($vm | Select-Object Name,State,Generation,Path,MemoryStartup | Format-List | Out-String)
    ($nic | Select-Object Name,SwitchName,MacAddress | Format-Table -AutoSize | Out-String)
    ($vlanInfo | Format-Table -AutoSize | Out-String)
    (Get-VMFirmware -VMName $nomeVM | Select-Object SecureBoot,SecureBootTemplate | Format-List | Out-String)
    "D: livre GB: $([math]::Round((Get-PSDrive D).Free / 1GB,2))"
) | Set-Content -LiteralPath $log -Encoding UTF8
$documento = Join-Path $docs '02-VM-FW01-PfSense.md'
@"
# SmartFactory - Etapa 02: VM-FW01 (pfSense CE)

Data de provisionamento: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

## Estado
- VM criada no Hyper-V; **instalacao do pfSense ainda nao validada**.
- ISO: $($iso.Name).
- SO previsto: pfSense Community Edition, versao a registrar apos instalacao.
- VM: VM-FW01, Geracao 2, 2 vCPU, 2 GiB RAM estatica, VHDX dinamico de 16 GiB.
- WAN: Default Switch (DHCP/NAT do Hyper-V).
- LAN: SF-LAN, trunk 802.1Q; VLAN 10 nativa, demais VLANs permitidas para implementacao posterior.
- LAN a configurar no pfSense: 10.20.10.1/24; host Windows: 10.20.10.10/24 (VLAN 10).
- Secure Boot: desativado somente nesta VM, conforme guia Netgate Hyper-V.
- O switch FIAP e os adaptadores fisicos nao foram modificados.
- Pasta de VM: $vmDir.
- Log de provisionamento: $log.

## Pendente apos provisionamento
- Iniciar instalador na console; confirmar pfSense CE, instalacao no VHDX, WAN DHCP.
- Atribuir interfaces de WAN e LAN pelos MACs, alterar LAN para 10.20.10.1/24.
- Testar HTTPS e conectividade; trocar senha administrativa padrao; remover ISO de boot.
- Coletar evidencias e gravar video da instalacao, com omissao de senhas na captura.

## Limites da demonstracao
- A segmentacao das demais VLANs e as regras inter-VLAN nao foram configuradas nesta etapa.
- A WAN usa NAT do Windows 11 e nao e uma interface de firewall perimetral fisica.
- Esta VM e um laboratorio em um unico host, sem tolerancia a falha fisica.
"@ | Set-Content -LiteralPath $documento -Encoding UTF8
Write-Host "VM-FW01 criada (DESLIGADA)." -ForegroundColor Green
Write-Host "ISO: $($iso.FullName)"
Write-Host "Log: $log"
Write-Host "Relatorio: $documento"
Write-Host "Confira a autenticidade da ISO com o SHA256 oficial da Netgate antes de instalar."
