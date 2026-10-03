import os
import sys
import json
import logging
from datetime import datetime, timezone

from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col, from_json, to_json, struct, window, approx_count_distinct, sum as spark_sum,
    when, lit, udf, current_timestamp, coalesce
)
from pyspark.sql.types import (
    StructType, StructField, StringType, DoubleType, TimestampType, IntegerType, ArrayType
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("StreamingJob")

# Configuration
KAFKA_BOOTSTRAP_SERVERS = os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "kafka.clickstream-pipeline.svc.cluster.local:9092")
INPUT_TOPIC = os.environ.get("KAFKA_INPUT_TOPIC", "clickstream-events")
DLQ_TOPIC = os.environ.get("KAFKA_DLQ_TOPIC", "clickstream-events-dlq")
KAFKA_SECURITY_PROTOCOL = os.environ.get("KAFKA_SECURITY_PROTOCOL", "SASL_PLAINTEXT")
KAFKA_SASL_MECHANISM = os.environ.get("KAFKA_SASL_MECHANISM", "SCRAM-SHA-512")
KAFKA_USERNAME = os.environ.get("KAFKA_SASL_USERNAME", "spark")
KAFKA_PASSWORD = os.environ.get("KAFKA_SASL_PASSWORD", "")
CHECKPOINT_DIR = os.environ.get("CHECKPOINT_DIR", "/tmp/spark-checkpoints")

POSTGRES_HOST = os.environ.get("POSTGRES_HOST", "postgres.clickstream-pipeline.svc.cluster.local")
POSTGRES_PORT = os.environ.get("POSTGRES_PORT", "5432")
POSTGRES_DB = os.environ.get("POSTGRES_DB", "clickstream")
POSTGRES_USER = os.environ.get("POSTGRES_USER", "spark_writer")
POSTGRES_PASSWORD = os.environ.get("POSTGRES_PASSWORD", "")

JAAS_CONFIG = (
    f'org.apache.kafka.common.security.scram.ScramLoginModule required '
    f'username="{KAFKA_USERNAME}" password="{KAFKA_PASSWORD}";'
)

# Schema definitions
EVENT_SCHEMA = StructType([
    StructField("schema_version", StringType(), True),
    StructField("event_id", StringType(), True),
    StructField("user_id", StringType(), True),
    StructField("session_id", StringType(), True),
    StructField("event_type", StringType(), True),
    StructField("page_url", StringType(), True),
    StructField("product_id", StringType(), True),
    StructField("product_category", StringType(), True),
    StructField("price_inr", DoubleType(), True),
    StructField("timestamp", StringType(), True)
])

VALID_EVENT_TYPES = {"page_view", "cart_add", "purchase", "page_exit"}

def validate_payload(payload_str):
    """
    Validates event payload against schema rules.
    Returns (is_valid: bool, error_msg: str, event_time_iso: str)
    """
    if not payload_str:
        return False, "Empty payload", None
    try:
        data = json.loads(payload_str)
    except Exception as e:
        return False, f"JSON parse error: {str(e)}", None

    if not isinstance(data, dict):
        return False, "Payload is not a JSON object", None

    required_fields = ["schema_version", "event_id", "user_id", "session_id", "event_type", "timestamp"]
    missing = [f for f in required_fields if f not in data or data[f] is None]
    if missing:
        return False, f"Missing required fields: {', '.join(missing)}", None

    if data.get("schema_version") != "1.0":
        return False, f"Unsupported schema_version: {data.get('schema_version')}", None

    if data.get("event_type") not in VALID_EVENT_TYPES:
        return False, f"Invalid event_type: {data.get('event_type')}", None

    try:
        ts_str = data["timestamp"].replace("Z", "+00:00")
        datetime.fromisoformat(ts_str)
    except Exception:
        return False, f"Invalid ISO timestamp format: {data.get('timestamp')}", None

    return True, None, data.get("timestamp")

def build_dlq_envelope(raw_payload, failure_reason, error_message, partition=None, offset=None):
    return json.dumps({
        "original_payload": raw_payload or "",
        "failure_reason": failure_reason,
        "validation_errors": [error_message] if error_message else [],
        "failed_at": datetime.now(timezone.utc).isoformat(),
        "source_partition": partition,
        "source_offset": offset
    })

def upsert_to_postgres(batch_df, batch_id):
    """
    Idempotent upsert into PostgreSQL using ON CONFLICT.
    Falls back gracefully if Postgres is not yet deployed/reachable.
    """
    row_count = batch_df.count()
    if row_count == 0:
        return

    logger.info(f"Processing microbatch {batch_id} with {row_count} aggregated rows")
    records = batch_df.collect()

    try:
                import psycopg2
                conn = psycopg2.connect(
                    host=POSTGRES_HOST,
                    port=POSTGRES_PORT,
                    dbname=POSTGRES_DB,
                    user=POSTGRES_USER,
                    password=POSTGRES_PASSWORD,
                    connect_timeout=3
                )
                cur = conn.cursor()

                upsert_query = """
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
                """

                for r in records:
                    cur.execute(upsert_query, (
                        r["window"]["start"],
                        r["window"]["end"],
                        r["page_url"] or "/unknown",
                        int(r["active_users"]),
                        int(r["cart_additions"]),
                        int(r["purchases"]),
                        float(r["cart_abandonment_rate"])
                    ))

                conn.commit()
                cur.close()
                conn.close()
                logger.info(f"Successfully upserted {len(records)} records to Postgres in batch {batch_id}")
    except Exception as e:
                logger.error(f"Postgres upsert failed in batch {batch_id}: {e}")
                raise

def main():
    logger.info("Initializing Spark Streaming Job for K.S.C.E.P. Platform")

    spark = (
        SparkSession.builder
        .appName("KSCEP-Clickstream-Streaming")
        .config("spark.sql.streaming.checkpointLocation", CHECKPOINT_DIR)
        .config("spark.sql.shuffle.partitions", "2")
        .getOrCreate()
    )
    spark.sparkContext.setLogLevel("WARN")

    # Read from Kafka
    kafka_options = {
        "kafka.bootstrap.servers": KAFKA_BOOTSTRAP_SERVERS,
        "subscribe": INPUT_TOPIC,
        "startingOffsets": "latest",
        "failOnDataLoss": "false"
    }

    if "SASL" in KAFKA_SECURITY_PROTOCOL:
        kafka_options.update({
            "kafka.security.protocol": KAFKA_SECURITY_PROTOCOL,
            "kafka.sasl.mechanism": KAFKA_SASL_MECHANISM,
            "kafka.sasl.jaas.config": JAAS_CONFIG
        })

    logger.info(f"Connecting to Kafka at {KAFKA_BOOTSTRAP_SERVERS}, topic: {INPUT_TOPIC}")
    df_raw = spark.readStream.format("kafka").options(**kafka_options).load()

    # Cast key and value to string
    df_parsed = df_raw.select(
        col("key").cast("string").alias("msg_key"),
        col("value").cast("string").alias("raw_value"),
        col("partition"),
        col("offset")
    )

    # Validation UDFs
    @udf(returnType=StringType())
    def get_validation_error(payload):
        is_valid, err, _ = validate_payload(payload)
        return err if not is_valid else None

    df_validated = df_parsed.withColumn("validation_error", get_validation_error(col("raw_value")))

    # Split into Valid and Invalid DataFrames
    df_invalid = df_validated.filter(col("validation_error").isNotNull())
    df_valid = df_validated.filter(col("validation_error").isNull())

    # Format DLQ envelope for invalid records
    @udf(returnType=StringType())
    def make_dlq_json(raw_val, err, part, off):
        return build_dlq_envelope(raw_val, "schema_validation_error", err, part, off)

    df_dlq = df_invalid.select(
        coalesce(col("msg_key"), lit("dlq_key")).alias("key"),
        make_dlq_json(col("raw_value"), col("validation_error"), col("partition"), col("offset")).alias("value")
    )

    # Write DLQ to Kafka
    dlq_kafka_options = {
        "kafka.bootstrap.servers": KAFKA_BOOTSTRAP_SERVERS,
        "topic": DLQ_TOPIC,
        "checkpointLocation": f"{CHECKPOINT_DIR}/dlq"
    }
    if "SASL" in KAFKA_SECURITY_PROTOCOL:
        dlq_kafka_options.update({
            "kafka.security.protocol": KAFKA_SECURITY_PROTOCOL,
            "kafka.sasl.mechanism": KAFKA_SASL_MECHANISM,
            "kafka.sasl.jaas.config": JAAS_CONFIG
        })

    dlq_query = (
        df_dlq.writeStream
        .format("kafka")
        .options(**dlq_kafka_options)
        .outputMode("append")
        .start()
    )

    # Parse valid events schema
    df_events = (
        df_valid
        .withColumn("data", from_json(col("raw_value"), EVENT_SCHEMA))
        .select("data.*")
        .withColumn("event_time", col("timestamp").cast(TimestampType()))
    )

    # Sliding window aggregations (60s window, 10s slide, 2-minute watermark)
    windowed_agg = (
        df_events
        .withWatermark("event_time", "2 minutes")
        .groupBy(
            window(col("event_time"), "60 seconds", "10 seconds"),
            coalesce(col("page_url"), lit("/unknown")).alias("page_url")
        )
        .agg(
            approx_count_distinct("user_id").alias("active_users"),
            spark_sum(when(col("event_type") == "cart_add", 1).otherwise(0)).alias("cart_additions"),
            spark_sum(when(col("event_type") == "purchase", 1).otherwise(0)).alias("purchases")
        )
        .withColumn(
            "cart_abandonment_rate",
            when(col("cart_additions") > 0,
                 (col("cart_additions") - col("purchases")) / col("cart_additions"))
            .otherwise(0.0)
        )
    )

    # Output to Postgres via foreachBatch
    agg_query = (
        windowed_agg.writeStream
        .foreachBatch(upsert_to_postgres)
        .outputMode("update")
        .option("checkpointLocation", f"{CHECKPOINT_DIR}/metrics")
        .start()
    )

    logger.info("Spark streaming queries started. Awaiting termination...")
    spark.streams.awaitAnyTermination()

if __name__ == "__main__":
    main()
