#!/bin/bash
# Installazione semplificata agente Wazuh

WAZUH_SERVER_IP="192.168.100.118"
AGENT_NAME="proxmox-$(hostname)"

# Installazione agente
apt-get update
apt-get install -y curl apt-transport-https gnupg
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | apt-key add -
echo "deb https://packages.wazuh.com/4.x/apt/ stable main" | tee /etc/apt/sources.list.d/wazuh.list
apt-get update
apt-get install -y wazuh-agent

# Configurazione e registrazione
sed -i "s/<address>.*<\/address>/<address>$WAZUH_SERVER_IP<\/address>/" /var/ossec/etc/ossec.conf
/var/ossec/bin/wazuh-control stop
rm -f /var/ossec/etc/client.keys
/var/ossec/bin/agent-auth -m $WAZUH_SERVER_IP -A "$AGENT_NAME"
/var/ossec/bin/wazuh-control start

echo "Agente installato e registrato come: $AGENT_NAME"
/var/ossec/bin/wazuh-control status
