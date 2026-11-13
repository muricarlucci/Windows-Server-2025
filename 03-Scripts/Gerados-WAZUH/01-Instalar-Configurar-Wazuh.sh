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