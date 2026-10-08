#!/bin/bash
# Install the toolchain, check out the workshop fork, and warm the local
# registry with the system and the counter demo. The kind cluster is created
# here and then deleted. The registry container stays, with restart
# always, so the learner's create-kind-cluster.sh pulls images that are
# already on the disk. Runs as root after the common setup. /root/data
# is already on the disk. Docker is already enabled.
set -euo pipefail
trap '' HUP

export DEBIAN_FRONTEND=noninteractive
export HOME=/root
export PATH="/usr/local/go/bin:${PATH}"

# esuez/workshop-patches on 2026-10-07. go.mod at this commit requires go 1.27.0.
SUBSTRATE_REMOTE=https://github.com/eitansuez/substrate.git
SUBSTRATE_REV=c64f3742c809cb8a15a097784bd1b7381c51e38e
GO_VERSION=1.27.0

echo "agent-substrate setup starting"

install_bin() {
  url=$1
  dest=$2
  curl -fL --retry 3 -o "$dest" "$url"
  chmod 755 "$dest"
}

apt-get update
apt-get install -y git build-essential pkg-config

curl -fL --retry 3 -o /tmp/go.tgz "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
rm -rf /usr/local/go
tar -C /usr/local -xzf /tmp/go.tgz
rm -f /tmp/go.tgz
ln -sfn /usr/local/go/bin/go /usr/local/bin/go
ln -sfn /usr/local/go/bin/gofmt /usr/local/bin/gofmt

# kubectl resolves to latest stable during the build. The cluster version
# comes from the kind node image the checkout pins, not from this binary.
kubectl_version=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
install_bin "https://dl.k8s.io/release/${kubectl_version}/bin/linux/amd64/kubectl" /usr/local/bin/kubectl
kubectl completion bash > /usr/share/bash-completion/completions/kubectl

# kind and containerd watch a lot of files. The image defaults are too small.
cat > /etc/sysctl.d/99-inotify.conf << 'EOF'
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
EOF
sysctl --system >/dev/null

# The lesson runs from /root and opens this layout by its short name.
# cp -a would copy data/'s owner and mode onto /root. sshd then ignores
# authorized_keys, and the login key is refused.
cp -r /root/data/. /root/
chown root:root /root
chmod 700 /root

# ko must not try to pull a base image through the GCE metadata server.
# The learner's install runs in an interactive shell, so bashrc needs
# these too. kubectl ate lands in /root/go/bin when go install uses the
# default location.
cat >> /root/.bashrc << 'EOF'

export GCE_METADATA_HOST=127.0.0.1
export GCE_METADATA_IP=127.0.0.1
export GOOGLE_APPLICATION_CREDENTIALS=/dev/null

export PATH="$PATH:$HOME/go/bin"

# The installer's own default wait is 60s per deployment. The router can
# still be coming up when that minute ends.
export ATE_INSTALL_ROLLOUT_TIMEOUT=5m

alias k=kubectl
# The completion file defines __start_kubectl and binds it to kubectl.
# bash-completion loads that file only when completing the kubectl command,
# so the alias needs the function loaded itself.
if [ -f /usr/share/bash-completion/completions/kubectl ]; then
  . /usr/share/bash-completion/completions/kubectl
  complete -o default -F __start_kubectl k
fi
EOF

export GCE_METADATA_HOST=127.0.0.1
export GCE_METADATA_IP=127.0.0.1
export GOOGLE_APPLICATION_CREDENTIALS=/dev/null

git init /root/substrate
git -C /root/substrate remote add origin "$SUBSTRATE_REMOTE"
git -C /root/substrate fetch --depth 1 origin "$SUBSTRATE_REV"
git -C /root/substrate checkout --detach FETCH_HEAD
got=$(git -C /root/substrate rev-parse HEAD)
if [ "$got" != "$SUBSTRATE_REV" ]; then
  echo "substrate checkout is $got" >&2
  exit 1
fi

cd /root/substrate

# The installer's default rollout wait is 60s per deployment. On this build
# VM the router alone took 52s, so a later deployment can still be pulling
# its image when the minute ends.
export ATE_INSTALL_ROLLOUT_TIMEOUT=5m

# Print the namespace when a deploy fails. The build VM is deleted
# afterward, and this log is the only record of why a pod stayed down.
diagnose_ns() {
  ns=$1
  echo "----- pods in ${ns} -----"
  kubectl get pods -n "$ns" -o wide || true
  echo "----- events in ${ns} -----"
  kubectl get events -n "$ns" --sort-by=.lastTimestamp || true
  kubectl get pods -n "$ns" -o name | while read -r pod; do
    phase=$(kubectl get -n "$ns" "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    ready=$(kubectl get -n "$ns" "$pod" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || true)
    if [ "$phase" != "Running" ] || [ "$ready" != "true" ]; then
      echo "----- describe ${pod} -----"
      kubectl describe -n "$ns" "$pod" || true
      echo "----- logs ${pod} -----"
      kubectl logs -n "$ns" "$pod" --all-containers --tail=40 || true
    fi
  done
}

# Build the system and the counter demo, then remove the demo and the
# cluster. The images stay in kind-registry. The lesson does not use the
# other demos.
./hack/create-kind-cluster.sh
if ! ./hack/install-ate-kind.sh --atenet-dataplane=agentgateway --deploy-ate-system \
  --credential-provider='{"name":"k8s.io"}'; then
  diagnose_ns ate-system
  exit 1
fi
GOBIN=/usr/local/bin go install ./cmd/kubectl-ate

if ! ./hack/install-ate-kind.sh --deploy-demo-counter; then
  diagnose_ns ate-system
  diagnose_ns ate-demo-counter
  exit 1
fi
./hack/install-ate-kind.sh --delete-demo-counter

./hack/kind.sh delete cluster --name kind
if [ "$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' kind-registry)" != "always" ]; then
  echo "kind-registry is not set to restart" >&2
  exit 1
fi

echo "agent-substrate setup done"
