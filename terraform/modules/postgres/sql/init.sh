#!/bin/sh
set -e
psql -v ON_ERROR_STOP=1 -U postgres -v w="$SPARK_WRITER_PASSWORD" -v r="$GRAFANA_READER_PASSWORD" <<'EOF'
CREATE DATABASE clickstream;
\c clickstream
ALTER DATABASE clickstream SET timezone = 'UTC';
CREATE ROLE spark_writer LOGIN PASSWORD :'w';
CREATE ROLE grafana_reader LOGIN PASSWORD :'r';
\i /sql/schema.sql
GRANT USAGE ON SCHEMA public TO spark_writer, grafana_reader;
GRANT SELECT, INSERT, UPDATE ON windowed_user_metrics TO spark_writer;
GRANT SELECT ON windowed_user_metrics TO grafana_reader;
SELECT ensure_partitions(3);
EOF