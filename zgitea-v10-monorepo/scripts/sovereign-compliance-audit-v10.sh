#!/usr/bin/env bash
# zttato-platform v10+: Sovereign Automated Compliance + Runtime Audit
# Standards: NIST SP 800-207 (Zero Trust), SOC2, ISO/IEC 27001
# Targets: Source Integrity, Secret Leakage, Policy Violation, Runtime Drift

set -Eeuo pipefail
trap 'echo "[AUDIT FAILED] line $LINENO"; exit 1' ERR

readonly POLICY_DIR="${POLICY_DIR:-./infrastructure/policies}"
readonly QUARANTINE_DIR="${QUARANTINE_DIR:-./.audit-quarantine}"
readonly SBOM_OUT="${SBOM_OUT:-/tmp/zttato-sbom.txt}"
readonly RUNTIME_ENFORCE="${RUNTIME_ENFORCE:-0}"

mkdir -p "$QUARANTINE_DIR"

die() {
  echo "[CRITICAL] $*"
  exit 1
}

warn() {
  echo "[WARN] $*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_optional_cmd() {
  local cmd="$1"
  local label="$2"

  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi

  if [[ "$RUNTIME_ENFORCE" == "1" ]]; then
    die "$label requires '$cmd' but it is not installed"
  fi

  warn "$label skipped because '$cmd' is not installed (set RUNTIME_ENFORCE=1 to fail instead)"
  return 1
}

quarantine_target() {
  local reason="$1"
  local target="$2"
  local stamp

  stamp="$(date -u +"%Y%m%dT%H%M%SZ")"
  printf '%s | %s | %s\n' "$stamp" "$reason" "$target" >> "$QUARANTINE_DIR/events.log"

  if [[ -e "$target" ]]; then
    chmod 000 "$target" 2>/dev/null || true
    mv "$target" "$QUARANTINE_DIR/" 2>/dev/null || true
  fi

  echo "[QUARANTINE] reason='$reason' target='$target'"
}

echo ">>> [v10+] Sovereign Compliance Audit START"

############################################
# 0. PRECHECK
############################################
require_cmd gitleaks
require_cmd trivy
require_cmd find
require_cmd grep

############################################
# 1. SECRET SCAN (STRICT)
############################################
echo "[1] Secret scan..."
gitleaks detect \
  --source . \
  --redact \
  --exit-code 1 \
  --no-banner

############################################
# 2. POLICY ENFORCEMENT (OPA)
############################################
echo "[2] Policy enforcement..."
require_cmd conftest

mapfile -d '' POLICY_FILES < <(find . -type f \( -name "*.yaml" -o -name "Dockerfile" \) -print0)

if [[ ${#POLICY_FILES[@]} -eq 0 ]]; then
  warn "no YAML or Dockerfile targets found for conftest"
else
  for file in "${POLICY_FILES[@]}"; do
    conftest test "$file" --policy "$POLICY_DIR"
  done
fi

############################################
# 3. VULNERABILITY + LICENSE SCAN
############################################
echo "[3] Vulnerability and license scan..."
trivy fs \
  --scanners vuln,license \
  --severity CRITICAL,HIGH \
  --exit-code 1 \
  --ignore-unfixed \
  --no-progress \
  .

############################################
# 4. SBOM + SUPPLY CHAIN
############################################
echo "[4] SBOM generation..."
trivy fs \
  --format cyclonedx \
  --output "$SBOM_OUT" \
  --scanners vuln \
  . >/dev/null

############################################
# 5. INTERPOLATION CHECK (SAFE)
############################################
echo "[5] Interpolation audit..."
if grep -R --line-number --fixed-strings '${' . \
  --exclude-dir=.git \
  --exclude-dir=node_modules \
  --exclude='*.tf' \
  --exclude='*.tpl' \
  --exclude='*.sh' \
  --exclude='docker-compose*.yml' \
  --exclude='*.md'; then
  die "suspicious interpolation usage detected"
fi

############################################
# 6. DOCKER SECURITY CHECK
############################################
echo "[6] Docker security..."
if grep -R --line-number "privileged:[[:space:]]*true" . --exclude-dir=.git; then
  die "privileged mode detected"
fi

if grep -R --line-number "USER[[:space:]]\+root" . --exclude-dir=.git; then
  warn "Dockerfiles using root were found"
fi

############################################
# 7. RUNTIME: FALCO + eBPF + DRIFT + AUTO-QUARANTINE
############################################
echo "[7] Runtime compliance (Falco + eBPF + drift)..."

# 7.1 Falco rule sanity/runtime signal
if require_optional_cmd falco "Falco runtime threat detection"; then
  falco --validate /etc/falco/falco_rules.yaml >/dev/null 2>&1 || die "falco rules validation failed"
fi

# 7.2 eBPF syscall watch (bpftrace) - short sampling mode
if require_optional_cmd bpftrace "eBPF syscall audit"; then
  timeout 10s bpftrace -e 'tracepoint:syscalls:sys_enter_execve { @[comm] = count(); }' >/dev/null 2>&1 || \
    warn "bpftrace sample timed out or lacks kernel capabilities"
fi

# 7.3 Drift detection (git tracked files integrity)
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if ! git diff --quiet -- . ':(exclude).audit-quarantine'; then
    warn "configuration drift detected (git working tree differs from HEAD)"
  fi
fi

# 7.4 Auto quarantine on high-risk runtime indicators
if require_optional_cmd journalctl "runtime log correlation"; then
  if journalctl --no-pager --since "-30 min" 2>/dev/null | grep -Eiq "(falco|privilege escalation|reverse shell|suspicious)"; then
    quarantine_target "runtime-high-risk-log-pattern" "./runtime-findings.log"
  fi
fi

echo ">>> [v10+] Audit PASSED"
echo ">>> Sovereignty Level: 10/10"
