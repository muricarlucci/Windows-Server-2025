# SmartFactory GS - ETAPA 10 - VM-WAZUH01: Criar VM Ubuntu, instalar Wazuh, hardening e validar
# Windows PowerShell 5.1 como Administrador no HOST Hyper-V.
# Ordem: Preparar -> CriarVM (gera midia automatica) -> Instalar Ubuntu manualmente
#        -> Executar instalador Linux via midia -> ColetarResultados depois de desligar Wazuh.
# Nenhuma VM existente sera excluida. NAO altera regras do pfSense, nem memoria de outros hosts.
[CmdletBinding()]
param(
  [ValidateSet('Preparar','CriarVM','GerarMidia','ValidarHost','ColetarResultados')]
  [string]$Acao = 'Preparar',
  [string]$IsoPath = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Base = 'D:\FIAP\WINDOWS\SmartFactory-GS'
$NomeVM = 'VM-WAZUH01'
$VMDir = Join-Path $Base '02-VMs\VM-WAZUH01'
$OS = Join-Path $VMDir 'VM-WAZUH01-Ubuntu-OS-40GB.vhdx'
$IDX = Join-Path $VMDir 'VM-WAZUH01-Indexer-80GB.vhdx'
$Transfer = Join-Path $VMDir 'VM-WAZUH01-SFSETUP-256MB.vhdx'
$HostSh = Join-Path $Base '03-Scripts\Gerados-WAZUH\01-Instalar-Configurar-Wazuh.sh'
$Log = Join-Path $Base '09-Logs-Testes\12-WAZUH01-Instalacao-Resultado.txt'
$Relatorio = Join-Path $Base '00-Documentacao\10-WAZUH01-SIEM-AllInOne.md'
$Checklist = Join-Path $Base '00-Documentacao\10-WAZUH01-Checklist.txt'
$Roteiro = Join-Path $Base '07-Video\Roteiros\Roteiro_Video_Etapa_11.txt'
$Evidencias = Join-Path $Base '06-Evidencias\10-WAZUH01-SIEM'
function Registrar([string]$msg){
  $line = ('{0} | {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$msg)
  Add-Content -LiteralPath $Log -Encoding UTF8 -Value $line
  Write-Host $line
}
function VerificarHost {
  if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'Use Windows PowerShell 5.1 do host, nao PS 7.' }
  $p = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Execute o Windows PowerShell como Administrador.'
  }
  if (-not (Test-Path -LiteralPath $Base -PathType Container)) { throw "Pasta do projeto ausente: $Base" }
  Import-Module Hyper-V -ErrorAction Stop
  $dirs = @($VMDir,(Split-Path $HostSh),(Split-Path $Log),(Split-Path $Relatorio),
            (Split-Path $Checklist),(Split-Path $Roteiro),$Evidencias)
  foreach($d in $dirs){ New-Item -ItemType Directory -Force -Path $d | Out-Null }
}
function VerificarVMs([bool]$exigirVM){
  $fw = Get-VM -Name 'VM-FW01' -ErrorAction Stop
  if($fw.State -ne 'Running'){ throw 'Mantenha VM-FW01 ligada para NAT/DNS. Outras VMs desligadas.' }
  $demais = @('VM-DC01','VM-FILE01','VM-WEB01','VM-BKP01','CLI-ADM01','PAW-TI01')
  foreach($n in $demais){
    $v = Get-VM -Name $n -ErrorAction SilentlyContinue
    if($v -and $v.State -ne 'Off'){ throw "$n esta $($v.State); desligue normalmente antes de executar esta etapa." }
  }
  if($exigirVM -and -not (Get-VM -Name $NomeVM -ErrorAction SilentlyContinue)){
    throw 'VM-WAZUH01 nao foi criada.'
  }
  $sw = Get-VMSwitch -Name 'SF-LAN' -ErrorAction Stop
  if($sw.SwitchType -ne 'Internal'){ throw 'Switch SF-LAN nao esta como Internal.' }
  $f = (Get-PSDrive -Name D).Free
  Registrar ('Disco D: livre {0:N1} GiB' -f ($f / 1GB))
  if($f -lt 25GB -and $Acao -in @('Preparar','CriarVM')){ throw 'Menos de 25 GiB livres no D:. Nao iniciar instalacao.' }
  if($f -lt 40GB){ Registrar 'ALERTA: menos de 40 GiB livres. Nao gerar 90 dias de retencao sem ampliar espaco.' }
  $ram = Get-CimInstance -Class Win32_OperatingSystem
  Registrar ('Host RAM fisica livre agora: {0:N1} GiB' -f ($ram.FreePhysicalMemory/1MB))
  Registrar ('FW01: RAM atribuida {0:N1} GiB' -f ($fw.MemoryAssigned/1GB))
}
function GerarArquivos {
  if(-not (Test-Path -LiteralPath $Relatorio)){
@'
# SmartFactory GS - Etapa 10: Wazuh all-in-one em Ubuntu 24.04

STATUS: Em implantacao ate validar o guest.

## Arquitetura real
- VM-WAZUH01 = Ubuntu Server 24.04 LTS AMD64; sem ingresso no Active Directory.
- Hyper-V Gen2, Linux Secure Boot template Microsoft UEFI Certificate Authority, 4 vCPU, RAM estatica 8 GiB.
- SCSI OS 40 GiB e indexer 80 GiB, ambos VHDX dinamicos. Terceiro VHDX FAT32 256 MiB e apenas de transporte de scripts.
- VLAN 110, IP 10.20.110.10/24, gateway 10.20.110.1.
- DNS de bootstrap: pfSense 10.20.110.1, excepcao temporaria/documentada para instalar sem o DC01 ligado.
- Wazuh 4.14, all-in-one: Manager + Indexer + Dashboard + Filebeat; Ubuntu AppArmor, UFW, SSH somente PAW.
- UFW: PAW-TI01 10.20.90.10 para TCP 22/443; VLANs corporativas para TCP 1514/1515.
- API TCP 55000 e Indexer TCP 9200 NAO expostos via UFW.
- Vulnerability Detection padrao do Wazuh 4.14; FIM/SCA/ingestao agent dependem de deploy e testes posteriores.
- Sem alterar pfSense automaticamente. Regra de DNS de bootstrap adicionada manualmente, com IP origem unico.

## Requisitos corporativos nao simulados
- Nao equivale a Wazuh distribuido para ~220 hosts, nem HA.
- 90 dias de retencao e uma meta de capacidade, nao garantia sem dimensionar volume de alertas.
- Sem 10-15 agentes implantados nesta etapa; serao instalados por grupos e validados na fase de telemetria.
- Credenciais Wazuh ficam apenas no Ubuntu, em /root/smartfactory-wazuh. Nao copiar para repositorio publico.
- Testes T17-T27 dos agentes e Wazuh dependem dos endpoints e da memoria fisica; nao alegar aprovacao agora.

## Evidencias
- Hyper-V com RAM estatica 8 GiB, VLAN110, 2 VHDX e Secure Boot Linux.
- Instalacao Ubuntu no disco 40 GiB, dados ext4 80 GiB montados em /var/lib/wazuh-indexer.
- Estado dos servicos (wazuh-indexer, wazuh-manager, wazuh-dashboard, filebeat).
- HTTPS local no Wazuh, UFW e sysctl; posterior login a partir da PAW com memoria suficiente.
- Log de validacao NAO sigiloso transportado em SFSETUP; credenciais nunca em videos/logs compartilhados.
'@ | Set-Content -LiteralPath $Relatorio -Encoding UTF8
  }
  if(-not (Test-Path -LiteralPath $Checklist)){
@'
[ ] FW01 Running; DC01, FILE01, WEB01, BKP01, CLI-ADM01, PAW-TI01 Off
[ ] Backup de configuracao pfSense preservado antes de habilitar resolver na VLAN110
[ ] pfSense DNS Resolver responde na VLAN SECURITY_SOC com regra TCP/UDP53 somente origem 10.20.110.10
[ ] D: com margem fisica; host suficiente para VM estatica 8 GiB
[ ] VM-WAZUH01 Gen2 4 vCPU 8 GiB fixos, Secure Boot Linux CA, Access VLAN110
[ ] VHDX OS 40 GiB, indexer 80 GiB, transporte FAT32 256 MiB
[ ] Ubuntu 24.04 Server: APENAS OS 40GiB formatado; IP estatico 10.20.110.10/24, gateway .1 DNS .1
[ ] Ubuntu sem AD Join; hostname vm-wazuh01
[ ] Script Linux executado pelo FAT32 em sudo, sem SSH aberto para host
[ ] Indexer volume ext4 WAZUHIDX em /var/lib/wazuh-indexer
[ ] Wazuh 4.14 all-in-one instalado, servicos ativos; HTTPS local
[ ] Segredos de admin nao filmados, guardados com acesso restrito
[ ] UFW ativo, 1514/1515 corporativos; 22/443 apenas PAW; 55000/9200 externos nao permitidos
[ ] Resultado nao sigiloso no FAT32; coletado no Windows com VM desligada
[ ] Relatorio, log, evidencias, video 11 e roteiro ampliado salvos
[ ] Agentes Windows, Sysmon, FIM, SCA, Vulnerability Detection de endpoints: etapas de telemetria/testes
'@ | Set-Content -LiteralPath $Checklist -Encoding UTF8
  }
  if(-not (Test-Path -LiteralPath $Roteiro)){
@'
Nesta etapa, implementamos a infraestrutura de monitoramento e deteccao da SmartFactory utilizando o Wazuh em um servidor Ubuntu Linux. A plataforma centraliza eventos de seguranca, aplica regras de deteccao e prepara o acompanhamento dos servidores e estacoes Windows do laboratorio.

Primeiro, fizemos uma avaliacao de recursos no Hyper-V. Como o computador possui apenas dezesseis gigabytes de memoria, desligamos o controlador de dominio, os servidores de arquivos, web e backup e as estacoes Windows. Mantivemos o firewall FW01 ligado para fornecer roteamento e Internet. Para a instalacao funcionar sem o DC01 ligado, configuramos uma autorizacao DNS restrita ao IP do Wazuh no pfSense. Nao liberamos a VLAN de monitoramento inteira para administrar a rede.

Na preparacao, o script criou as pastas de documentacao, o checklist, o log, o roteiro e o registro da configuracao prevista. Depois, provisionou a VM-WAZUH01 como maquina de Geracao 2, com quatro CPUs, oito gigabytes de memoria estatica, Secure Boot compatível com Linux e adaptador em modo Access na VLAN cento e dez. Criamos um disco de quarenta gigabytes para o sistema operacional e outro de oitenta gigabytes para os indices. Os VHDX sao dinamicos, economizando espaco fisico ate que os dados sejam gravados.

Instalamos o Ubuntu Server vinte e quatro ponto zero quatro no disco de sistema, sem ambiente grafico, com endereco dez ponto vinte ponto cento e dez ponto dez e gateway final um. Utilizamos tambem um pequeno disco FAT32 gerado pelo PowerShell para transportar o script Linux, evitando comandos longos copiados manualmente e acessos SSH indevidos pelo Windows hospedeiro.

Em seguida, o script do Ubuntu atualizou as dependencias, conferiu a rede, identificou com seguranca o disco de oitenta gigabytes e montou esse volume como armazenamento exclusivo do indexador. Configurou o limite de mapeamento de memoria necessario e executou o instalador oficial Wazuh da serie quatro ponto quatorze no modo all-in-one. Isso implantou o Wazuh Manager, responsavel por analisar eventos e disparar alertas, o Indexer, que armazena e consulta os dados, o Dashboard HTTPS e o Filebeat, que encaminha os registros para indexacao.

Depois, aplicamos o firewall local UFW. As portas de agentes quinze quatorze e quinze quinze foram permitidas somente para redes corporativas; SSH e Dashboard ficaram restritos a PAW-TI01. Ja a API administrativa e a API do Indexer nao foram publicadas. As credenciais geradas permaneceram guardadas exclusivamente no Ubuntu, sem aparecer nos logs compartilhados.

Finalizamos conferindo os quatro servicos, o HTTPS local, os volumes, a memoria e as regras de firewall, exportando um relatorio tecnico sem segredos. A instalacao dos agentes Windows, a coleta de Sysmon, a verificacao de integridade, as avaliacoes de configuracao e os alertas correlacionados serao comprovados na fase de telemetria e na bateria final de testes.
'@ | Set-Content -LiteralPath $Roteiro -Encoding UTF8
  }
}
function GerarLinux {
  $linux = @'
#!/usr/bin/env bash
# SmartFactory GS - Etapa 10 / Linux Ubuntu 24.04 - Wazuh 4.14 all-in-one.
# Executar: sudo bash /mnt/sfsetup/01-Instalar-Configurar-Wazuh.sh
set -Eeuo pipefail
umask 077
DATA_MOUNT='/var/lib/wazuh-indexer'
PASTA='/root/smartfactory-wazuh'
REL='/var/log/smartfactory-wazuh-validacao.txt'
MIDIA='/mnt/sfsetup'
mkdir -p "$PASTA"; chmod 700 "$PASTA"
log(){ printf '%s | %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
falha(){ log "ERRO: $*"; exit 1; }
trap 'echo "Falha na linha $LINENO; consulte a console e o log protegido em /root/smartfactory-wazuh/." >&2' ERR
[[ $(id -u) -eq 0 ]] || falha 'Execute com sudo.'
. /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == '24.04' ]] || falha 'Exige Ubuntu Server 24.04 LTS.'
[[ "$(uname -m)" == 'x86_64' ]] || falha 'Exige arquitetura x86_64.'
[[ "$(hostname -s)" == 'vm-wazuh01' ]] || falha 'Hostname esperado: vm-wazuh01. Ajuste no instalador antes de continuar.'
IP=$(ip -4 -o addr show scope global | awk '{print $4}')
[[ "$IP" == *'10.20.110.10/24'* ]] || falha "IP atual fora da VLAN SOC: $IP"
if (( $(awk '/MemTotal/ {print $2}' /proc/meminfo) < 7000000 )); then
  falha 'O guest nao recebeu ~8 GiB. Nao tente instalar a pilha completa com 4 GiB.'
fi
log 'Ubuntu, IP e 8 GiB verificados.'
getent ahostsv4 packages.wazuh.com >/dev/null || falha 'DNS externo indisponivel. Confirme DNS 10.20.110.1 e regra pfSense.'
curl --silent --show-error --head --location --max-time 18 https://packages.wazuh.com/4.14/wazuh-install.sh >/dev/null || falha 'Nao ha saida HTTPS para repositorio Wazuh.'
log 'DNS e HTTPS externos OK. Instalando dependencias do Ubuntu.'
# A VLAN SOC so pode sair em 443; mudar mirrors Ubuntu de HTTP/80 para HTTPS/443.
for sourcefile in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do
  [[ -f "$sourcefile" ]] || continue
  sed -i -E 's#http://([A-Za-z0-9.-]*ubuntu.com/ubuntu)#https://\1#g' "$sourcefile"
done
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl gnupg ufw parted openssh-server
hostnamectl set-hostname vm-wazuh01
timedatectl set-timezone America/Sao_Paulo
# Disco de 80 GiB, separado do sistema, destinado a /var/lib/wazuh-indexer.
mapfile -t DATA_DISKS < <(lsblk -b -dn -o NAME,SIZE,TYPE | awk '$2==85899345920 && $3=="disk" {print "/dev/"$1}')
[[ ${#DATA_DISKS[@]} -eq 1 ]] || falha "Esperado um disco de dados VHDX de 80 GiB, encontrados ${#DATA_DISKS[@]}. Veja lsblk."
DISK="${DATA_DISKS[0]}"
if findmnt -rn "$DATA_MOUNT" >/dev/null; then
  log 'Volume Wazuh indexer ja montado.'
else
  if [[ -e /dev/disk/by-label/WAZUHIDX ]]; then
    PART=$(readlink -f /dev/disk/by-label/WAZUHIDX)
    [[ "$PART" == "${DISK}"* ]] || falha 'Label WAZUHIDX aponta para outro disco. Interrompido.'
  else
    [[ $(lsblk -nrpo TYPE "$DISK" | grep -c '^part$' || true) -eq 0 ]] || falha 'Disco de 80GB possui particoes existentes. Nao formatar.'
    [[ -z "$(wipefs -n "$DISK" 2>/dev/null)" ]] || falha 'Disco 80GB tem assinatura. Nao formatar.'
    log "Inicializando SOMENTE disco de dados vazio de 80GiB: $DISK"
    parted -s -a optimal "$DISK" mklabel gpt mkpart primary ext4 1MiB 100%
    partprobe "$DISK" || true
    udevadm settle
    PART=$(lsblk -nrpo NAME,TYPE "$DISK" | awk '$2=="part"{print $1; exit}')
    [[ -n "$PART" ]] || falha 'Particao de dados nao apareceu.'
    mkfs.ext4 -F -L WAZUHIDX "$PART"
  fi
  UUID=$(blkid -s UUID -o value "$PART")
  [[ -n "$UUID" ]] || falha 'Sem UUID no volume de dados.'
  mkdir -p "$DATA_MOUNT"
  if ! grep -q "UUID=${UUID} " /etc/fstab; then
    printf 'UUID=%s %s ext4 defaults,noatime 0 2\n' "$UUID" "$DATA_MOUNT" >> /etc/fstab
  fi
  mount "$DATA_MOUNT"
fi
[[ "$(findmnt -rn -o FSTYPE "$DATA_MOUNT")" == ext4 ]] || falha 'Indexer nao montado em ext4 separado.'
# Parametro documentado para indexacao; nao impor tuning de heap sem diagnostico.
printf 'vm.max_map_count=262144\n' > /etc/sysctl.d/99-smartfactory-wazuh.conf
sysctl --system >/dev/null
systemctl enable --now ssh >/dev/null
log 'Disco de dados separado e sysctl preparados.'
if dpkg-query -W -f='${Status}' wazuh-indexer 2>/dev/null | grep -q 'install ok installed'; then
  log 'Wazuh indexer ja instalado. Nao repetir assistente.'
else
  cd "$PASTA"
  curl --fail --silent --show-error --location -o wazuh-install.sh 'https://packages.wazuh.com/4.14/wazuh-install.sh'
  chmod 700 wazuh-install.sh
  log 'Iniciando instalacao Wazuh all-in-one 4.14 (indexer, manager, dashboard e filebeat).'
  log 'Saida integral e senhas guardadas somente no Linux, com permissoes root.'
  if ! bash ./wazuh-install.sh -a > "$PASTA/instalacao-sigilosa.log" 2>&1; then
    log 'Instalador falhou. Verifique o arquivo root-only instalacao-sigilosa.log.'
    tail -n 35 "$PASTA/instalacao-sigilosa.log" | sed -E 's/(Password|password|PASS|pass)([^:]*):.*/\1: [OCULTO]/g' >&2 || true
    exit 1
  fi
fi
chmod 700 "$PASTA"
find "$PASTA" -maxdepth 1 -type f -exec chmod 600 {} \;
# Regras de defesa em profundidade. Consoles locais sao o fallback caso SSH esteja indisponivel.
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow from 10.20.90.10 to any port 22 proto tcp comment 'SF PAW SSH' >/dev/null
ufw allow from 10.20.90.10 to any port 443 proto tcp comment 'SF PAW dashboard' >/dev/null
for NET in 20 30 40 50 60 70 80 90 100 120; do
  ufw allow from "10.20.${NET}.0/24" to any port 1514 proto tcp >/dev/null
  ufw allow from "10.20.${NET}.0/24" to any port 1515 proto tcp >/dev/null
done
ufw --force enable >/dev/null
log 'UFW aplicado: PAW 22/443, endpoints 1514/1515; API/indexer nao publicados.'
# Nao enviar credenciais Wazuh, chaves e certificados a FAT32 ou arquivos publicos.
{
  echo '=== SmartFactory Etapa 10: Wazuh, dados nao sigilosos ==='
  date -Is
  hostnamectl --static
  ip -4 -br a
  free -h
  df -h / "$DATA_MOUNT"
  echo '=== Wazuh versoes ==='
  dpkg-query -W -f='${Package} ${Version}\n' wazuh-manager wazuh-indexer wazuh-dashboard filebeat 2>&1 || true
  echo '=== Servicos ==='
  for svc in wazuh-manager wazuh-indexer wazuh-dashboard filebeat; do
    printf '%s: ' "$svc"; systemctl is-active "$svc" || true
  done
  echo '=== HTTPS local (somente status) ==='
  curl -sk -o /dev/null -w 'HTTP %{http_code}\n' --max-time 15 https://127.0.0.1/ || true
  echo '=== UFW ==='
  ufw status verbose
  echo '=== Escuta TCP ==='
  ss -lnt | grep -E ':(22|443|1514|1515|55000|9200)\b' || true
  echo '=== Linux hardening ==='
  aa-status --enabled >/dev/null 2>&1 && echo 'AppArmor: ativo' || echo 'AppArmor: verificar'
  sysctl vm.max_map_count
} > "$REL" 2>&1
chmod 600 "$REL"
if [[ -d "$MIDIA" && -w "$MIDIA" ]]; then
  cp -f "$REL" "$MIDIA/RESULTADO_WAZUH.txt"
  sync
fi
log 'Relatorio nao sigiloso criado no Ubuntu e copiado para a midia SFSETUP.'
cat "$REL"
for svc in wazuh-manager wazuh-indexer wazuh-dashboard filebeat; do
  systemctl is-active --quiet "$svc" || falha "Servico $svc nao esta ativo. Consulte journalctl -u $svc."
done
HTTP=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 20 https://127.0.0.1/ || true)
[[ "$HTTP" != '000' && -n "$HTTP" ]] || falha 'Dashboard nao respondeu em HTTPS local.'
log 'VALIDACAO INICIAL APROVADA: componentes ativos e HTTPS local respondendo.'
log 'CREDENCIAIS: use sudo tar -O -xf /root/smartfactory-wazuh/wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt SEM GRAVAR TELA.'
'@
  # Gravar sem UTF-8 BOM e com LF, para o bash no Ubuntu.
  $linux = $linux.Replace("`r`n", "`n")
  [IO.File]::WriteAllText($HostSh,$linux,(New-Object Text.UTF8Encoding($false)))
  Registrar "Script Linux gerado: $HostSh"
}
function PreencherMidia {
  $v = Get-VM -Name $NomeVM -ErrorAction Stop
  if($v.State -ne 'Off'){ throw 'Desligue a VM-WAZUH01 antes de montar o disco SFSETUP no host.' }
  if(-not(Test-Path -LiteralPath $Transfer)){ throw 'Disco de transferencia ausente. Execute CriarVM.' }
  GerarLinux
  $mounted = $false
  try {
    $vdisk = Mount-VHD -Path $Transfer -Passthru -ErrorAction Stop
    $mounted = $true
    $disk = $vdisk | Get-Disk
    if($disk.PartitionStyle -eq 'RAW'){
      Initialize-Disk -Number $disk.Number -PartitionStyle MBR -ErrorAction Stop | Out-Null
      $part = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter -ErrorAction Stop
      Format-Volume -DriveLetter $part.DriveLetter -FileSystem FAT32 -NewFileSystemLabel 'SFSETUP' -Confirm:$false -Force -ErrorAction Stop | Out-Null
    }
    $part = Get-Partition -DiskNumber $disk.Number | Where-Object DriveLetter | Select-Object -First 1
    if(-not $part){ throw 'Disco SFSETUP sem letra; interrompido.' }
    $vol = Get-Volume -DriveLetter $part.DriveLetter
    if($vol.FileSystemLabel -ne 'SFSETUP' -or $vol.FileSystem -ne 'FAT32'){
      throw 'O disco de transferencia nao tem label SFSETUP e FAT32. Nao sobrescrever.'
    }
    $drive = "{0}:\" -f $part.DriveLetter
    Copy-Item -LiteralPath $HostSh -Destination (Join-Path $drive '01-Instalar-Configurar-Wazuh.sh') -Force
    if(-not(Test-Path -LiteralPath (Join-Path $drive '01-Instalar-Configurar-Wazuh.sh'))){ throw 'Falha ao copiar o script Linux.' }
    Registrar "SFSETUP FAT32 preparado: $($part.DriveLetter):\"
  } finally {
    if($mounted){ Dismount-VHD -Path $Transfer -ErrorAction Stop }
  }
}
VerificarHost
GerarArquivos
switch($Acao){
 'Preparar' {
   VerificarVMs $false
   Registrar 'ETAPA 10 PREPARADA: FW01 Running; todas as outras VMs Off; Wazuh 8 GiB estatico recomendado.'
   Registrar "Roteiro: $Roteiro"
   Registrar "Relatorio: $Relatorio"
   Registrar 'ANTES de CriarVM, liberar DNS do 10.20.110.10 no DNS Resolver pfSense e regra em SECURITY_SOC.'
 }
 'CriarVM' {
   VerificarVMs $false
   if(Get-VM -Name $NomeVM -ErrorAction SilentlyContinue){ throw 'VM-WAZUH01 ja existe. Nao recriar.' }
   foreach($d in @($OS,$IDX,$Transfer)){
     if(Test-Path -LiteralPath $d){ throw "VHDX ja existe: $d. Nao sobrescrever." }
   }
   if(-not $IsoPath){
     $isoOptions = @(Get-ChildItem -LiteralPath (Join-Path $Base '01-ISOs') -Filter '*.iso' -File |
       Where-Object { $_.Name -match 'ubuntu.*24\.04|24\.04.*server' })
     if($isoOptions.Count -ne 1){ throw 'Informe -IsoPath com a ISO Ubuntu Server 24.04 LTS AMD64.' }
     $IsoPath = $isoOptions[0].FullName
   }
   if(-not(Test-Path -LiteralPath $IsoPath -PathType Leaf) -or $IsoPath -notmatch '\.iso$'){
     throw "ISO invalida: $IsoPath"
   }
   New-VM -Name $NomeVM -Generation 2 -Path $VMDir -MemoryStartupBytes 8GB `
      -NewVHDPath $OS -NewVHDSizeBytes 40GB -SwitchName 'SF-LAN' -ErrorAction Stop | Out-Null
   Set-VMProcessor -VMName $NomeVM -Count 4
   Set-VMMemory -VMName $NomeVM -DynamicMemoryEnabled $false -StartupBytes 8GB
   Set-VM -Name $NomeVM -AutomaticStopAction ShutDown -CheckpointType Disabled
   $nic = @(Get-VMNetworkAdapter -VMName $NomeVM)
   if($nic.Count -ne 1){ throw 'NIC inesperada na VM-WAZUH01.' }
   Rename-VMNetworkAdapter -VMName $NomeVM -Name $nic[0].Name -NewName 'SOC'
   Set-VMNetworkAdapterVlan -VMName $NomeVM -VMNetworkAdapterName 'SOC' -Access -VlanId 110
   Set-VMNetworkAdapter -VMName $NomeVM -VMNetworkAdapterName 'SOC' -RouterGuard On -DhcpGuard On
   $controllers = @(Get-VMScsiController -VMName $NomeVM | Select-Object -ExpandProperty ControllerNumber)
   if(1 -notin $controllers){ Add-VMScsiController -VMName $NomeVM | Out-Null }
   New-VHD -Path $IDX -Dynamic -SizeBytes 80GB -ErrorAction Stop | Out-Null
   New-VHD -Path $Transfer -Dynamic -SizeBytes 256MB -ErrorAction Stop | Out-Null
   Add-VMHardDiskDrive -VMName $NomeVM -ControllerType SCSI -ControllerNumber 1 -ControllerLocation 0 -Path $IDX
   Add-VMHardDiskDrive -VMName $NomeVM -ControllerType SCSI -ControllerNumber 1 -ControllerLocation 1 -Path $Transfer
   $dvd = Add-VMDvdDrive -VMName $NomeVM -Path $IsoPath -Passthru -ErrorAction Stop
   Set-VMFirmware -VMName $NomeVM -EnableSecureBoot On -SecureBootTemplate 'MicrosoftUEFICertificateAuthority' -FirstBootDevice $dvd
   PreencherMidia
   Registrar 'VM CRIADA: 4 vCPU, 8 GiB ESTATICOS, Ubuntu, 40G OS, 80G Indexer, 256M FAT32, VLAN110.'
   Registrar 'INSTALE Ubuntu somente no VHDX de 40 GiB; NAO FORMATE 80 GiB nem SFSETUP.'
   Registrar 'Durante instalacao Ubuntu configure DNS 10.20.110.1 (resolver pfSense) e IP 10.20.110.10/24.'
 }
 'GerarMidia' { VerificarVMs $true; PreencherMidia; Registrar 'MIDIA REGERADA. VM pode iniciar depois.' }
 'ValidarHost' {
   VerificarVMs $true
   $v = Get-VM -Name $NomeVM
   $vmMem = Get-VMMemory -VMName $NomeVM
   $firm = Get-VMFirmware -VMName $NomeVM
   $nic = Get-VMNetworkAdapterVlan -VMName $NomeVM -VMNetworkAdapterName 'SOC'
   $discs = @(Get-VMHardDiskDrive -VMName $NomeVM)
   Registrar "VM estado: $($v.State); 4vCPU: $((Get-VMProcessor -VMName $NomeVM).Count -eq 4)"
   Registrar "RAM dinamica: $($vmMem.DynamicMemoryEnabled); startup GiB: $($vmMem.Startup / 1GB)"
   Registrar "VLAN: $($nic.AccessVlanId); Secure Boot: $($firm.SecureBoot) template: $($firm.SecureBootTemplate)"
   Registrar "Discos VHDX: $($discs.Count)"
   if($vmMem.DynamicMemoryEnabled -or $vmMem.Startup -ne 8GB -or $nic.AccessVlanId -ne 110 -or $discs.Count -ne 3){
     throw 'Configuracao Hyper-V diferente do esperado.'
   }
   Registrar 'VALIDACAO HOST APROVADA. Status de Manager/Indexer/Dashboard requer validacao no Ubuntu.'
 }
 'ColetarResultados' {
   VerificarVMs $true
   $v = Get-VM -Name $NomeVM
   if($v.State -ne 'Off'){ throw 'Desligue WAZUH01 de forma normal antes de coletar resultados do FAT32.' }
   $mounted = $false
   try {
     $disk = Mount-VHD -Path $Transfer -ReadOnly -Passthru -ErrorAction Stop | Get-Disk
     $mounted = $true
     $part = Get-Partition -DiskNumber $disk.Number | Where-Object DriveLetter | Select-Object -First 1
     if(-not $part){ throw 'Nenhuma letra no SFSETUP.' }
     $src = '{0}:\RESULTADO_WAZUH.txt' -f $part.DriveLetter
     if(-not(Test-Path -LiteralPath $src)){ throw 'Linux ainda nao gerou RESULTADO_WAZUH.txt no SFSETUP.' }
     $dest = Join-Path $Base '09-Logs-Testes\12-WAZUH01-Resultado-Linux.txt'
     Copy-Item -LiteralPath $src -Destination $dest -Force
     Registrar "RELATORIO LINUX COLETADO: $dest"
     Add-Content -LiteralPath $Relatorio -Value ("`n## Resultado validacao Linux`nVer arquivo 09-Logs-Testes/12-WAZUH01-Resultado-Linux.txt. Nao incluiu credenciais Wazuh.") -Encoding UTF8
   } finally {
     if($mounted){ Dismount-VHD -Path $Transfer -ErrorAction SilentlyContinue }
   }
 }
}
