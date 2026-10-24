#!/bin/bash
# Install agentgateway 1.6 and the rate-limit stack.
# Runs as root after the common setup. /root/data is already on the disk.
# Docker is already enabled. The containers are pulled here and started on
# each boot, so the golden disk does not keep them running.
set -euo pipefail
trap '' HUP

export DEBIAN_FRONTEND=noninteractive
export HOME=/root

AGW_VERSION=1.6.0

echo "agw-cost-mgmt setup starting"

if ! docker compose version >/dev/null 2>&1; then
  apt-get update
  apt-get install -y docker-compose-v2
fi

install_bin() {
  url=$1
  dest=$2
  curl -fL --retry 3 -o "$dest" "$url"
  chmod 755 "$dest"
}

base="https://github.com/agentgateway/agentgateway/releases/download/v${AGW_VERSION}"
install_bin "${base}/agentgateway-linux-amd64" /usr/local/bin/agentgateway
install_bin "${base}/agctl-linux-amd64" /usr/local/bin/agctl

# The lesson runs from /root and copies these files by their short names.
# cp -a would copy data/'s owner and mode onto /root. sshd then ignores
# authorized_keys, and the login key is refused.
cp -r /root/data/. /root/
chown root:root /root
chmod 700 /root

cd /root
docker compose pull

# ssh waits for this, so the rate-limit server is up when the lesson opens.
# The docker service returns before dockerd is listening.
cat > /usr/local/sbin/agw-cost-start << 'EOF'
#!/bin/sh
set -eu
i=0
while [ "$i" -lt 60 ]; do
  if docker info >/dev/null 2>&1; then
    break
  fi
  i=$((i + 1))
  sleep 1
done
if ! docker info >/dev/null 2>&1; then
  echo "dockerd did not start" >&2
  exit 1
fi
cd /root
exec docker compose up -d
EOF
chmod 755 /usr/local/sbin/agw-cost-start

if systemctl cat ssh.service >/dev/null 2>&1; then
  ssh_unit=ssh.service
elif systemctl cat sshd.service >/dev/null 2>&1; then
  ssh_unit=sshd.service
else
  echo "no ssh service on this image" >&2
  exit 1
fi

cat > /etc/systemd/system/agw-cost.service << EOF
[Unit]
Description=Start the agentgateway rate-limit stack
After=docker.service
Requires=docker.service
Before=${ssh_unit}

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/agw-cost-start

[Install]
WantedBy=multi-user.target
EOF
mkdir -p "/etc/systemd/system/${ssh_unit}.d"
cat > "/etc/systemd/system/${ssh_unit}.d/agw-cost.conf" << EOF
[Unit]
After=agw-cost.service
Requires=agw-cost.service
EOF
systemctl daemon-reload
systemctl enable agw-cost.service
systemctl enable "$ssh_unit"
systemctl disable ssh.socket || true

echo "agw-cost-mgmt setup done"
