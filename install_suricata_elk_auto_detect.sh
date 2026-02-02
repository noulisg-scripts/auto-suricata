#!/bin/bash
set -e

# install_suricata_elk_auto_detect.sh
# Debian 12 | NAT + VMnet2 Promisc | Suricata + ELK + EveBox

[[ $EUID -ne 0 ]] && echo "Run as root" && exit 1

echo "🔎 Detecting network interfaces..."

ENS33=$(ip route | awk '/default/ {print $5; exit}')
ENS34=$(ip -o link show | awk -F': ' '{print $2}' | grep -Ev "lo|$ENS33" | head -n1)

if [[ -z "$ENS33" || -z "$ENS34" ]]; then
    echo "❌ Could not detect interfaces"
    exit 1
fi

echo "✅ NAT interface: $ENS33"
echo "✅ Monitor interface: $ENS34"

# -------------------------
# Base system
# -------------------------
apt update
apt install -y curl wget gnupg ca-certificates net-tools lsb-release \
               htop iftop nmap tcpdump software-properties-common

# -------------------------
# XFCE Desktop
# -------------------------
DEBIAN_FRONTEND=noninteractive apt install -y xfce4 xfce4-goodies lightdm firefox-esr
systemctl enable lightdm

# -------------------------
# Configure monitoring NIC
# -------------------------
ENS34_IP="192.168.50.30"
ENS34_NETMASK="24"

echo "🛠 Configuring $ENS34 static IP..."

nmcli dev set "$ENS34" managed yes || true
nmcli con delete "$ENS34" 2>/dev/null || true
nmcli con add type ethernet ifname "$ENS34" con-name "$ENS34" \
  ip4 "$ENS34_IP/$ENS34_NETMASK" autoconnect yes
nmcli con up "$ENS34"

# Force promisc
ip link set "$ENS34" promisc on

# -------------------------
# Suricata
# -------------------------
apt install -y suricata
suricata-update

sed -i "s|^ *- interface:.*|- interface: $ENS34|" /etc/suricata/suricata.yaml

systemctl enable suricata
systemctl restart suricata

# -------------------------
# Elastic Stack Repo
# -------------------------
mkdir -p /etc/apt/keyrings
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch \
  | gpg --dearmor -o /etc/apt/keyrings/elastic.gpg

echo "deb [signed-by=/etc/apt/keyrings/elastic.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" \
  > /etc/apt/sources.list.d/elastic-8.x.list

apt update
apt install -y elasticsearch logstash kibana filebeat

# -------------------------
# Filebeat Suricata Module
# -------------------------
filebeat modules enable suricata
filebeat setup

systemctl enable elasticsearch logstash kibana filebeat
systemctl start elasticsearch logstash kibana filebeat

# -------------------------
# EveBox
# -------------------------
wget -q https://github.com/jasonish/evebox/releases/download/v0.10.5/evebox_0.10.5_linux_amd64.deb
dpkg -i evebox_0.10.5_linux_amd64.deb || apt -f install -y

systemctl enable evebox
systemctl start evebox

# -------------------------
# Final Info
# -------------------------
echo "--------------------------------------------"
echo "✅ Installation complete!"
echo "NAT interface: $ENS33"
echo "Monitor interface: $ENS34 (Promisc ON)"
echo "Monitor IP: $ENS34_IP"
echo ""
echo "Kibana:  http://$ENS34_IP:5601"
echo "EveBox:  http://$ENS34_IP:5636"
echo "Logs:    /var/log/suricata/eve.json"
echo ""
echo "💡 Reboot recommended: sudo reboot"
echo "--------------------------------------------"
