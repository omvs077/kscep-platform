# Product Requirements Document (PRD)

## Project Name: K.S.C.E.P.
**Real-Time E-Commerce Clickstream & User Behavior Analytics Platform**

---

### 1. Executive Summary & Vision
K.S.C.E.P. is a resilient, Kubernetes-native, real-time event ingestion and stream processing platform designed for modern e-commerce storefronts. It ingests high-volume clickstream events (`page_view`, `cart_add`, `purchase`, `page_exit`), validates them against schema governance contracts, routes anomalies to a Dead-Letter Queue (DLQ), performs low-latency sliding-window aggregations using Apache Spark Structured Streaming, and materializes analytics into an indexed, partitioned PostgreSQL datastore visualized by Grafana dashboards.

The platform provides end-to-end observability, fine-grained zero-trust network policies, role-based access control, elastic autoscaling via KEDA, and robust Disaster Recovery / GitOps automation.

---

### 2. Target Personas
1. **Product & Growth Managers:** Track real-time funnel conversion, cart abandonment spikes, page popularity, and campaign performance with under 10-second end-to-end latency.
2. **Data Engineers:** Maintain rigid schema contracts (`event_v1.json`), monitor stream lag, debug schema failures in the Dead Letter Queue (`clickstream-events-dlq`), and manage streaming jobs.
3. **Platform & Site Reliability Engineers (SREs):** Monitor cluster health, node utilization, autoscaling behavior via KEDA, zero-downtime database maintenance, and network security compliance.

---

### 3. Core Functional Requirements (FRs)

#### FR-1: High-Throughput Event Ingestion
- Ingest clickstream payloads via a lightweight, secure REST API / control panel.
- Authenticate producer requests using secure API keys.
- Rate-limit and throttle abusive clients to protect downstream brokers.
- Concurrently publish validated events to Apache Kafka KRaft cluster.

#### FR-2: Schema Governance & Dead-Letter Queue (DLQ)
- Enforce JSON schema validation at the ingestion boundary and stream processor.
- Valid events contain: `schema_version`, `event_id` (UUID), `user_id`, `session_id`, `event_type`, `page_url`, `timestamp` (ISO-8601 UTC). Optional: `product_id`, `product_category`, `price_inr`.
- Unparseable or schema-violating events must NOT crash the stream; they must be enriched with failure metadata (timestamp, error reason, source partition/offset) and routed to a dedicated DLQ Kafka topic (`clickstream-events-dlq`).

#### FR-3: Stream Analytics & Metric Aggregation
- Consume raw events from Kafka with read-only credentials.
- Compute rolling 60-second window aggregations sliding every 10 seconds.
- Handle out-of-order events using a 2-minute event-time watermark.
- Compute key metrics:
  - Active unique users per page (`approx_count_distinct`)
  - Cart addition counts
  - Purchase counts
  - Cart abandonment rate (`(cart_additions - purchases) / cart_additions`)

#### FR-4: Storage & Materialized Serving
- Persist aggregated window metrics into PostgreSQL 16 using idempotent upsert operations (`ON CONFLICT (window_start, window_end, page_url) DO UPDATE`).
- Enforce daily table partitioning to support historical retention without degradation.
- Separate database roles: `spark_writer` (INSERT/UPDATE on metrics) and `grafana_reader` (SELECT-only).

#### FR-5: Visualization & Dashboards
- Multi-tier Grafana dashboards provisioned as code:
  - **Executive Dashboard:** High-level conversion funnel, real-time GMV, cart abandonment trends.
  - **Engineering Dashboard:** Processing latency (p50, p95, p99), Kafka consumer lag, DLQ error breakdown.
  - **Infra/Ops Dashboard:** Kubernetes resource utilization, pod memory/CPU, KEDA scaling triggers.

#### FR-6: Elastic Autoscaling
- Scale Spark streaming consumers and producer pods dynamically based on Kafka consumer group lag using KEDA (Kubernetes Event-driven Autoscaling).

---

### 4. Non-Functional Requirements (NFRs)

| Metric | Target | Rationale |
|---|---|---|
| **End-to-End Latency** | $\le 10$ seconds | Fresh insights for dynamic frontends and operational alerts |
| **Ingestion Availability** | 99.9% uptime | Prevent loss of customer interactions during sales spikes |
| **Data Integrity** | Zero data loss | Checkpointed streaming state and durable Kafka storage |
| **Security Isolation** | Zero-Trust (Default Deny) | Least-privilege RBAC, SASL SCRAM-SHA-512 authentication, non-root containers |
| **Recovery Time Objective (RTO)** | $< 5$ minutes | Automated Helm / Terraform bootstrap and automated checkpoints |
| **Recovery Point Objective (RPO)** | $< 1$ minute | Continuous Spark checkpointing to durable PVC |

---

### 5. Release Roadmap (Sprint Plan)
- **Sprint 1 (Done):** Secure Foundation - IaC, Minikube, Namespaces, Default-Deny NetPols, Secrets, RBAC.
- **Sprint 2 (Done):** Ingestion Layer - Schema Governance, Flask Producer Control Panel, Kafka KRaft, Producer ACLs.
- **Sprint 3 (In Progress):** Stream Processing - Spark Structured Streaming, DLQ Routing, Windowing, Exactly-Once Sink.
- **Sprint 4 (Planned):** Storage & Visualization - PostgreSQL 16, Partitioning, DB Roles, Grafana Dashboards as Code.
- **Sprint 5 (Planned):** Elastic Autoscaling - KEDA Operator, ScaledObjects, Locust Load Testing.
- **Sprint 6 (Planned):** Security Hardening & Compliance - Fine-grained NetPols, Trivy scan, kube-bench, Gitleaks.
- **Sprint 7 (Planned):** Observability Stack - Prometheus, Alertmanager rules, Loki log aggregation.
- **Sprint 8 (Planned):** CI/CD & Production Readiness - GitHub Actions workflows, end-to-end integration tests.
