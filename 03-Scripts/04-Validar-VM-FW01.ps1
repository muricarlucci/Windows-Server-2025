
# SmartFactory - Etapa 02 - Validacao da VM-FW01
# Executar no Windows PowerShell como Administrador.
# Nao modifica a configuracao da VM.

$ErrorActionPreference = 'Stop'

$base = 'D:\FIAP\WINDOWS\SmartFactory-GS'
$logs = Join-Path $base '09-Logs-Testes'
$nome = 'VM-FW01'
$ip = '10.20.10.1'

New-Item -ItemType Directory -Path $logs -Force |
    Out-Null

Import-Module Hyper-V -ErrorAction Stop

$vm = Get-VM -Name $nome -ErrorAction SilentlyContinue

if (-not $vm) {
    throw 'VM-FW01 nao encontrada no Hyper-V.'
}

$adaptadores = Get-VMNetworkAdapter -VMName $nome
$vlans = Get-VMNetworkAdapterVlan -VMName $nome
$firmware = Get-VMFirmware -VMName $nome
$processador = Get-VMProcessor -VMName $nome
$memoria = Get-VMMemory -VMName $nome
$discos = Get-VMHardDiskDrive -VMName $nome

$interfaceHost = Get-NetIPAddress `
    -InterfaceAlias 'vEthernet (SF-LAN)' `
    -AddressFamily IPv4 `
    -ErrorAction SilentlyContinue |
    Where-Object IPAddress -eq '10.20.10.10'

$web = Test-NetConnection `
    -ComputerName $ip `
    -Port 443 `
    -WarningAction SilentlyContinue

$internetHost = Test-NetConnection `
    -ComputerName '1.1.1.1' `
    -Port 443 `
    -WarningAction SilentlyContinue

$log = Join-Path $logs '04-Validacao-PfSense.txt'

$relatorio = @(
    "SMARTFACTORY - VALIDACAO DA VM-FW01"
    "Data: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    ""
    "=== MAQUINA VIRTUAL ==="
    "Nome: $($vm.Name)"
    "Estado: $($vm.State)"
    "Geracao: $($vm.Generation)"
    "CPUs virtuais: $($processador.Count)"
    "RAM inicial (GB): $([math]::Round($memoria.Startup / 1GB, 2))"
    "Memoria dinamica: $($memoria.DynamicMemoryEnabled)"
    "Secure Boot: $($firmware.SecureBoot)"
    ""
    "=== INTERFACE DO HOST ==="
    "IP: $($interfaceHost.IPAddress)"
    "Prefixo: $($interfaceHost.PrefixLength)"
    "Estado: $($interfaceHost.AddressState)"
    ""
    "=== CONECTIVIDADE ==="
    "HTTPS pfSense ($ip): $($web.TcpTestSucceeded)"
    "Internet do WINDOWS: $($internetHost.TcpTestSucceeded)"
    "OBS: o teste externo nao comprova Internet na WAN do pfSense."
    ""
    "=== ADAPTADORES VIRTUAIS ==="
    ($adaptadores |
        Select-Object Name, SwitchName, MacAddress |
        Format-Table -AutoSize | Out-String)
    ""
    "=== CONFIGURACAO DE VLAN ==="
    ($vlans | Format-List | Out-String)
    ""
    "=== DISCOS VIRTUAIS ==="
    ($discos |
        Select-Object ControllerType, Path |
        Format-Table -AutoSize | Out-String)
    ""
    "=== VALIDACAO MANUAL PENDENTE ==="
    "1. Confirmar acesso e login no painel web."
    "2. Confirmar WAN IPv4 e conectividade do pfSense."
    "3. Confirmar LAN 10.20.10.1/24."
    "4. Confirmar DHCP desabilitado na LAN."
    "5. Confirmar alteracao da senha administrativa."
    "6. Registrar a versao instalada do pfSense CE."
)

$relatorio |
    Set-Content -LiteralPath $log -Encoding UTF8

Get-Content -LiteralPath $log

Write-Host ""
Write-Host "Resultado salvo em: $log" -ForegroundColor Green

$doc = Join-Path $base '00-Documentacao\02-VM-FW01-PfSense.md'

if (Test-Path -LiteralPath $doc) {

    $resultado = if ($web.TcpTestSucceeded) {
        'TCP 443 acessivel; confirmar login manualmente.'
    }
    else {
        'TCP 443 inacessivel; investigar conectividade.'
    }

    Add-Content -LiteralPath $doc -Encoding UTF8 -Value @"

## Verificacao automatizada - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

- Estado da VM: $($vm.State).
- IP do host: $($interfaceHost.IPAddress).
- Estado do IP: $($interfaceHost.AddressState).
- HTTPS pfSense: $resultado
- Internet do Windows: $($internetHost.TcpTestSucceeded).
- Log: 09-Logs-Testes/04-Validacao-PfSense.txt.
- Versao do pfSense e conectividade WAN: validar manualmente.
"@

    Write-Host "Documentacao atualizada: $doc" -ForegroundColor Green
}
