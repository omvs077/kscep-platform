# Technology Stack & Technical Rationale

## Project: K.S.C.E.P. Platform

---

### 1. Technology Selection Matrix

| Component | Technology | Version | Purpose / Role |
|---|---|---|---|
| **Container Platform** | Kubernetes (Minikube) | v1.38+ (K8s 1.28+) | Container orchestration, self-healing, networking |
| **Infrastructure as Code** | HashiCorp Terraform | $\ge 1.5.0$ | Declarative provisioning of K8s resources, Helm charts, secrets |
| **Message Broker** | Apache Kafka (KRaft mode) | 3.6.1 | High-throughput distributed event streaming without ZooKeeper |
| **Ingestion Service** | Python Flask + Gunicorn | 3.0+ / 21+ | Event ingestion gateway with JSON Schema validation & API authentication |
| **Stream Processing** | Apache Spark (Structured Streaming) | 3.5.1 | Low-latency stateful stream processing, sliding window aggregations |
| **Storage & Serving** | PostgreSQL | 16 (Alpine) | ACID relational store with time-partitioned metric tables |
| **Visualization** | Grafana OSS | 10.4+ | Interactive real-time metrics dashboards |
| **Autoscaling** | KEDA | 2.13+ | Kubernetes Event-driven Autoscaling driven by Kafka consumer group lag |
| **Observability** | Prometheus & Loki | Latest | Time-series metrics and log aggregation |
| **Schema Governance** | JSON Schema (Draft-07) | Draft-07 | Contract specification for producer, DLQ, and consumers |
| **Testing** | pytest & Locust | 8.0+ / 2.24+ | Unit, schema, integration, and load testing |

---

### 2. Deep Dive Rationales

#### 2.1 Apache Kafka with KRaft
- **Why KRaft over ZooKeeper?**
  - Reduces cluster footprint by eliminating the dedicated ZooKeeper quorum.
  - Decreases startup and recovery times from minutes to seconds.
  - Simplifies metadata management and lowers memory usage in resource-constrained environments (Minikube 3GB RAM).

#### 2.2 Apache Spark Structured Streaming
- **Why Spark over Flink or Kafka Streams?**
  - Built-in SQL catalyst optimizer allows intuitive DataFrame operations (`groupBy`, `window`, `watermark`).
  - Native micro-batch guarantees exact-once processing semantics through write-ahead logging (WAL) and checkpointing.
  - First-class Python ecosystem (`pyspark`) enables rapid testing, schema validation UDFs, and flexible sink integrations via `foreachBatch`.

#### 2.3 PostgreSQL 16
- **Why PostgreSQL over ClickHouse or Cassandra?**
  - Standardized SQL syntax with robust `ON CONFLICT DO UPDATE` support for idempotent upserts.
  - Native declarative table partitioning by range (`PARTITION BY RANGE (window_start)`).
  - Minimal memory footprint (~100-200MB) compared to ClickHouse (~1-2GB).
  - Role-based security (`spark_writer` vs `grafana_reader`) natively supported.

#### 2.4 KEDA (Kubernetes Event-driven Autoscaling)
- **Why KEDA over standard HPA?**
  - Standard Horizontal Pod Autoscaler (HPA) relies on CPU and Memory metrics, which are lagging indicators for message backpressure.
  - KEDA triggers scaling directly from Kafka topic lag (unprocessed message count), scaling consumers proactively before latency degradation occurs.
