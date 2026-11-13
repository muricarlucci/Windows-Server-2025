
$ErrorActionPreference = "Stop"

$base = "D:\FIAP\WINDOWS\SmartFactory-GS"
$logs = Join-Path $base "09-Logs-Testes"

if (!(Test-Path $base)) {
    throw "Pasta principal SmartFactory-GS nao encontrada."
}

New-Item -ItemType Directory -Path $logs -Force |
    Out-Null

$arquivo = Join-Path $logs "01-Diagnostico-HyperV.txt"

$relatorio = @()

$relatorio += "SMARTFACTORY - DIAGNOSTICO HYPER-V"
$relatorio += "Data: $(Get-Date)"
$relatorio += ""

$relatorio += "=== WINDOWS ==="
$os = Get-CimInstance Win32_OperatingSystem
$relatorio += $os.Caption
$relatorio += "Build: $($os.BuildNumber)"
$relatorio += ""

$relatorio += "=== RECURSOS HYPER-V ==="
$relatorio += (
    Get-WindowsOptionalFeature -Online |
    Where-Object FeatureName -like "*Hyper-V*" |
    Select-Object FeatureName, State |
    Format-Table -AutoSize | Out-String
)

$relatorio += "=== SERVICOS ==="
$relatorio += (
    Get-Service vmms, vmcompute -ErrorAction SilentlyContinue |
    Select-Object Name, Status, StartType |
    Format-Table -AutoSize | Out-String
)

$relatorio += "=== HOST HYPER-V ==="

try {
    $relatorio += (
        Get-VMHost -ErrorAction Stop |
        Select-Object ComputerName,
            VirtualHardDiskPath,
            VirtualMachinePath |
        Format-List | Out-String
    )
}
catch {
    $relatorio += "ERRO: $($_.Exception.Message)"
}

$relatorio += "=== SWITCHES EXISTENTES ==="

try {
    $relatorio += (
        Get-VMSwitch -ErrorAction Stop |
        Select-Object Name, SwitchType, NetAdapterInterfaceDescription |
        Format-Table -AutoSize | Out-String
    )
}
catch {
    $relatorio += "ERRO: $($_.Exception.Message)"
}

$relatorio += "=== ENDERECOS IPv4 ==="
$relatorio += (
    Get-NetIPAddress -AddressFamily IPv4 |
    Select-Object InterfaceAlias, IPAddress, PrefixLength |
    Format-Table -AutoSize | Out-String
)

$relatorio += "=== ROTAS PRIVADAS ==="
$relatorio += (
    Get-NetRoute -AddressFamily IPv4 |
    Where-Object {
        $_.DestinationPrefix -like "10.*"
    } |
    Select-Object InterfaceAlias,
        DestinationPrefix,
        NextHop |
    Format-Table -AutoSize | Out-String
)

$relatorio += "=== ARMAZENAMENTO ==="
$relatorio += (
    Get-PSDrive -PSProvider FileSystem |
    Select-Object Name,
        @{N="LivreGB";E={[math]::Round($_.Free / 1GB,1)}} |
    Format-Table -AutoSize | Out-String
)

$relatorio | Set-Content -Path $arquivo -Encoding UTF8

$relatorio | ForEach-Object { Write-Host $_ }

Write-Host ""
Write-Host "Relatorio salvo em: $arquivo"
