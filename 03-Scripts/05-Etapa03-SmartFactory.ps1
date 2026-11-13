# SmartFactory - Etapa 03 - Rede e Firewall
# Windows PowerShell 5.1 (Administrador)
# Uso: -Acao Gerar | MigrarTrunk | Validar | ReverterTrunk
# Nao modifica o XML original nem aplica configuracoes no pfSense automaticamente.
[CmdletBinding()]
param(
    [ValidateSet('Gerar','MigrarTrunk','Validar','ReverterTrunk')]
    [string]$Acao = 'Gerar',
    [string]$XmlOrigem = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Base = 'D:\FIAP\WINDOWS\SmartFactory-GS'
$ConfigDir = Join-Path $Base '04-Configuracoes\pfSense'
$NovoXml = Join-Path $ConfigDir 'config-SmartFactory-Etapa03-IMPORTAR.xml'
$Backup = Join-Path $ConfigDir 'backup-ANTES-Etapa03.xml'
$Log = Join-Path $Base '09-Logs-Testes\05-Etapa03-Resultado.txt'
$Relatorio = Join-Path $Base '00-Documentacao\03-Rede-Firewall.md'
$Roteiro = Join-Path $Base '07-Video\Roteiros\Roteiro_Video_Etapa_4.txt'
$TrunkVlans = '10,20,30,40,50,60,70,80,90,99,100,110,120,999'

function Logar([string]$Linha) {
    $s = ('{0} | {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Linha)
    Add-Content -LiteralPath $Log -Value $s -Encoding UTF8
    Write-Host $s
}

function Filho([System.Xml.XmlNode]$Pai,[string]$Nome,[AllowNull()][string]$Valor=$null) {
    $el = $script:Doc.CreateElement($Nome)
    if ($null -ne $Valor) { $el.InnerText = $Valor }
    [void]$Pai.AppendChild($el)
    return $el
}

function RemoverSeHouver([System.Xml.XmlNode]$Pai,[string]$Nome) {
    $el = $Pai.SelectSingleNode($Nome)
    if ($null -ne $el) { [void]$Pai.RemoveChild($el) }
}

function DefinirTexto([System.Xml.XmlNode]$Pai,[string]$Nome,[string]$Valor) {
    $el = $Pai.SelectSingleNode($Nome)
    if ($null -eq $el) { $el = Filho $Pai $Nome }
    $el.InnerText = $Valor
}

function NovoAlias([string]$Nome,[string]$Tipo,[string]$Enderecos,[string]$Descricao) {
    $n = Filho $script:Aliases 'alias'
    [void](Filho $n 'name' $Nome)
    [void](Filho $n 'type' $Tipo)
    [void](Filho $n 'address' $Enderecos)
    [void](Filho $n 'descr' $Descricao)
}

function NovaRegra {
    param(
        [string]$Interface,[string]$Descricao,[string]$Origem,[string]$Destino,
        [ValidateSet('pass','block')][string]$AcaoRegra = 'pass',
        [ValidateSet('any','tcp','udp','tcp/udp','icmp')][string]$Protocolo = 'tcp',
        [string]$Porta = '',
        [switch]$InverterDestino
    )
    $r = Filho $script:Filtro 'rule'
    [void](Filho $r 'type' $AcaoRegra)
    [void](Filho $r 'interface' $Interface)
    [void](Filho $r 'ipprotocol' 'inet')
    if ($Protocolo -ne 'any') { [void](Filho $r 'protocol' $Protocolo) }
    $s = Filho $r 'source'
    if ($Origem -eq 'any') { [void](Filho $s 'any') }
    elseif ($Origem -match '^opt[0-9]+$') { [void](Filho $s 'network' $Origem) }
    else { [void](Filho $s 'address' $Origem) }
    $d = Filho $r 'destination'
    if ($InverterDestino) { [void](Filho $d 'not') }
    if ($Destino -eq 'any') { [void](Filho $d 'any') }
    else { [void](Filho $d 'address' $Destino) }
    if ($Porta -ne '') { [void](Filho $d 'port' $Porta) }
    [void](Filho $r 'descr' $Descricao)
    [void](Filho $r 'tracker' ([string]$script:Tracker))
    $script:Tracker++
    if ($AcaoRegra -eq 'block') { [void](Filho $r 'log') }
    $script:RegraCount++
}

function VerificarXml([string]$Caminho) {
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $x = New-Object System.Xml.XmlDocument
    $x.PreserveWhitespace = $true
    $reader = [System.Xml.XmlReader]::Create($Caminho,$settings)
    try { $x.Load($reader) } finally { $reader.Close() }
    if ($x.DocumentElement.Name -ne 'pfsense') { throw 'Nao e XML do pfSense.' }
    return $x
}

if (-not (Test-Path -LiteralPath $Base -PathType Container)) {
    throw "Pasta do projeto nao encontrada: $Base"
}

$pastas = @(
    $ConfigDir,
    (Join-Path $Base '00-Documentacao'),
    (Join-Path $Base '06-Evidencias\03-Rede-Firewall'),
    (Join-Path $Base '07-Video\Roteiros'),
    (Join-Path $Base '09-Logs-Testes')
)
foreach ($p in $pastas) { New-Item -ItemType Directory -Path $p -Force | Out-Null }

if ($Acao -eq 'Gerar') {
    if ([string]::IsNullOrWhiteSpace($XmlOrigem)) {
        $downloads = Join-Path $env:USERPROFILE 'Downloads'
        $candidato = Get-ChildItem -LiteralPath $downloads -Filter 'config-fw01.smartfactory.corp-*.xml' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($null -ne $candidato) { $XmlOrigem = $candidato.FullName }
    }
    if (-not (Test-Path -LiteralPath $XmlOrigem -PathType Leaf)) {
        throw 'Nao encontrei o backup. Informe -XmlOrigem "C:\caminho\config-fw01....xml".'
    }
    if (([IO.Path]::GetFullPath($XmlOrigem)) -eq ([IO.Path]::GetFullPath($NovoXml))) {
        throw 'Nao e permitido usar o XML de saida como origem.'
    }
    $script:Doc = VerificarXml $XmlOrigem
    $raizXml = $script:Doc.DocumentElement
    if ($raizXml.SelectSingleNode('version').InnerText -ne '24.6') {
        throw 'Revisao do XML diferente de 24.6. Pare e revise a versao.'
    }
    if ($raizXml.SelectSingleNode('system/hostname').InnerText -ne 'fw01' -or
        $raizXml.SelectSingleNode('system/domain').InnerText -ne 'smartfactory.corp') {
        throw 'XML nao pertence ao firewall fw01.smartfactory.corp.'
    }
    if ($raizXml.SelectSingleNode('interfaces/wan/if').InnerText -ne 'hn0' -or
        $raizXml.SelectSingleNode('interfaces/lan/if').InnerText -ne 'hn1' -or
        $raizXml.SelectSingleNode('interfaces/lan/ipaddr').InnerText -ne '10.20.10.1') {
        throw 'Interfaces diferentes do backup analisado. Nenhuma mudanca feita.'
    }
    if ($raizXml.SelectNodes('vlans/vlan').Count -ne 0 -or
        $raizXml.SelectNodes('interfaces/opt1').Count -ne 0 -or
        $raizXml.SelectNodes('aliases/alias').Count -ne 0 -or
        $raizXml.SelectNodes('ifgroups/ifgroupentry').Count -ne 0 -or
        $raizXml.SelectNodes('dhcrelay').Count -ne 0) {
        throw 'O backup nao esta mais no estado inicial. Nao vou sobrescrever mudancas.'
    }
    $regrasAntigas = $raizXml.SelectNodes('filter/rule')
    if ($regrasAntigas.Count -ne 2) { throw 'Firewall ja possui regras adicionais. Interrompido.' }
    $nomesOriginais = @($regrasAntigas | ForEach-Object { $_.SelectSingleNode('descr').InnerText })
    if ($nomesOriginais -notcontains 'Default allow LAN to any rule' -or
        $nomesOriginais -notcontains 'Default allow LAN IPv6 to any rule') {
        throw 'Regras de origem diferentes do esperado. Interrompido.'
    }
    if (Test-Path -LiteralPath $Backup) {
        $ha = (Get-FileHash -LiteralPath $Backup -Algorithm SHA256).Hash
        $hb = (Get-FileHash -LiteralPath $XmlOrigem -Algorithm SHA256).Hash
        if ($ha -ne $hb) { throw 'Backup original ja existe, mas e diferente. Interrompido.' }
    } else {
        Copy-Item -LiteralPath $XmlOrigem -Destination $Backup
    }
    Logar 'Backup original preservado; iniciando geracao do XML.'

    $interfaces = $raizXml.SelectSingleNode('interfaces')
    $lan = $raizXml.SelectSingleNode('interfaces/lan')
    DefinirTexto $lan 'if' 'hn1.10'
    RemoverSeHouver $lan 'track6-interface'
    RemoverSeHouver $lan 'track6-prefix-id'
    RemoverSeHouver $lan 'ipaddrv6'
    $wan = $raizXml.SelectSingleNode('interfaces/wan')
    RemoverSeHouver $wan 'blockpriv'
    RemoverSeHouver $wan 'blockbogons'

    # O backup inicial traz DHCPv6 da LAN habilitado; o lab usa somente IPv4.
    $dv6 = $raizXml.SelectSingleNode('dhcpdv6/lan')
    if ($null -ne $dv6) {
        RemoverSeHouver $dv6 'enable'
        DefinirTexto $dv6 'ramode' 'disabled'
    }
    $d4 = $raizXml.SelectSingleNode('dhcpd/lan')
    if ($null -ne $d4) {
        RemoverSeHouver $d4 'range'
        RemoverSeHouver $d4 'enable'
    }

    $vlans = $raizXml.SelectSingleNode('vlans')
    $redes = @(
        [pscustomobject]@{ Id=10;  Nome='MGMT';         IP='10.20.10.1';  Iface='lan' },
        [pscustomobject]@{ Id=20;  Nome='SERVIDORES';    IP='10.20.20.1';  Iface='opt1' },
        [pscustomobject]@{ Id=30;  Nome='ADMIN';        IP='10.20.30.1';  Iface='opt2' },
        [pscustomobject]@{ Id=40;  Nome='RH';           IP='10.20.40.1';  Iface='opt3' },
        [pscustomobject]@{ Id=50;  Nome='FINANCEIRO';   IP='10.20.50.1';  Iface='opt4' },
        [pscustomobject]@{ Id=60;  Nome='ENGENHARIA';   IP='10.20.60.1';  Iface='opt5' },
        [pscustomobject]@{ Id=70;  Nome='PRODUCAO';     IP='10.20.70.1';  Iface='opt6' },
        [pscustomobject]@{ Id=80;  Nome='LOGISTICA';    IP='10.20.80.1';  Iface='opt7' },
        [pscustomobject]@{ Id=90;  Nome='TI';           IP='10.20.90.1';  Iface='opt8' },
        [pscustomobject]@{ Id=100; Nome='DMZ';          IP='10.20.100.1'; Iface='opt9' },
        [pscustomobject]@{ Id=110; Nome='SECURITY_SOC'; IP='10.20.110.1'; Iface='opt10' },
        [pscustomobject]@{ Id=120; Nome='BACKUP';       IP='10.20.120.1'; Iface='opt11' },
        [pscustomobject]@{ Id=999; Nome='VISITANTES';   IP='10.20.200.1'; Iface='opt12' }
    )
    foreach ($rede in $redes) {
        $v = Filho $vlans 'vlan'
        [void](Filho $v 'if' 'hn1')
        [void](Filho $v 'tag_type' 'ctag')
        [void](Filho $v 'tag' ([string]$rede.Id))
        [void](Filho $v 'pcp')
        [void](Filho $v 'descr' ('VLAN{0}_{1}' -f $rede.Id,$rede.Nome))
        [void](Filho $v 'vlanif' ('hn1.{0}' -f $rede.Id))
        if ($rede.Iface -eq 'lan') { continue }
        $iface = Filho $interfaces $rede.Iface
        [void](Filho $iface 'descr' $rede.Nome)
        [void](Filho $iface 'if' ('hn1.{0}' -f $rede.Id))
        [void](Filho $iface 'enable')
        [void](Filho $iface 'ipaddr' $rede.IP)
        [void](Filho $iface 'subnet' '24')
    }

    $script:Aliases = $raizXml.SelectSingleNode('aliases')
    NovoAlias 'SF_CORP' 'network' '10.20.0.0/16' 'Faixa corporativa SmartFactory'
    NovoAlias 'SF_PRIVATE' 'network' '10.0.0.0/8 172.16.0.0/12 192.168.0.0/16' 'Espacos privados RFC1918'
    NovoAlias 'SF_CLIENT_NETS' 'network' '10.20.30.0/24 10.20.40.0/24 10.20.50.0/24 10.20.60.0/24 10.20.70.0/24 10.20.80.0/24 10.20.90.0/24' 'VLANs corporativas de usuarios'
    NovoAlias 'SF_DC' 'host' '10.20.20.11 10.20.20.12' 'Controladores de dominio (DC02 apenas planejado)'
    NovoAlias 'SF_FILES' 'host' '10.20.20.15 10.20.20.16' 'File Servers (FILE02 apenas planejado)'
    NovoAlias 'SF_WEB' 'host' '10.20.100.10' 'Servidor IIS'
    NovoAlias 'SF_WAZUH' 'host' '10.20.110.10' 'Wazuh all-in-one'
    NovoAlias 'SF_BACKUP' 'host' '10.20.120.10' 'Servidor backup'
    NovoAlias 'SF_PAW' 'host' '10.20.90.10' 'Privileged Access Workstation'
    NovoAlias 'SF_HOST' 'host' '10.20.10.10' 'Host Hyper-V de laboratorio'
    NovoAlias 'SF_MANAGED' 'host' '10.20.20.11 10.20.20.12 10.20.20.15 10.20.20.16 10.20.100.10 10.20.120.10' 'Servidores Windows administraveis'
    NovoAlias 'SF_BKP_TARGETS' 'host' '10.20.20.11 10.20.20.15' 'Alvos permitidos do backup'
    NovoAlias 'SF_PUBLIC_DNS' 'host' '1.1.1.1 9.9.9.9' 'Resolvedores publicos visitantes'
    NovoAlias 'SF_KERBEROS' 'port' '88 464' 'Kerberos e mudanca de senha'
    NovoAlias 'SF_LDAP' 'port' '389 636 3268 3269' 'LDAP/LDAPS e Global Catalog'
    NovoAlias 'SF_RPC' 'port' '135 49152:65535' 'Endpoint Mapper e RPC dinamico do AD'
    NovoAlias 'SF_WEBPORTS' 'port' '80 443' 'HTTP e HTTPS'
    NovoAlias 'SF_WAZUH_AGENT' 'port' '1514 1515' 'Eventos e enrollment de agentes Wazuh'
    NovoAlias 'SF_WINRM' 'port' '5985 5986' 'WinRM HTTP e HTTPS'
    NovoAlias 'SF_BKP_PORTS' 'port' '135 445 5985 49152:65535' 'Transporte do backup Windows'

    $ifgroups = Filho $raizXml 'ifgroups'
    $g = Filho $ifgroups 'ifgroupentry'
    [void](Filho $g 'ifname' 'CLIENTES')
    [void](Filho $g 'members' 'opt2 opt3 opt4 opt5 opt6 opt7 opt8')
    [void](Filho $g 'descr' 'Clientes das VLANs 30 a 90')

    $relay = Filho $raizXml 'dhcrelay'
    [void](Filho $relay 'enable')
    [void](Filho $relay 'interface' 'opt2,opt3,opt4,opt5,opt6,opt7,opt8,opt12')
    [void](Filho $relay 'server' '10.20.20.11')
    [void](Filho $relay 'carpstatusvip' 'none')

    $outbound = $raizXml.SelectSingleNode('nat/outbound/mode')
    if ($null -eq $outbound) { throw 'Modo NAT nao encontrado.' }
    $outbound.InnerText = 'automatic'

    $webgui = $raizXml.SelectSingleNode('system/webgui')
    if ($null -eq $webgui.SelectSingleNode('noantilockout')) {
        [void](Filho $webgui 'noantilockout')
    }

    $script:Filtro = $raizXml.SelectSingleNode('filter')
    while ($null -ne $script:Filtro.SelectSingleNode('rule')) {
        $regraAntiga = $script:Filtro.SelectSingleNode('rule')
        [void]$script:Filtro.RemoveChild($regraAntiga)
    }
    $script:Tracker = [long]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) * 100L
    $script:RegraCount = 0

    # LAN gerencial. Esta regra existe antes da desativacao do anti-lockout.
    NovaRegra -Interface 'lan' -Descricao 'SF-01 HOST HTTPS pfSense' -Origem 'SF_HOST' -Destino '10.20.10.1' -Porta '443'

    # Grupo CLIENTES: ordem intencional, primeira correspondencia prevalece.
    NovaRegra -Interface 'CLIENTES' -Descricao 'SF-02 PAW HTTPS pfSense' -Origem 'SF_PAW' -Destino '10.20.10.1' -Porta '443'
    NovaRegra -Interface 'CLIENTES' -Descricao 'SF-03 PAW WinRM servidores' -Origem 'SF_PAW' -Destino 'SF_MANAGED' -Porta 'SF_WINRM'
    NovaRegra -Interface 'CLIENTES' -Descricao 'SF-04 PAW RDP WEB01' -Origem 'SF_PAW' -Destino 'SF_WEB' -Porta '3389'
    NovaRegra -Interface 'CLIENTES' -Descricao 'SF-05 PAW SSH Wazuh' -Origem 'SF_PAW' -Destino 'SF_WAZUH' -Porta '22'
    NovaRegra -Interface 'CLIENTES' -Descricao 'SF-06 PAW dashboard Wazuh' -Origem 'SF_PAW' -Destino 'SF_WAZUH' -Porta '443'
    NovaRegra -Interface 'CLIENTES' -Descricao 'SF-07 DNS AD' -Origem 'SF_CLIENT_NETS' -Destino 'SF_DC' -Protocolo 'tcp/udp' -Porta '53'
    NovaRegra -Interface 'CLIENTES' -Descricao 'SF-08 Kerberos AD' -Origem 'SF_CLIENT_NETS' -Destino 'SF_DC' -Protocolo 'tcp/udp' -Porta 'SF_KERBEROS'
    NovaRegra -Interface 'CLIENTES' -Descricao 'SF-09 LDAP e GC' -Origem 'SF_CLIENT_NETS' -Destino 'SF_DC' -Porta 'SF_LDAP'
    NovaRegra -Interface 'CLIENTES' -Descricao 'SF-10 CLDAP DC locator' -Origem 'SF_CLIENT_NETS' -Destino 'SF_DC' -Protocolo 'udp' -Porta '389'
    NovaRegra -Interface 'CLIENTES' -Descricao 'SF-11 SYSVOL Netlogon' -Origem 'SF_CLIENT_NETS' -Destino 'SF_DC' -Porta '445'
    NovaRegra -Interface 'CLIENTES' -Descricao 'SF-12 RPC Active Directory' -Origem 'SF_CLIENT_NETS' -Destino 'SF_DC' -Porta 'SF_RPC'
    NovaRegra -Interface 'CLIENTES' -Descricao 'SF-13 NTP AD' -Origem 'SF_CLIENT_NETS' -Destino 'SF_DC' -Protocolo 'udp' -Porta '123'
    NovaRegra -Interface 'CLIENTES' -Descricao 'SF-14 Compartilhamentos FILE' -Origem 'SF_CLIENT_NETS' -Destino 'SF_FILES' -Porta '445'
    NovaRegra -Interface 'CLIENTES' -Descricao 'SF-15 Intranet HTTP HTTPS' -Origem 'SF_CLIENT_NETS' -Destino 'SF_WEB' -Porta 'SF_WEBPORTS'
    NovaRegra -Interface 'CLIENTES' -Descricao 'SF-16 Agentes Wazuh' -Origem 'SF_CLIENT_NETS' -Destino 'SF_WAZUH' -Porta 'SF_WAZUH_AGENT'
    NovaRegra -Interface 'CLIENTES' -Descricao 'SF-17 Bloquear lateral RFC1918' -Origem 'SF_CLIENT_NETS' -Destino 'SF_PRIVATE' -AcaoRegra 'block' -Protocolo 'any'
    NovaRegra -Interface 'CLIENTES' -Descricao 'SF-18 Internet HTTP HTTPS' -Origem 'SF_CLIENT_NETS' -Destino 'SF_PRIVATE' -Porta 'SF_WEBPORTS' -InverterDestino

    # Servidores: destinos corporativos somente por excecao.
    NovaRegra -Interface 'opt1' -Descricao 'SF-19 Servidores agentes Wazuh' -Origem 'opt1' -Destino 'SF_WAZUH' -Porta 'SF_WAZUH_AGENT'
    NovaRegra -Interface 'opt1' -Descricao 'SF-20 DCs DNS externo' -Origem 'SF_DC' -Destino 'SF_PUBLIC_DNS' -Protocolo 'tcp/udp' -Porta '53'
    NovaRegra -Interface 'opt1' -Descricao 'SF-21 Servidores bloquear redes privadas' -Origem 'opt1' -Destino 'SF_PRIVATE' -AcaoRegra 'block' -Protocolo 'any'
    NovaRegra -Interface 'opt1' -Descricao 'SF-22 Servidores atualizacoes' -Origem 'opt1' -Destino 'SF_PRIVATE' -Porta 'SF_WEBPORTS' -InverterDestino
    NovaRegra -Interface 'opt1' -Descricao 'SF-23 Servidores NTP externo' -Origem 'opt1' -Destino 'SF_PRIVATE' -Protocolo 'udp' -Porta '123' -InverterDestino

    # DMZ: apenas dependencias autenticacao e log.
    NovaRegra -Interface 'opt9' -Descricao 'SF-24 WEB DNS DC' -Origem 'SF_WEB' -Destino 'SF_DC' -Protocolo 'tcp/udp' -Porta '53'
    NovaRegra -Interface 'opt9' -Descricao 'SF-25 WEB Kerberos' -Origem 'SF_WEB' -Destino 'SF_DC' -Protocolo 'tcp/udp' -Porta 'SF_KERBEROS'
    NovaRegra -Interface 'opt9' -Descricao 'SF-26 WEB LDAP GC' -Origem 'SF_WEB' -Destino 'SF_DC' -Porta 'SF_LDAP'
    NovaRegra -Interface 'opt9' -Descricao 'SF-27 WEB CLDAP' -Origem 'SF_WEB' -Destino 'SF_DC' -Protocolo 'udp' -Porta '389'
    NovaRegra -Interface 'opt9' -Descricao 'SF-28 WEB SYSVOL' -Origem 'SF_WEB' -Destino 'SF_DC' -Porta '445'
    NovaRegra -Interface 'opt9' -Descricao 'SF-29 WEB RPC DC' -Origem 'SF_WEB' -Destino 'SF_DC' -Porta 'SF_RPC'
    NovaRegra -Interface 'opt9' -Descricao 'SF-30 WEB agente Wazuh' -Origem 'SF_WEB' -Destino 'SF_WAZUH' -Porta 'SF_WAZUH_AGENT'
    NovaRegra -Interface 'opt9' -Descricao 'SF-31 DMZ bloquear redes privadas' -Origem 'opt9' -Destino 'SF_PRIVATE' -AcaoRegra 'block' -Protocolo 'any'
    NovaRegra -Interface 'opt9' -Descricao 'SF-32 WEB atualizacoes externas' -Origem 'SF_WEB' -Destino 'SF_PRIVATE' -Porta 'SF_WEBPORTS' -InverterDestino

    # SIEM.
    NovaRegra -Interface 'opt10' -Descricao 'SF-33 SOC DNS DC' -Origem 'SF_WAZUH' -Destino 'SF_DC' -Protocolo 'tcp/udp' -Porta '53'
    NovaRegra -Interface 'opt10' -Descricao 'SF-34 SOC NTP DC' -Origem 'SF_WAZUH' -Destino 'SF_DC' -Protocolo 'udp' -Porta '123'
    NovaRegra -Interface 'opt10' -Descricao 'SF-35 SOC bloquear privado' -Origem 'opt10' -Destino 'SF_PRIVATE' -AcaoRegra 'block' -Protocolo 'any'
    NovaRegra -Interface 'opt10' -Descricao 'SF-36 SOC HTTPS updates' -Origem 'SF_WAZUH' -Destino 'SF_PRIVATE' -Porta '443' -InverterDestino

    # Backup.
    NovaRegra -Interface 'opt11' -Descricao 'SF-37 BKP DNS DC' -Origem 'SF_BACKUP' -Destino 'SF_DC' -Protocolo 'tcp/udp' -Porta '53'
    NovaRegra -Interface 'opt11' -Descricao 'SF-38 BKP Kerberos DC' -Origem 'SF_BACKUP' -Destino 'SF_DC' -Protocolo 'tcp/udp' -Porta 'SF_KERBEROS'
    NovaRegra -Interface 'opt11' -Descricao 'SF-39 BKP LDAP DC' -Origem 'SF_BACKUP' -Destino 'SF_DC' -Porta 'SF_LDAP'
    NovaRegra -Interface 'opt11' -Descricao 'SF-40 BKP alvos permitidos' -Origem 'SF_BACKUP' -Destino 'SF_BKP_TARGETS' -Porta 'SF_BKP_PORTS'
    NovaRegra -Interface 'opt11' -Descricao 'SF-41 BKP eventos Wazuh' -Origem 'SF_BACKUP' -Destino 'SF_WAZUH' -Porta 'SF_WAZUH_AGENT'
    NovaRegra -Interface 'opt11' -Descricao 'SF-42 BKP bloquear privado' -Origem 'opt11' -Destino 'SF_PRIVATE' -AcaoRegra 'block' -Protocolo 'any'
    NovaRegra -Interface 'opt11' -Descricao 'SF-43 BKP HTTPS updates' -Origem 'SF_BACKUP' -Destino 'SF_PRIVATE' -Porta '443' -InverterDestino

    # Visitantes: sem acesso a qualquer RFC1918.
    NovaRegra -Interface 'opt12' -Descricao 'SF-44 Guest bloquear RFC1918' -Origem 'opt12' -Destino 'SF_PRIVATE' -AcaoRegra 'block' -Protocolo 'any'
    NovaRegra -Interface 'opt12' -Descricao 'SF-45 Guest DNS publico' -Origem 'opt12' -Destino 'SF_PUBLIC_DNS' -Protocolo 'tcp/udp' -Porta '53'
    NovaRegra -Interface 'opt12' -Descricao 'SF-46 Guest web externo' -Origem 'opt12' -Destino 'SF_PRIVATE' -Porta 'SF_WEBPORTS' -InverterDestino
    NovaRegra -Interface 'opt12' -Descricao 'SF-47 Guest NTP externo' -Origem 'opt12' -Destino 'SF_PRIVATE' -Protocolo 'udp' -Porta '123' -InverterDestino

    # Regras do pfSense aplicam-se a trafego roteado; mesma VLAN requer firewall local.
    $script:Doc.Save($NovoXml)
    $releitura = VerificarXml $NovoXml
    if ($releitura.SelectNodes('/pfsense/vlans/vlan').Count -ne 13 -or
        $releitura.SelectNodes('/pfsense/interfaces/*').Count -ne 14 -or
        $releitura.SelectNodes('/pfsense/filter/rule').Count -ne 47 -or
        $releitura.SelectNodes('/pfsense/aliases/alias').Count -ne 20 -or
        $releitura.SelectSingleNode('/pfsense/interfaces/lan/if').InnerText -ne 'hn1.10' -or
        $releitura.SelectSingleNode('/pfsense/dhcrelay/server').InnerText -ne '10.20.20.11') {
        throw 'Validacao estrutural do XML gerado falhou. NAO IMPORTAR.'
    }

    $roteiroTexto = @'
Nesta etapa, implementamos a segmentacao da rede SmartFactory no firewall pfSense e no Hyper-V.

Partimos de um backup da configuracao original do firewall e utilizamos um script PowerShell para gerar o arquivo XML com as VLANs, gateways, aliases, regras de seguranca, NAT e DHCP Relay, evitando configurar dezenas de itens manualmente.

Configuramos a VLAN 99 como nativa e sem uso, mantendo a VLAN 10 etiquetada para gerenciamento. As redes de departamentos, servidores, DMZ, SOC, backup e visitantes receberam gateways especificos.

Organizamos as regras do firewall conforme o principio de menor privilegio, limitando acesso administrativo a PAW e ao host do laboratorio, protegendo a DMZ e isolando a rede de visitantes das redes privadas.

O DHCP Relay foi preparado para o futuro controlador de dominio, onde sera instalado o DHCP do Windows Server. Os testes entre maquinas virtuais serao realizados quando os servidores e clientes estiverem instalados.

Por fim, conferimos o trunk do Hyper-V, o acesso HTTPS ao firewall e registramos os resultados e backups para documentacao e recuperacao.
'@
    Set-Content -LiteralPath $Roteiro -Value $roteiroTexto -Encoding UTF8

    $docTexto = @"
# SmartFactory - Etapa 03 - VLANs, Firewall, NAT e DHCP Relay

Data: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

## Base utilizada

- Origem: backup integral da VM-FW01 fornecido pelo usuario.
- Revisao de configuracao: 24.6 (NAO e versao do produto).
- Interfaces fisicas pfSense: hn0 WAN, hn1 LAN.
- WAN: DHCP sobre Default Switch, sem bloqueio RFC1918 devido ao NAT privado do Hyper-V.
- LAN: hn1.10, IP 10.20.10.1/24.
- Hyper-V: SF-LAN e VLAN nativa 99; host Access VLAN 10.
- DHCP IPv4 pfSense: nao habilitado; range obsoleto da LAN removido.
- DHCPv6/RA da LAN: desabilitado para o laboratorio IPv4.
- IPv6 WAN preservado conforme backup original.

## Segmentos

$((($redes | ForEach-Object { '- VLAN {0} | {1} | {2}/24 | {3}' -f $_.Id,$_.Nome,$_.IP,$_.Iface }) -join "`r`n"))

VLAN 99: somente nativa, sem interface IP e sem gateway.

## Politicas

- Aliases criados: 20.
- Regras criadas: $script:RegraCount (log habilitado nas regras de block).
- Grupo CLIENTES: VLANs 30,40,50,60,70,80,90.
- Anti-lockout desabilitado; regra explicita de gestao do host 10.20.10.10.
- Gestao PAW: 10.20.90.10, habilitada somente para destinos e portas previstas.
- Acesso inter-VLAN somente por autorizacoes especificas; demais fluxos privados negados.
- Visitantes: bloqueio de RFC1918, DNS publico e HTTP/HTTPS externos.
- NAT outbound: automatic.
- DHCP Relay: interfaces opt2 a opt8 e opt12 para 10.20.20.11.
- DHCP Relay somente sera funcional depois que DC01/Windows DHCP estiver configurado.
- Servicos AD/DFS/SMB/Wazuh dependem da instalacao das VMs previstas.
- Trafego na mesma VLAN nao atravessa pfSense; usar firewall local Windows.

## Reducoes e pendencias

- VMs DC02 e FILE02 planejadas no CP02 mas nao instaladas por limite de hardware.
- DHCP Failover e DFSR entre 2 servidores nao serao demonstrados fisicamente neste laboratorio.
- Interface WAN usa Default Switch do Hyper-V, nao uplink fisico redundante.
- VLANs no pfSense nao representam isoladamente testes de conectividade entre clientes.
- Testes reais de ACLs, AD, SMB, Wazuh, DHCP e backup serao executados apos criacao das VMs.

## Evidencias

- Backup antes: 04-Configuracoes/pfSense/backup-ANTES-Etapa03.xml.
- Arquivo para restaurar: 04-Configuracoes/pfSense/config-SmartFactory-Etapa03-IMPORTAR.xml.
- Log PowerShell: 09-Logs-Testes/05-Etapa03-Resultado.txt.
- Capturas: 06-Evidencias/03-Rede-Firewall/.
- Roteiro: 07-Video/Roteiros/Roteiro_Video_Etapa_4.txt.
- Video: 04 - SmartFactory - VLANs, Firewall, NAT e DHCP Relay.mp4.

## Critério de encerramento

Marcar concluida somente quando restore, trunk, HTTPS, inspeção das regras e backup posterior forem confirmados. Demais testes permanecem pendentes ate implantar os hosts.
"@
    Set-Content -LiteralPath $Relatorio -Value $docTexto -Encoding UTF8

    $Matriz = Join-Path $Base '00-Documentacao\00-Matriz-Rastreabilidade-CP1-CP2-CP3.md'
    if (-not (Test-Path -LiteralPath $Matriz)) {
        $matrizTexto = @'
# SmartFactory - Rastreabilidade das tres CPs

Regra: marcar [x] somente apos implementacao e evidencia. Omitir VMs por hardware nao equivale a implementar alta disponibilidade.

## CP-01 - Rede

- [ ] Enderecamento completo e VLANs 10-120, 999 (VLAN 99 nativa sem IP).
- [ ] Hyper-V, SF-LAN, trunk e host na VLAN 10; evidencias.
- [ ] Gateway pfSense em todas as redes e roteamento inter-VLAN.
- [ ] ACLs stateful, minimo privilegio e bloqueio de movimento lateral.
- [ ] Isolamento RH/Financeiro e TI/OT Produção.
- [ ] DMZ interna, acesso permitido e bloqueio de pivot.
- [ ] Visitantes isolados das redes privadas.
- [ ] NAT automatico, politicas WAN e DHCP Relay.
- [ ] Documentar SET/switches fisicos como arquitetura nao implantada.
- [ ] Diagrama logico e fisico, plano IP e testes positivos/negativos.

## CP-02 - Windows Server 2025

- [ ] DC01 Windows Server 2025 Core; AD DS smartfactory.corp.
- [ ] DNS integrado AD, zonas, SRV, forwarders, zona reversa.
- [ ] OUs, usuarios, grupos e AGDLP.
- [ ] DHCP Windows, oito escopos, opcoes, exclusoes e Relay funcional.
- [ ] DC02/DHCP Failover: limitacao de laboratorio registrada.
- [ ] FILE01, VHDX/SCSI, NTFS, permissoes e shares SMB 3.1.1.
- [ ] DFS Namespace, FSRM, VSS e deduplicacao (verificar suporte).
- [ ] FILE02/DFSR assincrono: limitacao registrada, nao confundir com backup.
- [ ] WEB01 IIS em DMZ, TLS/HTTPS e autenticacao Windows.
- [ ] BKP01, isolamento, backups e restauracao.
- [ ] Cliente Windows 11 no dominio e testes DNS/DHCP/SMB/IIS.
- [ ] Documentar licenciamento, Core/Desktop e restricoes de RAM.

## CP-03 - Hardening, SIEM e resposta

- [ ] VLAN 110 SOC e VLAN 120 backup isoladas.
- [ ] PAW-TI01 e acessos admin restritos; excecao do host documentada.
- [ ] Matriz de firewall integral, regras, logs e verificacao de bloqueios.
- [ ] GPOs modulares, Central Store, piloto, gpresult e rollback.
- [ ] Windows LAPS, delegacao, ACLs, senha local e validacoes.
- [ ] Hardening Windows Server Core, WinRM, Defender, SMB e auditoria.
- [ ] Ubuntu Wazuh: SSH por chave, UFW, AppArmor, patching.
- [ ] Wazuh manager/indexer/dashboard, agentes e RBAC.
- [ ] Sysmon, coleta 4625/4720/1102/4104, FIM/SCA e vulnerability detection.
- [ ] Isolar backup, procedimento restore de arquivos e system-state.
- [ ] Playbooks IR, GMUD, rollback de mudancas e logs de auditoria.
- [ ] Pacote de evidencias e apresentacao com limites do laboratorio.

## Matriz de 30 testes da CP-03

- [ ] T01 ADM para RH SMB: bloqueado.
- [ ] T02 Cliente para FILE01 TCP445: permitido.
- [ ] T03 Visitantes para 10.20.0.0/16: bloqueado.
- [ ] T04 Cliente para Intranet 443: permitido.
- [ ] T05 WEB01 para RH: bloqueado.
- [ ] T06 Estacao comum para RDP servidor: bloqueado.
- [ ] T07 PAW para RDP WEB01: permitido.
- [ ] T08 PAW para WinRM Core: permitido.
- [ ] T09 Nao-PAW para SSH Wazuh: bloqueado.
- [ ] T10 PAW para SSH Wazuh por chave: permitido.
- [ ] T11 Login SSH por senha: negado.
- [ ] T12 gpresult de endpoint: GPO aplicada.
- [ ] T13 Get-LapsADPassword autorizado: retorna senha.
- [ ] T14 Get-LapsADPassword usuario comum: acesso negado.
- [ ] T15 Reset-LapsPassword: nova senha no AD.
- [ ] T16 Rollback VM teste: rotacao LAPS.
- [ ] T17 Falha logon repetida: alerta Wazuh.
- [ ] T18 Criacao usuario AD: evento 4720 no Wazuh.
- [ ] T19 Inclusao grupo privilegiado: alerta critico.
- [ ] T20 Limpeza Security log: evento 1102 critico.
- [ ] T21 Modificacao arquivo IIS: alerta FIM.
- [ ] T22 PowerShell teste: evento 4104 no Wazuh.
- [ ] T23 Sysmon Process Create: evento ID 1 ingerido.
- [ ] T24 Defender teste benigno: telemetria capturada.
- [ ] T25 Vulnerability Detection: CVE visivel.
- [ ] T26 Mudanca ACL arquivo: evento 4670 no Wazuh.
- [ ] T27 Wazuh Agent parado: deteccao host offline.
- [ ] T28 Restore arquivo: integridade verificada.
- [ ] T29 Restore System State: log/procedimento.
- [ ] T30 Failover de FILE: nao executavel sem FILE02; justificar.

## Limitacoes formais do laboratorio

- Oito VMs e apenas 16GB de RAM no host Windows 11.
- DC02, FILE02, DHCP Failover, DFSR e SET fisico nao sao implantados.
- Acesso a arquivos/servicos depende das VMs e do firewall local Windows.
- Backup em disco do mesmo host nao e backup offline/imutavel.
- Para testes inviaveis: registrar a justificativa, sem marcar como aprovados.
'@
        Set-Content -LiteralPath $Matriz -Value $matrizTexto -Encoding UTF8
    }
    Logar ('XML gerado: {0}' -f $NovoXml)
    Logar ('VLANs: 13, aliases: 20, regras: {0}, DHCP relay: 8 VLANs.' -f $script:RegraCount)
    Logar ('SHA256 XML: {0}' -f (Get-FileHash -LiteralPath $NovoXml -Algorithm SHA256).Hash)
    Logar ('Roteiro: {0}' -f $Roteiro)
    Logar 'Proximo passo MANUAL: Restaurar XML no pfSense; somente DEPOIS executar -Acao MigrarTrunk.'
    Write-Host "`nGERACAO CONCLUIDA. NADA FOI ALTERADO NO PFSENSE OU NO HYPER-V." -ForegroundColor Green
    Write-Host "Arquivo para importar: $NovoXml" -ForegroundColor Cyan
    return
}

# As outras acoes exigem privilegio administrativo no Hyper-V.
$identidade = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identidade)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Abra o Windows PowerShell como Administrador.'
}
Import-Module Hyper-V -ErrorAction Stop
$vm = Get-VM -Name 'VM-FW01' -ErrorAction Stop
$lanVM = Get-VMNetworkAdapter -VMName 'VM-FW01' -Name 'LAN' -ErrorAction Stop
$wanVM = Get-VMNetworkAdapter -VMName 'VM-FW01' -Name 'WAN' -ErrorAction Stop
if ($lanVM.SwitchName -ne 'SF-LAN' -or $wanVM.SwitchName -ne 'Default Switch') {
    throw 'Adaptadores WAN/LAN nao coincidem com a topologia esperada.'
}

if ($Acao -eq 'MigrarTrunk') {
    if (-not (Test-Path -LiteralPath $NovoXml)) { throw 'XML gerado nao encontrado. Execute Gerar primeiro.' }
    $resposta = Read-Host 'Ja restaurou o XML no pfSense e a console concluiu o reboot? Digite SIM-RESTAUREI'
    if ($resposta -ne 'SIM-RESTAUREI') { throw 'Cancelado sem mudancas.' }
    Set-VMNetworkAdapterVlan -VMName 'VM-FW01' -VMNetworkAdapterName 'LAN' `
        -Trunk -AllowedVlanIdList $TrunkVlans -NativeVlanId 99
    Logar 'Hyper-V: trunk atualizado para VLAN nativa 99.'
    Start-Sleep -Seconds 8
}
if ($Acao -eq 'ReverterTrunk') {
    $resposta = Read-Host 'Ja restaurou a configuracao ANTIGA do pfSense na console? Digite SIM-REVERTI'
    if ($resposta -ne 'SIM-REVERTI') { throw 'Cancelado sem mudancas.' }
    Set-VMNetworkAdapterVlan -VMName 'VM-FW01' -VMNetworkAdapterName 'LAN' `
        -Trunk -AllowedVlanIdList $TrunkVlans -NativeVlanId 10
    Logar 'Hyper-V: trunk restaurado para VLAN nativa 10.'
    Start-Sleep -Seconds 5
}

$estado = Get-VMNetworkAdapterVlan -VMName 'VM-FW01' -VMNetworkAdapterName 'LAN'
$hostVlan = Get-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName 'SF-LAN'
$ipHost = Get-NetIPAddress -InterfaceAlias 'vEthernet (SF-LAN)' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -eq '10.20.10.10' -and $_.PrefixLength -eq 24 } |
    Select-Object -First 1
$https = $false
try {
    $https = (Test-NetConnection -ComputerName '10.20.10.1' -Port 443 -WarningAction SilentlyContinue).TcpTestSucceeded
} catch { $https = $false }
Logar ('VM: {0}; Trunk: {1}; Native: {2}; Host access: {3}; HTTPS: {4}' -f `
    $vm.State,$estado.OperationMode,$estado.NativeVlanId,$hostVlan.AccessVlanId,$https)

if ($Acao -eq 'Validar' -or $Acao -eq 'MigrarTrunk') {
    if ($vm.State -ne 'Running' -or $estado.OperationMode -ne 'Trunk' -or
        $estado.NativeVlanId -ne 99 -or $hostVlan.OperationMode -ne 'Access' -or $hostVlan.AccessVlanId -ne 10 -or
        $null -eq $ipHost -or $ipHost.AddressState -ne 'Preferred' -or -not $https) {
        throw 'Validacao de rede NAO APROVADA. Verifique o log e a console do pfSense.'
    }
    Logar 'VALIDACAO HYPER-V + HTTPS APROVADA. Regras/servicos do pfSense exigem conferencia no painel.'
    Write-Host 'Hyper-V e HTTPS validados. Confira VLANs, regras, NAT e DHCP Relay no pfSense.' -ForegroundColor Green
}
