# Software Requirements Document (SRD)

## Project Name: K.S.C.E.P. Platform
**System Requirements, Interface Specifications & Architecture Contracts**

---

### 1. System Scope & Environment Constraints
K.S.C.E.P. is designed to operate on single-node Minikube clusters in constrained environments (e.g. 2 vCPUs, 3–4 GB RAM) while maintaining production-grade cloud architectural patterns.

#### Host / Cluster Constraints
- **Platform:** Kubernetes v1.28+ (Minikube with Docker driver)
- **Host System:** Windows 10/11 with WSL2 / Docker Engine
- **Resource Envelope:**
  - Cluster CPU: 2 Cores
  - Cluster RAM: ~3072 MB - 3800 MB
  - Storage: Minikube `standard` StorageClass (Hostpath dynamic provisioner)
- **Namespaces:**
  - `clickstream-pipeline`: Core streaming workloads (Producer, Kafka, Spark, PostgreSQL)
  - `monitoring`: Observability stack (Prometheus, Grafana, Loki)

---

### 2. Interface Specifications

#### 2.1 Ingestion API (Producer Service)
- **Protocol:** HTTP/1.1 (JSON)
- **Endpoints:**
  - `POST /api/v1/events`: Ingests single clickstream event
  - `GET /healthz`: Kubernetes liveness/readiness probe (returns HTTP 200)
  - `GET /metrics`: Prometheus metrics endpoint
- **Security:** Header `X-API-Key: <secret-token>` required on mutation endpoints.
- **Event Contract (`schemas/event_v1.json`):**
  ```json
  {
    "schema_version": "1.0",
    "event_id": "UUID (RFC 4122)",
    "user_id": "string (1-64 chars)",
    "session_id": "string (1-64 chars)",
    "event_type": "page_view | cart_add | purchase | page_exit",
    "page_url": "string (valid URI path)",
    "product_id": "string (optional)",
    "product_category": "string (optional)",
    "price_inr": "number >= 0.0 (optional)",
    "timestamp": "ISO-8601 UTC string"
  }
  ```

#### 2.2 Kafka Broker & Topic Contracts
- **Broker Mode:** Apache Kafka 3.6+ KRaft (ZooKeeper-less)
- **Security Protocol:** `SASL_PLAINTEXT` (internal cluster communication) with `SCRAM-SHA-512`
- **Topics:**
  1. `clickstream-events`: 6 partitions, RF=1, cleanup.policy=delete, retention.ms=86400000 (24h).
  2. `clickstream-events-dlq`: 6 partitions, RF=1, cleanup.policy=delete, retention.ms=604800000 (7d).
- **ACL Matrix:**
  | Principal | Resource | Operations |
  |---|---|---|
  | `User:producer` | Topic `clickstream-events` | `WRITE`, `DESCRIBE` |
  | `User:producer` | Cluster `kafka-cluster` | `IDEMPOTENT_WRITE` |
  | `User:spark` | Topic `clickstream-events` | `READ`, `DESCRIBE` |
  | `User:spark` | Topic `clickstream-events-dlq` | `WRITE`, `DESCRIBE` |
  | `User:spark` | Consumer Group `*` | `READ`, `DESCRIBE` |

#### 2.3 Dead-Letter Queue Envelope (`schemas/dlq_envelope.json`)
```json
{
  "original_payload": "string (raw unparsed text)",
  "failure_reason": "schema_validation_error | json_parse_error | system_error",
  "validation_errors": ["array of human-readable error messages"],
  "failed_at": "ISO-8601 UTC timestamp",
  "source_partition": "int (0-5)",
  "source_offset": "int >= 0"
}
```

#### 2.4 PostgreSQL Schema (`clickstream` DB)
```sql
CREATE TABLE IF NOT EXISTS windowed_user_metrics (
    window_start TIMESTAMP NOT NULL,
    window_end TIMESTAMP NOT NULL,
    page_url VARCHAR(512) NOT NULL,
    active_users INT DEFAULT 0,
    cart_additions INT DEFAULT 0,
    purchases INT DEFAULT 0,
    cart_abandonment_rate DOUBLE PRECISION DEFAULT 0.0,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (window_start, window_end, page_url)
);
CREATE INDEX IF NOT EXISTS idx_window_time ON windowed_user_metrics(window_start, window_end);
```

---

### 3. Reliability & State Management
- **Spark Checkpoint Store:** Mounted PVC (`spark-checkpoints-pvc`) mounted at `/opt/spark/checkpoints`. Checkpoint stores offset commits and stateful window aggregation metadata.
- **Watermarking:** 2-minute delay watermark (`withWatermark("event_time", "2 minutes")`) drops late data arriving beyond the boundary.
- **Idempotency:** Spark's `foreachBatch` writer issues atomic PostgreSQL `INSERT ... ON CONFLICT (window_start, window_end, page_url) DO UPDATE` to ensure exact-once processing semantics even across pod restarts or replayed microbatches.

---

### 4. Security & Compliance Requirements
- **Pod Security Standards:** Non-root execution (`runAsUser: 1000`, `runAsNonRoot: true`, `allowPrivilegeEscalation: false`).
- **Network Isolation:** `default-deny-all` NetworkPolicy on namespace. Explicit ingress/egress policies declared per service.
- **Credential Governance:** No plaintext secrets in Git. Terraform generates secrets using `random_password` and injects them into Kubernetes `Secret` resources.
