#!/bin/bash
# Install a k3d cluster, agentgateway 1.6.0, and the gateway that fronts
# the kagent dashboard. The lesson installs substrate 0.0.10 and kagent
# 0.10.0-rc1 from the kagent-dev charts. Runs as root after the common
# setup. /root/data is already on the disk. Docker is already enabled.
set -euo pipefail
trap '' HUP

export DEBIAN_FRONTEND=noninteractive
export HOME=/root

# These two stay on the versions the lesson was written against.
# agentgateway 1.6.0 documents Gateway API 1.6.0.
AGW_VERSION=v1.6.0
GATEWAY_API_VERSION=v1.6.0

echo "kagent-substrate setup starting"

install_bin() {
  url=$1
  dest=$2
  curl -fL --retry 3 -o "$dest" "$url"
  chmod 755 "$dest"
}

kubectl_version=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
install_bin "https://dl.k8s.io/release/${kubectl_version}/bin/linux/amd64/kubectl" /usr/local/bin/kubectl
k3d_version=$(curl -fsSL https://api.github.com/repos/k3d-io/k3d/releases/latest | jq -r .tag_name)
install_bin "https://github.com/k3d-io/k3d/releases/download/${k3d_version}/k3d-linux-amd64" /usr/local/bin/k3d
helm_version=$(curl -fsSL https://api.github.com/repos/helm/helm/releases/latest | jq -r .tag_name)
curl -fL --retry 3 -o /tmp/helm.tgz "https://get.helm.sh/helm-${helm_version}-linux-amd64.tar.gz"
tar -xzf /tmp/helm.tgz -C /tmp
install -m 755 /tmp/linux-amd64/helm /usr/local/bin/helm
rm -rf /tmp/helm.tgz /tmp/linux-amd64

kubectl completion bash > /usr/share/bash-completion/completions/kubectl
k3d completion bash > /usr/share/bash-completion/completions/k3d
helm completion bash > /usr/share/bash-completion/completions/helm

cat >> /root/.bashrc << 'EOF'

alias k=kubectl
# The completion file defines __start_kubectl and binds it to kubectl.
# bash-completion loads that file only when completing the kubectl command,
# so the alias needs the function loaded itself.
if [ -f /usr/share/bash-completion/completions/kubectl ]; then
  . /usr/share/bash-completion/completions/kubectl
  complete -o default -F __start_kubectl k
fi
EOF

# k3s and containerd watch a lot of files. The image defaults are too small.
cat > /etc/sysctl.d/99-inotify.conf << 'EOF'
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
EOF
sysctl --system >/dev/null

# 1.36 is the channel the other Kubernetes labs already run. agentgateway
# 1.6 supports Kubernetes 1.32 through 1.37.
k3s_url=$(curl -fsSL -o /dev/null -w '%{url_effective}' https://update.k3s.io/v1-release/channels/v1.36)
k3s_version=$(basename "$k3s_url" | tr '+' '-')
if [ -z "$k3s_version" ] || [ "$k3s_version" = "null" ]; then
  echo "could not resolve the k3s 1.36 release" >&2
  exit 1
fi

# Port 80 is the guest side of the kagent Dashboard link.
k3d cluster create my-k8s-cluster \
  --image "rancher/k3s:${k3s_version}" \
  --api-port 6443 \
  --k3s-arg "--disable=traefik@server:0" \
  --port 80:80@loadbalancer

kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
helm upgrade --install agentgateway-crds oci://cr.agentgateway.dev/charts/agentgateway-crds \
  --namespace agentgateway-system --create-namespace \
  --version "$AGW_VERSION"
helm upgrade --install agentgateway oci://cr.agentgateway.dev/charts/agentgateway \
  --namespace agentgateway-system \
  --version "$AGW_VERSION" \
  --wait

# The lesson reads minimal.yaml and sandbox-agent.yaml from the home
# directory. cp -a would copy data/'s owner and mode onto /root. sshd
# then ignores authorized_keys, and the login key is refused.
cp -r /root/data/. /root/
chown -R root:root /root
chmod 700 /root

# The route names kagent-ui, which the lesson's helm install creates.
# The gateway has no hostname: the catalog sends Host 80-<session>.runlabs.io,
# and that name is not known while this disk is built.
kubectl create namespace kagent
kubectl apply -f /root/gtw.yaml
kubectl apply -f /root/kagent-route.yaml
kubectl wait --for=condition=Programmed gateway/ingress-gateway --timeout=300s

ready=0
i=0
while [ "$i" -lt 60 ]; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 http://127.0.0.1/ || true)
  if [ -n "$code" ] && [ "$code" != "000" ]; then
    ready=1
    break
  fi
  i=$((i + 1))
  sleep 2
done
if [ "$ready" != 1 ]; then
  echo "gateway is not listening on 127.0.0.1:80" >&2
  exit 1
fi

# The cluster is stopped in the image. Booting the microVM starts it again,
# and ssh waits for that so the lesson opens with kubectl already working.
# Firecracker has no /dev/kmsg. k3s refuses to start until the link exists.
# The docker service returns before dockerd is listening.
cat > /usr/local/sbin/k3d-lab-start << 'EOF'
#!/bin/sh
set -eu
if [ ! -e /dev/kmsg ]; then
  ln -s /dev/console /dev/kmsg
fi
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
exec k3d cluster start my-k8s-cluster
EOF
chmod 755 /usr/local/sbin/k3d-lab-start

if systemctl cat ssh.service >/dev/null 2>&1; then
  ssh_unit=ssh.service
elif systemctl cat sshd.service >/dev/null 2>&1; then
  ssh_unit=sshd.service
else
  echo "no ssh service on this image" >&2
  exit 1
fi

cat > /etc/systemd/system/k3d-cluster.service << EOF
[Unit]
Description=Start the kagent lab cluster
After=docker.service
Requires=docker.service
Before=${ssh_unit}

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/k3d-lab-start

[Install]
WantedBy=multi-user.target
EOF
mkdir -p "/etc/systemd/system/${ssh_unit}.d"
cat > "/etc/systemd/system/${ssh_unit}.d/k3d.conf" << EOF
[Unit]
After=k3d-cluster.service
Requires=k3d-cluster.service
EOF
systemctl daemon-reload
systemctl enable k3d-cluster.service
systemctl enable "$ssh_unit"
systemctl disable ssh.socket || true

k3d cluster stop my-k8s-cluster

echo "kagent-substrate setup done"
