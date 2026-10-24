#!/bin/bash
# Install agentgateway 1.6.
# Runs as root after the common setup. /root/data is already on the disk.
set -euo pipefail
trap '' HUP

export HOME=/root

AGW_VERSION=1.6.0

echo "agw-guardrails setup starting"

install_bin() {
  url=$1
  dest=$2
  curl -fL --retry 3 -o "$dest" "$url"
  chmod 755 "$dest"
}

base="https://github.com/agentgateway/agentgateway/releases/download/v${AGW_VERSION}"
install_bin "${base}/agentgateway-linux-amd64" /usr/local/bin/agentgateway

# The lesson runs from /root and uses these files by their short names.
# cp -a would copy data/'s owner and mode onto /root. sshd then ignores
# authorized_keys, and the login key is refused.
cp -r /root/data/. /root/
chown root:root /root
chmod 700 /root

echo "agw-guardrails setup done"
