#!/usr/bin/env bash
# Pre-commit hook: block plaintext secret material from being committed.
set -euo pipefail

failed=0

for f in "$@"; do
  # Block age private keys
  if grep -qP "^AGE-SECRET-KEY-" "$f" 2>/dev/null; then
    echo "ERROR: age private key detected in $f" >&2
    failed=1
  fi

  # Block unencrypted sops yaml files (sops metadata present but no mac/encrypted_regex)
  if [[ "$f" == *.yaml ]] && grep -q "^sops:" "$f" 2>/dev/null && ! grep -q "mac:" "$f" 2>/dev/null; then
    echo "ERROR: possible unencrypted sops file: $f" >&2
    failed=1
  fi

  # Block raw private keys (SSH, RSA, EC)
  if grep -qP -e "-----BEGIN (EC |RSA |OPENSSH )?PRIVATE KEY-----" "$f" 2>/dev/null; then
    echo "ERROR: private key material detected in $f" >&2
    failed=1
  fi
done

exit $failed
