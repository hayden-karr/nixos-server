{ pkgs }:

pkgs.writeShellScript "wait-dns" ''
  set -euo pipefail
  for i in {1..120}; do
    if ${pkgs.host}/bin/host -W 2 cloudflare.com 1.1.1.1 >/dev/null 2>&1; then
      exit 0
    fi
    sleep 1
  done
  exit 0
''
