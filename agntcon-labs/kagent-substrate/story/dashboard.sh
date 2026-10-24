#!/bin/bash
# The cluster is already started. The save is taken when the dashboard answers.
set -eu
i=0
while [ "$i" -lt 60 ]; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 http://127.0.0.1/ || true)
  if [ -n "$code" ] && [ "$code" != "000" ]; then
    exit 0
  fi
  i=$((i + 1))
  sleep 2
done
echo "dashboard is not listening on 127.0.0.1:80" >&2
exit 1
