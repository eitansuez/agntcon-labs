#!/bin/bash
# The cluster is already started. The save is taken when kgateway is up.
set -eu
kubectl rollout status -n kgateway-system deploy/kgateway --timeout=180s
