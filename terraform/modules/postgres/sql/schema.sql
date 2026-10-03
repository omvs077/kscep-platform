CREATE TABLE windowed_user_metrics (
    window_start TIMESTAMP NOT NULL,
    window_end TIMESTAMP NOT NULL,
    page_url VARCHAR(512) NOT NULL,
    active_users INT DEFAULT 0,
    cart_additions INT DEFAULT 0,
    purchases INT DEFAULT 0,
    cart_abandonment_rate DOUBLE PRECISION DEFAULT 0.0,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (window_start, window_end, page_url)
) PARTITION BY RANGE (window_start);
CREATE INDEX idx_window_time ON windowed_user_metrics (window_start, window_end);

CREATE OR REPLACE FUNCTION ensure_partitions(days_ahead int DEFAULT 3) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE d date;
BEGIN
  FOR d IN SELECT g::date FROM generate_series(
      (now() AT TIME ZONE 'utc')::date - 1,
      (now() AT TIME ZONE 'utc')::date + days_ahead, '1 day') g
  LOOP
    EXECUTE format('CREATE TABLE IF NOT EXISTS windowed_user_metrics_%s PARTITION OF windowed_user_metrics FOR VALUES FROM (%L) TO (%L)',
      to_char(d, 'YYYYMMDD'), d, d + 1);
  END LOOP;
END $$;