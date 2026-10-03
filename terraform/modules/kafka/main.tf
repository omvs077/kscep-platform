resource "helm_release" "kafka" {
  name      = "kafka"
  chart     = "${path.module}/../../charts/kafka"
  namespace = var.namespace

  # Resource allocations for low-resource environment (dev)
  values = [
    <<-EOT
    image:
      registry: docker.io
      repository: bitnamilegacy/kafka
      tag: 3.6.1-debian-11-r4
    replicaCount: ${var.replica_count}

    controller:
      replicaCount: ${var.replica_count}
    kraft:
      enabled: true
    sasl:
      enabledMechanisms: PLAIN,SCRAM-SHA-512
      client:
        users:
          - admin
          - producer
          - spark
          - keda
        passwords: "${var.kafka_admin_password},${var.kafka_producer_password},${var.kafka_spark_password},${var.kafka_keda_password}"
    extraConfig: |-
      authorizer.class.name=org.apache.kafka.metadata.authorizer.StandardAuthorizer
      super.users=User:admin;User:controller_user;User:inter_broker_user
      offsets.topic.replication.factor=1
      offsets.topic.num.partitions=1
      transaction.state.log.replication.factor=1
      transaction.state.log.min.isr=1
    listeners:
      client:
        protocol: SASL_PLAINTEXT
        port: 9092
    persistence:
      enabled: false  # Disable persistence in dev to save disk and memory
    provisioning:
      enabled: true
      topics:
        - name: clickstream-events
          partitions: 6
          replicationFactor: 1
        - name: clickstream-events-dlq
          partitions: 6
          replicationFactor: 1
    resources:
      limits:
        cpu: "1.0"
        memory: 1024Mi
      requests:
        cpu: "0.25"
        memory: 512Mi
    EOT
  ]
}

