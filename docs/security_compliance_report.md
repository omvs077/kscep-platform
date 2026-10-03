# K.S.C.E.P. Platform Security Hardening & Compliance Report

**Sprint:** Sprint 6 (Security Hardening & Compliance)  
**Classification:** Internal Confidential / SRE Security  
**Status:** Validated  

---

## 1. Executive Summary

This report establishes the baseline security posture and compliance validation for the **K.S.C.E.P. Platform** across Kubernetes infrastructure, network isolation, secrets lifecycle, container runtime security, and vulnerability scanning.

---

## 2. Zero-Trust Network Segmentation Matrix

All namespaces (`clickstream-pipeline`, `monitoring`, `keda`) enforce a default-deny ingress and egress posture (`default-deny-all`). Traffic is allowed strictly on an explicit white-list basis:

| Source Pod / Namespace | Destination Pod / Service | Port / Protocol | Rationale |
| :--- | :--- | :--- | :--- |
| `producer` | `kube-system` (CoreDNS) | `53/UDP, 53/TCP` | Cluster service discovery |
| `producer` | `kafka` | `9092/TCP` | High-throughput SASL event publishing |
| Ingress / External | `producer` | `8080/TCP` | Event ingestion & Admin UI |
| `spark` | `kube-system` (CoreDNS) | `53/UDP, 53/TCP` | Cluster service discovery |
| `spark` | `kafka` | `9092/TCP` | Consuming clickstream events & DLQ routing |
| `spark` | `postgres` | `5432/TCP` | Idempotent microbatch metric upserts |
| `grafana` | `kube-system` (CoreDNS) | `53/UDP, 53/TCP` | Cluster service discovery |
| `grafana` | `postgres` | `5432/TCP` | SELECT-only dashboard metric queries |
| `postgres-maintenance` | `postgres` | `5432/TCP` | Automated partition creation & backup jobs |
| `keda-operator` | `kafka` | `9092/TCP` | Topic consumer group lag polling |
| `keda-operator` | `kube-apiserver` | `443, 6443, 8443/TCP` | Horizontal pod autoscaling control |

---

## 3. Pod Security Standards (PSS) & Runtime Isolation

Workloads strictly adhere to the Kubernetes **Restricted** Pod Security Standard profile:

1. **Non-Root Execution:**
   - Producer runs as UID/GID `1000:1000`.
   - Spark runs as UID `1000` (`spark:spark`).
   - PostgreSQL runs as UID `70` (`postgres`).
   - `runAsNonRoot: true` is enforced on all pods.
2. **Privilege Escalation:**
   - `allowPrivilegeEscalation: false` enforced on all application containers.
3. **Capabilities:**
   - All default Linux capabilities dropped (`drop: ["ALL"]`).
4. **Filesystem Integrity:**
   - Read-only root filesystem (`readOnlyRootFilesystem: true`) on Producer with dedicated `/tmp` emptyDir.
   - Stateful persistent storage restricted to dedicated PVC mounts (`/opt/spark/checkpoints`, `/var/lib/postgresql/data`, `/backups`).

---

## 4. Secret Governance & Lifecycle

- **Zero Plaintext Secrets:** No passwords, SASL credentials, or tokens are committed to source control.
- **Terraform Random Generation:** Cryptographically strong passwords (16–24 characters) generated dynamically via `hashicorp/random`.
- **Role Isolation:**
  - `kafka-secrets`: Admin, Producer, Spark, and KEDA SCRAM credentials strictly separated.
  - `postgres-secrets`: Admin, `spark_writer` (INSERT/UPDATE), and `grafana_reader` (SELECT-only) passwords separated.
  - `producer-secrets`: Ingestion API key (`X-API-Key`).
- **Gitleaks Automated Gate:** Configured via `.gitleaks.toml` to prevent credential exposure in Git commits and pull requests.

---

## 5. Vulnerability & Benchmark Scanning

1. **Trivy Scanner:**
   - Configured via `trivy.yaml` targeting Terraform misconfigurations, container Dockerfiles, and Python dependency trees.
   - Scans run with severity thresholds `HIGH` and `CRITICAL`.
2. **CIS Kubernetes Benchmark (kube-bench):**
   - Packaged as a batch Job in `security/kube-bench/job.yaml`.
   - Verifies node, control plane, and policy conformance to CIS Benchmark 1.8.

---

## 6. Threat Modeling (STRIDE Matrix)

| Threat Category | Potential Attack Vector | K.S.C.E.P. Platform Countermeasure |
| :--- | :--- | :--- |
| **Spoofing** | Unauthorized entity publishing fraudulent events | Required `X-API-Key` authentication header + Kafka SASL SCRAM-SHA-512 authentication. |
| **Tampering** | Data alteration during transport or persistence | NetworkPolicy segmentation, strict JSON schema validation, DLQ isolation. |
| **Repudiation** | Denying event receipt or database modification | Atomic timestamping, offset checkpointing on PVC, audit logging. |
| **Information Disclosure** | Credential leakage or cross-pod data snooping | Non-root execution, role-based database privileges, encrypted secrets, default-deny netpols. |
| **Denial of Service** | Volumetric event flood overwhelming pipeline | Rate limiting (100 req/s), KEDA horizontal autoscaling, sliding window watermarks. |
| **Elevation of Privilege** | Container escape to host node | `allowPrivilegeEscalation: false`, dropped capabilities (`ALL`), non-root UIDs. |
