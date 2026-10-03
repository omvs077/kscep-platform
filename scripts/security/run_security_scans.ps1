# K.S.C.E.P. Platform Security Audit Runner (PowerShell)
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Running K.S.C.E.P. Platform Security Scans" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Gitleaks Check
Write-Host "`n[1/3] Checking Gitleaks..." -ForegroundColor Yellow
if (Get-Command gitleaks -ErrorAction SilentlyContinue) {
    gitleaks detect --config .gitleaks.toml --verbose
} else {
    Write-Host "gitleaks not found on PATH. Run via Docker: docker run --rm -v ${PWD}:/path zricethezav/gitleaks:latest dir /path" -ForegroundColor DarkGray
}

# 2. Trivy Misconfiguration Scan
Write-Host "`n[2/3] Checking Trivy Scanner..." -ForegroundColor Yellow
if (Get-Command trivy -ErrorAction SilentlyContinue) {
    trivy config --config trivy.yaml terraform/
} else {
    Write-Host "trivy not found on PATH. Run via Docker: docker run --rm -v ${PWD}:/root aquasec/trivy:latest fs /root" -ForegroundColor DarkGray
}

# 3. Kube-bench
Write-Host "`n[3/3] Kube-bench CIS Benchmark manifest..." -ForegroundColor Yellow
Write-Host "Manifest ready at security/kube-bench/job.yaml" -ForegroundColor Green
Write-Host "Run: kubectl apply -f security/kube-bench/job.yaml" -ForegroundColor White
