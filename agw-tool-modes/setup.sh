#!/bin/bash
# Install a k3d cluster, Helm, kubectl, and the MCP inspector.
# The lesson installs enterprise agentgateway and applies the Gateway API CRDs.
# Runs as root after the common setup. /root/data is already on the disk.
# Docker is already enabled.
set -euo pipefail
trap '' HUP

export DEBIAN_FRONTEND=noninteractive
export HOME=/root

# mcp-inspector 2.9.0 needs Node >= 22.19. The pod in server-everything.yaml
# is a separate image and runs its own npx.
NODE_VERSION=22.23.3
INSPECTOR_VERSION=2.9.0

# Defaults from the lesson's chart, enterprise-agentgateway v2026.9.3.
# The proxy tag is the chart value, with no leading v.
CONTROLLER_IMAGE=us-docker.pkg.dev/solo-public/enterprise-agentgateway/enterprise-agentgateway-controller:2026.9.3
PROXY_IMAGE=us-docker.pkg.dev/solo-public/enterprise-agentgateway/agentgateway-enterprise:2026.9.3
# server-everything.yaml says node:20-alpine. kubelet looks that up as this name.
NODE_IMAGE=docker.io/library/node:20-alpine

echo "agw-tool-modes setup starting"

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

curl -fL --retry 3 -o /tmp/node.tar.gz \
  "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.gz"
tar -xzf /tmp/node.tar.gz -C /usr/local --strip-components=1
rm -f /tmp/node.tar.gz
hash -r
npm install -g "@modelcontextprotocol/inspector@${INSPECTOR_VERSION}"

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

# The channel redirects to the GitHub release page. The tag is the last part of that URL.
# 1.36 is the channel the kgateway lab already runs on this Firecracker guest.
# The enterprise chart does not declare a kubeVersion.
k3s_url=$(curl -fsSL -o /dev/null -w '%{url_effective}' https://update.k3s.io/v1-release/channels/v1.36)
k3s_version=$(basename "$k3s_url" | tr '+' '-')
if [ -z "$k3s_version" ] || [ "$k3s_version" = "null" ]; then
  echo "could not resolve the k3s 1.36 release" >&2
  exit 1
fi

k3d cluster create my-k8s-cluster \
  --image "rancher/k3s:${k3s_version}" \
  --api-port 6443 \
  --k3s-arg "--disable=traefik@server:0" \
  --port 80:80@loadbalancer \
  --port 443:443@loadbalancer

# Images the lesson pulls once the cluster is up: the controller and the proxy
# from the enterprise chart, and the MCP server image. The pod still runs
# npx, so that container needs outbound network after boot.
#
# k3d image import always loads the tar with ctr --all-platforms, and there
# is no flag to turn that off. The tar names the arm64 manifest, which was
# never downloaded, so ctr fails and k3d still exits 0. Import it ourselves
# and ask only for linux/amd64.
images="\
$CONTROLLER_IMAGE
$PROXY_IMAGE
$NODE_IMAGE"
node=k3d-my-k8s-cluster-server-0
for image in $images; do
  docker pull "$image"
  rm -f /tmp/lab-image.tar
  docker save "$image" -o /tmp/lab-image.tar
  docker cp /tmp/lab-image.tar "$node":/tmp/lab-image.tar
  docker exec "$node" ctr -n k8s.io images import --platform linux/amd64 /tmp/lab-image.tar
  docker exec "$node" rm -f /tmp/lab-image.tar
  rm -f /tmp/lab-image.tar
done
have=$(docker exec "$node" ctr -n k8s.io images ls -q)
for image in $images; do
  short=${image#docker.io/}
  if ! printf '%s\n' "$have" | grep -qx "$image" \
    && ! printf '%s\n' "$have" | grep -qx "$short"; then
    echo "image did not land in the node: $image" >&2
    printf '%s\n' "$have" >&2
    exit 1
  fi
done

metallb_version=$(curl -fsSL https://api.github.com/repos/metallb/metallb/releases/latest | jq -r .tag_name)
kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/${metallb_version}/config/manifests/metallb-native.yaml"
# The deployment and daemonset exist as soon as apply returns. A pod wait
# exits immediately when the pods have not been created yet.
kubectl -n metallb-system rollout status deployment/controller --timeout=300s
kubectl -n metallb-system rollout status daemonset/speaker --timeout=300s

# The lesson reads the gateway address from status.addresses. MetalLB hands
# that address out of the k3d docker network, which the guest can route to.
gateway_ip=$(docker network inspect k3d-my-k8s-cluster | jq -r '[.[0].IPAM.Config[].Gateway | select(test("^[0-9.]+$"))][0]')
prefix=${gateway_ip%.*}
kubectl apply -f - << EOF
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: k3d-pool
  namespace: metallb-system
spec:
  addresses:
  - ${prefix}.200-${prefix}.250
  autoAssign: true
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: k3d-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - k3d-pool
EOF

# The lesson runs from /root and uses these files by their short names.
# cp -a would copy data/'s owner and mode onto /root. sshd then ignores
# authorized_keys, and the login key is refused.
cp -r /root/data/. /root/
chown root:root /root
chmod 700 /root
mkdir -p /root/out

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
Description=Start the tool-modes lab cluster
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

echo "agw-tool-modes setup done"
