# System Architecture & Data Flow

## Project: K.S.C.E.P. Platform

---

### 1. High-Level Architecture Diagram

```mermaid
flowchart TD
    subgraph Client ["Client / E-Commerce Frontend"]
        User["Browser / Mobile Client"]
    end

    subgraph K8s ["Kubernetes Cluster (clickstream-pipeline namespace)"]
        direction TB

        subgraph Ingestion ["Ingestion Layer"]
            Producer["Producer Pods (Flask / Gunicorn)\n- API Key Auth\n- Schema Validation (event_v1)\n- USER 1000"]
        end

        subgraph Messaging ["Message Broker (KRaft)"]
            KafkaBroker["Kafka Broker (3.6.1)\n- SASL_SCRAM Auth\n- ACLs: producer(W), spark(R/W)"]
            EventsTopic[("clickstream-events\n(6 partitions)")]
            DLQTopic[("clickstream-events-dlq\n(6 partitions)")]
            KafkaBroker --- EventsTopic
            KafkaBroker --- DLQTopic
        end

        subgraph Processing ["Stream Processing Engine"]
            SparkPod["Spark Streaming Job (PySpark 3.5.1)\n- Schema Validation UDF\n- 60s/10s Sliding Window\n- 2m Watermark\n- DLQ Envelope Routing"]
            CheckpointPVC[("spark-checkpoints-pvc\n(State Store)")]
            SparkPod --- CheckpointPVC
        end

        subgraph Storage ["Storage & Serving"]
            Postgres[("PostgreSQL 16\n- windowed_user_metrics\n- Daily Partitioning\n- Role Isolation")]
        end

        subgraph Scaling ["Autoscaling Engine"]
            KEDA["KEDA Operator\n- Kafka Lag Scaler\n- Min: 1, Max: 3"]
            KEDA -.-> SparkPod
        end
    end

    subgraph MonitoringNS ["monitoring namespace"]
        Grafana["Grafana Dashboards\n- Executive\n- Engineering\n- Infra/Ops"]
        Prometheus["Prometheus / Loki"]
    end

    %% Data Flows
    User -->|"POST /api/v1/events (X-API-Key)"| Producer
    Producer -->|"SASL SCRAM (Write-only)"| EventsTopic
    EventsTopic -->|"SASL SCRAM (Read-only)"| SparkPod
    SparkPod -->|"Malformed / Schema Failures"| DLQTopic
    SparkPod -->|"foreachBatch Idempotent Upsert"| Postgres
    Postgres -->|"grafana_reader (SELECT-only)"| Grafana
    Producer -.->|"Metrics (:5000/metrics)"| Prometheus
    SparkPod -.->|"Metrics"| Prometheus
```

---

### 2. End-to-End Data Pipeline Flow

#### Step 1: Event Generation & Boundary Ingestion
1. Client generates interaction events (`page_view`, `cart_add`, `purchase`, `page_exit`).
2. Event is transmitted via HTTP POST to the Flask Producer service with an `X-API-Key` header.
3. The Producer service validates the payload against `schemas/event_v1.json`:
   - If invalid: rejects immediately with HTTP 400 and validation error message.
   - If valid: serializes to JSON and produces message to Kafka topic `clickstream-events` with partition key `user_id`.

#### Step 2: Stream Consumption & Spark Validation
1. The Spark Streaming container boots as user `spark` (UID 1000) and reads from `clickstream-events` using `SASL_PLAINTEXT` and `SCRAM-SHA-512`.
2. A schema validation UDF verifies the raw Kafka value:
   - **Valid Events:** Passed down the analytics pipeline.
   - **Invalid / Poison Pills:** Wrapped into a standardized Dead-Letter Queue envelope (`dlq_envelope.json`) containing error details, original payload, source partition, and offset. Published immediately to `clickstream-events-dlq`.

#### Step 3: Stateful Sliding Window Aggregation
1. The valid stream assigns timestamps and applies a 2-minute event-time watermark:
   ```python
   df.withWatermark("event_time", "2 minutes")
   ```
2. Aggregations run over 60-second tumbling/sliding windows with 10-second hop:
   - Approximate active unique users (`approx_count_distinct(user_id)`)
   - Sum of cart additions
   - Sum of purchases
   - Computed cart abandonment rate:
     $$\text{Abandonment Rate} = \frac{\text{Cart Additions} - \text{Purchases}}{\text{Cart Additions}}$$

#### Step 4: Idempotent Materialization (Exactly-Once Sink)
1. For each microbatch, `foreachBatch` executes an atomic PostgreSQL upsert:
   ```sql
   INSERT INTO windowed_user_metrics (
       window_start, window_end, page_url, active_users,
       cart_additions, purchases, cart_abandonment_rate, updated_at
   ) VALUES (%s, %s, %s, %s, %s, %s, %s, NOW())
   ON CONFLICT (window_start, window_end, page_url)
   DO UPDATE SET
       active_users = EXCLUDED.active_users,
       cart_additions = EXCLUDED.cart_additions,
       purchases = EXCLUDED.purchases,
       cart_abandonment_rate = EXCLUDED.cart_abandonment_rate,
       updated_at = NOW();
   ```
2. Checkpoint state is persisted to `spark-checkpoints-pvc` ensuring fault-tolerant crash recovery.

---

### 3. Security Architecture & Zero-Trust
1. **Network Policies:**
   - Default deny on all ingress and egress traffic in `clickstream-pipeline`.
   - Producer only allows ingress on HTTP 5000 and egress to Kafka (port 9092) and DNS (port 53).
   - Spark only allows egress to Kafka (port 9092), Postgres (port 5432), and DNS (port 53).
   - Kafka only allows ingress from Producer and Spark pods.
2. **Identity & Access Management:**
   - Pods run under distinct Kubernetes Service Accounts (`producer-sa`, `spark-sa`).
   - Root privileges disabled across all containers (`runAsNonRoot: true`, `readOnlyRootFilesystem: false`).
   - Kafka ACLs enforce principle of least privilege (Producer cannot read; Spark cannot write to `clickstream-events`).
