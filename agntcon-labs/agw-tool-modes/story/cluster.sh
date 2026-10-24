#!/bin/bash
# The cluster is already started. The save is taken when the nodes are ready.
set -eu
kubectl wait --for=condition=ready node --all --timeout=180s
