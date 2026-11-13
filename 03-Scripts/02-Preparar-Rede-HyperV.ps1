
# SMARTFACTORY - PREPARACAO DA REDE HYPER-V
# Executar como Administrador.
# Nao altera Wi-Fi, Ethernet fisico ou Default Switch.

$ErrorActionPreference = "Stop"

$base = "D:\FIAP\WINDOWS\SmartFactory-GS"
$logs = Join-Path $base "09-Logs-Testes"

$nomeSwitch = "SF-LAN"
$alias = "vEthernet ($nomeSwitch)"
$ipHost = "10.20.10.10"
$prefixo = 24
$vlan = 10

if (!(Test-Path $base)) {
    throw "Pasta principal SmartFactory-GS nao encontrada."
}

New-Item -ItemType Directory -Path $logs -Force |
    Out-Null

# 1. Verificar permissao administrativa.

$identidade = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identidade)

if (!$principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    throw "Execute o PowerShell como Administrador."
}

# 2. Validar Hyper-V.

Get-VMHost -ErrorAction Stop | Out-Null

Write-Host "Hyper-V acessivel." -ForegroundColor Green

# 3. Verificar conflitos antes de criar o switch.

$ipExistente = Get-NetIPAddress `
    -AddressFamily IPv4 `
    -IPAddress $ipHost `
    -ErrorAction SilentlyContinue

if ($ipExistente -and
    $ipExistente.InterfaceAlias -ne $alias) {
    throw "O IP $ipHost ja pertence a outra interface."
}

$rotaExistente = Get-NetRoute `
    -AddressFamily IPv4 `
    -DestinationPrefix "10.20.10.0/24" `
    -ErrorAction SilentlyContinue |
    Where-Object InterfaceAlias -ne $alias

if ($rotaExistente) {
    throw "Ja existe uma rota para 10.20.10.0/24 em outra interface."
}

# 4. Criar ou validar o switch interno.

$switch = Get-VMSwitch -Name $nomeSwitch `
    -ErrorAction SilentlyContinue

if (!$switch) {
    New-VMSwitch `
        -Name $nomeSwitch `
        -SwitchType Internal `
        -Notes "Rede interna SmartFactory - laboratorio" |
        Out-Null

    Write-Host "Switch SF-LAN criado." -ForegroundColor Green
}
elseif ($switch.SwitchType -ne "Internal") {
    throw "SF-LAN existe, mas nao e um switch interno."
}
else {
    Write-Host "Switch SF-LAN ja existe."
}

# 5. Aguardar o adaptador virtual aparecer.

$adaptador = $null

for ($i = 0; $i -lt 15; $i++) {
    $adaptador = Get-NetAdapter -Name $alias `
        -ErrorAction SilentlyContinue

    if ($adaptador) { break }

    Start-Sleep -Seconds 1
}

if (!$adaptador) {
    throw "Adaptador virtual SF-LAN nao encontrado."
}

# 6. Configurar VLAN de gerenciamento.

Set-VMNetworkAdapterVlan `
    -ManagementOS `
    -VMNetworkAdapterName $nomeSwitch `
    -Access `
    -VlanId $vlan

Write-Host "VLAN 10 configurada." -ForegroundColor Green

# 7. Configurar IPv4 estatico.

$ipConfigurado = Get-NetIPAddress `
    -InterfaceAlias $alias `
    -AddressFamily IPv4 `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.IPAddress -eq $ipHost -and
        $_.PrefixLength -eq $prefixo
    }

if (!$ipConfigurado) {
    New-NetIPAddress `
        -InterfaceAlias $alias `
        -IPAddress $ipHost `
        -PrefixLength $prefixo |
        Out-Null

    Write-Host "IP $ipHost configurado." -ForegroundColor Green
}
else {
    Write-Host "IP $ipHost ja configurado."
}

# 8. Gerar evidencias.

$arquivo = Join-Path $logs "02-Rede-HyperV.txt"

$relatorio = @(
    "SMARTFACTORY - REDE HYPER-V"
    "Data: $(Get-Date)"
    ""
    "=== SWITCHES ==="
    (Get-VMSwitch |
        Select-Object Name, SwitchType |
        Format-Table -AutoSize | Out-String)
    "=== VLAN DO HOST ==="
    (Get-VMNetworkAdapterVlan `
        -ManagementOS `
        -VMNetworkAdapterName $nomeSwitch |
        Format-List | Out-String)
    "=== IPv4 SF-LAN ==="
    (Get-NetIPAddress `
        -InterfaceAlias $alias `
        -AddressFamily IPv4 |
        Format-Table -AutoSize | Out-String)
    "=== GATEWAYS SF-LAN ==="
    (Get-NetRoute `
        -InterfaceAlias $alias `
        -AddressFamily IPv4 `
        -ErrorAction SilentlyContinue |
        Where-Object DestinationPrefix -eq "0.0.0.0/0" |
        Format-Table | Out-String)
)

$relatorio | Set-Content `
    -Path $arquivo `
    -Encoding UTF8

$relatorio | ForEach-Object { Write-Host $_ }

Write-Host ""
Write-Host "Configuracao finalizada." -ForegroundColor Green
Write-Host "Relatorio: $arquivo"
Write-Host "Nenhuma maquina virtual foi criada."
