# Production Runbook: PostgreSQL Disaster Recovery & Backup Restoration

**Target Database:** `clickstream`  
**Storage Path:** `/backups/` mounted from `postgres-backups-pvc`  
**Objective:** Restore database state to Recovery Point Objective (RPO < 1 hour) in the event of pod/data loss.

---

## 1. Automated Nightly Backups

The automated CronJob `postgres-backup` executes nightly at `01:30 UTC` via:
```bash
pg_dump -Fc -f /backups/clickstream-$(date +%F).dump
```
Retention: Dumps older than 7 days are automatically pruned.

---

## 2. Emergency Restoration Procedure

### Step 1: Identify the Latest Available Backup
Inspect the backup volume from within a maintenance container or running pod:
```bash
kubectl exec -n clickstream-pipeline postgres-0 -c postgres -- ls -lh /backups/
```
Expected output:
```text
clickstream-2026-10-02.dump
clickstream-2026-10-03.dump
```

### Step 2: Quiesce Upstream Writers
Temporarily scale down the Spark streaming consumer to prevent partial writes during restore:
```bash
kubectl scale deployment spark-streaming -n clickstream-pipeline --replicas=0
```

### Step 3: Execute pg_restore
Run `pg_restore` using clean-and-restore flags (`-c`, `--if-exists`, `-d clickstream`):
```bash
kubectl exec -n clickstream-pipeline postgres-0 -c postgres -- pg_restore \
  -U postgres \
  -d clickstream \
  --clean \
  --if-exists \
  /backups/clickstream-LATEST.dump
```

### Step 4: Verify Database Consistency & Row Counts
Check record counts on partitioned metrics tables:
```bash
kubectl exec -n clickstream-pipeline postgres-0 -c postgres -- psql -U postgres -d clickstream -c \
  "SELECT count(*) FROM windowed_user_metrics;"
```

### Step 5: Resume Ingestion & Processing
Scale the Spark streaming consumer back to target replica count:
```bash
kubectl scale deployment spark-streaming -n clickstream-pipeline --replicas=1
```
Spark will resume consuming from the last committed checkpoint on durable PVC `spark-checkpoints-pvc`.
