#!/usr/bin/env bash
set -Eeuo pipefail
# Etapa12: NAO reinstala Wazuh, nao altera indexer heap, UFW ou autenticacao SSH por senha.
[[ "${EUID}" -eq 0 ]] || { echo 'Execute com sudo.' >&2; exit 1; }
OUT='/root/smartfactory-wazuh/ETAPA12-RESULTADO.txt'
mkdir -p /root/smartfactory-wazuh
chmod 700 /root/smartfactory-wazuh
{
 echo '=== SmartFactory | Etapa12 | Auditoria Wazuh/Linux ==='
 date -Is
 hostnamectl --static
 lsb_release -ds || true
 ip -4 -br address
 free -h
 df -h / /var/lib/wazuh-indexer
 echo '-- Pacotes Wazuh --'
 dpkg-query -W -f='${Package} ${Version}\n' wazuh-manager wazuh-indexer wazuh-dashboard filebeat || true
 echo '-- Servicos --'
 for svc in wazuh-manager wazuh-indexer wazuh-dashboard filebeat; do
   printf '%s: ' "$svc"
   systemctl is-active "$svc" || true
 done
 echo '-- Modulos Wazuh (nao contem senhas) --'
 grep -A 3 -B 1 '<vulnerability-detection>' /var/ossec/etc/ossec.conf || true
 echo '-- Firewall --'
 ufw status verbose
 echo '-- AppArmor --'
 if aa-status --enabled >/dev/null 2>&1; then echo 'AppArmor ativo'; else echo 'AppArmor indisponivel'; fi
 echo '-- Ajuste do indexador --'
 sysctl vm.max_map_count
} > "$OUT" 2>&1
# Endurecimento seguro: root remoto proibido, sem cortar password auth do operador sfadmin.
mkdir -p /etc/ssh/sshd_config.d
CONF='/etc/ssh/sshd_config.d/60-smartfactory-root.conf'
if [[ ! -f "$CONF" ]]; then
  printf 'PermitRootLogin no\n' > "$CONF"
  chmod 644 "$CONF"
fi
if /usr/sbin/sshd -t; then
  systemctl reload ssh
  echo 'SSH root remoto: proibido via config SmartFactory' >> "$OUT"
else
  rm -f "$CONF"
  echo 'ALERTA: sshd -t falhou; arquivo de hardening revertido.' >> "$OUT"
  exit 1
fi
# Configuracoes originais preservadas, inclusive senhas e certificados.
if ! systemctl is-active --quiet wazuh-manager; then echo 'ERRO: manager inativo' >> "$OUT"; exit 1; fi
if ! systemctl is-active --quiet wazuh-indexer; then echo 'ERRO: indexer inativo' >> "$OUT"; exit 1; fi
if ! systemctl is-active --quiet wazuh-dashboard; then echo 'ERRO: dashboard inativo' >> "$OUT"; exit 1; fi
if ! systemctl is-active --quiet filebeat; then echo 'ERRO: filebeat inativo' >> "$OUT"; exit 1; fi
CODE=$(curl -sk --max-time 15 -o /dev/null -w '%{http_code}' https://127.0.0.1/ || true)
if [[ -z "$CODE" || "$CODE" == 000 ]]; then echo 'ERRO: HTTPS Dashboard nao respondeu' >> "$OUT"; exit 1; fi
printf 'HTTPS local: HTTP %s\n' "$CODE" >> "$OUT"
echo 'AUDITORIA ETAPA12 CONCLUIDA: servicos ativos, SSH root restrito.' >> "$OUT"
chmod 600 "$OUT"
cat "$OUT"
# Salvar evidencia sem credenciais somente em midia local montada.
if mountpoint -q /mnt/sfsetup && [[ -w /mnt/sfsetup ]]; then
  cp "$OUT" /mnt/sfsetup/RESULTADO_ETAPA12_LINUX.txt
  sync
  echo 'Resultado exportado para SFSETUP.'
else
  echo 'SFSETUP nao montada para escrita; evidencia permanece em /root/smartfactory-wazuh/ETAPA12-RESULTADO.txt.'
fi