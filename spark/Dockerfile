FROM python:3.11-slim-bookworm

# Install JRE and utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    default-jre-headless \
    curl \
    ca-certificates \
    procps \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/default-java
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# Create non-root user 'spark' (UID 1000)
RUN groupadd -g 1000 spark && \
    useradd -u 1000 -g spark -m -s /bin/bash spark

WORKDIR /app

# Install Python requirements
COPY spark/requirements.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Create jars directory and download connector jars
RUN mkdir -p /opt/spark/jars && \
    curl -fsSL -o /opt/spark/jars/spark-sql-kafka-0-10_2.12-3.5.1.jar \
    https://repo1.maven.org/maven2/org/apache/spark/spark-sql-kafka-0-10_2.12/3.5.1/spark-sql-kafka-0-10_2.12-3.5.1.jar && \
    curl -fsSL -o /opt/spark/jars/spark-token-provider-kafka-0-10_2.12-3.5.1.jar \
    https://repo1.maven.org/maven2/org/apache/spark/spark-token-provider-kafka-0-10_2.12/3.5.1/spark-token-provider-kafka-0-10_2.12-3.5.1.jar && \
    curl -fsSL -o /opt/spark/jars/kafka-clients-3.5.1.jar \
    https://repo1.maven.org/maven2/org/apache/kafka/kafka-clients/3.5.1/kafka-clients-3.5.1.jar && \
    curl -fsSL -o /opt/spark/jars/commons-pool2-2.11.1.jar \
    https://repo1.maven.org/maven2/org/apache/commons/commons-pool2/2.11.1/commons-pool2-2.11.1.jar && \
    curl -fsSL -o /opt/spark/jars/postgresql-42.7.3.jar \
    https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.3/postgresql-42.7.3.jar && \
    PYSPARK_JARS=$(python3 -c "import pyspark, os; print(os.path.join(pyspark.__path__[0], 'jars'))") && \
    cp /opt/spark/jars/*.jar "$PYSPARK_JARS/" && \
    chown -R spark:spark /opt/spark

# Copy application files and schema package
COPY schemas/ /app/schemas/
COPY spark/__init__.py /app/spark/__init__.py
COPY spark/streaming_job.py /app/spark/streaming_job.py

ENV PYTHONPATH="/app"

RUN chown -R spark:spark /app

USER 1000:1000

CMD ["python", "-u", "/app/spark/streaming_job.py"]
