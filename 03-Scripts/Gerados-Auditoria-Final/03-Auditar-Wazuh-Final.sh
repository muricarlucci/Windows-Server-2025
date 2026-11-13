#!/usr/bin/env bash
# SmartFactory - auditoria nao destrutiva Wazuh 4.14.10; nao exporta credenciais.
set -u
OUT="/root/smartfactory-wazuh/AUDITORIA_WAZUH_FINAL.txt"
mkdir -p /root/smartfactory-wazuh
exec > >(tee "$OUT") 2>&1
printf 'SMARTFACTORY WAZUH AUDITORIA %s\n' "$(date -Is)"
cat /etc/os-release | grep -E '^(NAME|VERSION_ID)=' || true
hostnamectl --static || hostname
ip -br -4 addr || true
free -h
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS
printf '\nSTATUS DOS SERVICOS\n'
for svc in wazuh-manager wazuh-indexer wazuh-dashboard filebeat; do
  printf '%s: ' "$svc";systemctl is-active "$svc" 2>/dev/null || true
done
printf '\nDISCO INDEXER / MOUNT\n'
findmnt /var/lib/wazuh-indexer || true
df -h / /var/lib/wazuh-indexer || true
printf '\nHARDENING LINUX\n'
sysctl vm.max_map_count || true
sudo ufw status numbered || true
sudo aa-status --enabled || true
printf '\nPORTAS LOCAIS DE ESCUTA\n'
ss -lnt | grep -E '(:22 |:443 |:1514 |:1515 |:55000 |:9200 )' || true
printf '\nHTTPS LOCAL\n'
curl -sk -o /dev/null -w 'HTTP_CODE=%{http_code}\n' --max-time 10 https://127.0.0.1/ || true
printf '\nAGENTES CADASTRADOS\n'
/var/ossec/bin/agent_control -l 2>&1 | head -65 || true
printf '\nSSH CONFIGURACAO EFETIVA (sem segredos)\n'
/usr/sbin/sshd -T 2>/dev/null | grep -E '^(permitrootlogin|passwordauthentication|pubkeyauthentication)' || true
printf '\nVULNERABILITY (configuracao NAO comprova CVEs)\n'
grep -A 5 '<vulnerability-detection>' /var/ossec/etc/ossec.conf || true
printf '\nCONCLUSAO\nValidar Dashboard, agente online e alertas separadamente. ESTE ARQUIVO NAO PROVA INGESTAO WINDOWS.\n'
if mountpoint -q /mnt/sfsetup; then
  cp -f "$OUT" /mnt/sfsetup/AUDITORIA_WAZUH_FINAL.txt && sync && echo 'RELATORIO COPIADO PARA SFSETUP'
else
  echo 'SFSETUP nao montada: saida permanece em /root/smartfactory-wazuh/AUDITORIA_WAZUH_FINAL.txt'
fi