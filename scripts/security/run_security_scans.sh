#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo " Running K.S.C.E.P. Platform Security Scans"
echo "=========================================="

# 1. Gitleaks Scan
echo ""
echo "[1/3] Running Gitleaks Secret Detection..."
if command -v gitleaks &> /dev/null; then
    gitleaks detect --config .gitleaks.toml --verbose || echo "Gitleaks reported potential secrets."
else
    echo "gitleaks not installed. Run via Docker: docker run -v \$(pwd):/path zricethezav/gitleaks:latest dir /path"
fi

# 2. Trivy Filesystem & Misconfiguration Scan
echo ""
echo "[2/3] Running Trivy Misconfiguration & Vulnerability Scan..."
if command -v trivy &> /dev/null; then
    trivy config --config trivy.yaml terraform/
    trivy fs --config trivy.yaml .
else
    echo "trivy not installed. Run via Docker: docker run -v \$(pwd):/root aquasec/trivy:latest fs /root"
fi

# 3. Kube-bench CIS Benchmark
echo ""
echo "[3/3] Checking Kube-bench CIS Kubernetes Benchmark Job..."
echo "To execute kube-bench in cluster: kubectl apply -f security/kube-bench/job.yaml"
echo "Done."
