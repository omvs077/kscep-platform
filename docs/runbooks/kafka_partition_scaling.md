# Production Runbook: Kafka Topic Partition Scaling & Rebalancing

**Target Topics:** `clickstream-events`, `clickstream-events-dlq`  
**Current Partitions:** 6  
**Objective:** Scale partition count to accommodate higher peak throughput without pipeline downtime.

---

## 1. Pre-Scaling Assessment

Verify current consumer group lag and broker resource headroom before altering partitions:
```bash
# Check consumer lag
kubectl exec -n clickstream-pipeline kafka-controller-0 -- kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe \
  --group kscep-spark-consumer \
  --command-config /tmp/client.properties
```

---

## 2. Partition Expansion Procedure

Kafka permits increasing partitions on active topics dynamically. *Note: Kafka does not allow decreasing partitions.*

### Step 1: Scale Topic Partitions
Increase `clickstream-events` from 6 to 12 partitions:
```bash
kubectl exec -n clickstream-pipeline kafka-controller-0 -- kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --topic clickstream-events \
  --alter \
  --partitions 12 \
  --command-config /tmp/client.properties
```

### Step 2: Scale DLQ Partitions Matching Ingestion
```bash
kubectl exec -n clickstream-pipeline kafka-controller-0 -- kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --topic clickstream-events-dlq \
  --alter \
  --partitions 12 \
  --command-config /tmp/client.properties
```

### Step 3: Verify Partition Count
```bash
kubectl exec -n clickstream-pipeline kafka-controller-0 -- kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --describe \
  --topic clickstream-events \
  --command-config /tmp/client.properties
```

---

## 3. Spark Consumer Rebalancing

PySpark Structured Streaming automatically detects new partitions during microbatch trigger execution (`startingOffsets: latest` or checkpoint offset range update).
Verify consumer partition pickup in Spark logs:
```bash
kubectl logs -n clickstream-pipeline -l app=spark -f --tail=100
```
