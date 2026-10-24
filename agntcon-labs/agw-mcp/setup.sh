#!/bin/bash
# Install agentgateway 1.6, Node, and the MCP inspector.
# Runs as root after the common setup. /root/data is already on the disk.
# The lesson starts the Everything server itself with npx.
set -euo pipefail
trap '' HUP

export HOME=/root

AGW_VERSION=1.6.0
NODE_VERSION=22.23.3
INSPECTOR_VERSION=2.9.0
EVERYTHING_VERSION=2026.8.31

echo "agw-mcp setup starting"

install_bin() {
  url=$1
  dest=$2
  curl -fL --retry 3 -o "$dest" "$url"
  chmod 755 "$dest"
}

curl -fL --retry 3 -o /tmp/node.tar.gz \
  "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.gz"
tar -xzf /tmp/node.tar.gz -C /usr/local --strip-components=1
rm -f /tmp/node.tar.gz
hash -r

npm install -g \
  "@modelcontextprotocol/inspector@${INSPECTOR_VERSION}" \
  "@modelcontextprotocol/server-everything@${EVERYTHING_VERSION}"

base="https://github.com/agentgateway/agentgateway/releases/download/v${AGW_VERSION}"
install_bin "${base}/agentgateway-linux-amd64" /usr/local/bin/agentgateway

# The lesson runs from /root and uses these files by their short names.
# cp -a would copy data/'s owner and mode onto /root. sshd then ignores
# authorized_keys, and the login key is refused.
cp -r /root/data/. /root/
chown root:root /root
chmod 700 /root

echo "agw-mcp setup done"
