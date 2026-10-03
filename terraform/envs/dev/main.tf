terraform {
  required_version = ">= 1.5.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.26.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "minikube"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "minikube"
  }
}

module "namespace" {
  source = "../../modules/namespace"

  pipeline_namespace   = "clickstream-pipeline"
  monitoring_namespace = "monitoring"
}

module "secrets" {
  source    = "../../modules/secrets"
  namespace = module.namespace.pipeline_namespace_name
}

module "kafka" {
  source = "../../modules/kafka"

  namespace               = module.namespace.pipeline_namespace_name
  kafka_admin_password    = module.secrets.kafka_admin_password
  kafka_producer_password = module.secrets.kafka_producer_password
  kafka_spark_password    = module.secrets.kafka_spark_password
  kafka_keda_password     = module.secrets.kafka_keda_password
  replica_count           = 1
}

module "producer" {
  source = "../../modules/producer"

  namespace            = module.namespace.pipeline_namespace_name
  bootstrap_servers    = module.kafka.bootstrap_servers
  kafka_secret_name    = module.secrets.kafka_secret_name
  producer_secret_name = module.secrets.producer_secret_name
  image                = "producer:latest"
  replicas             = 2
}

module "spark" {
  source = "../../modules/spark"

  namespace               = module.namespace.pipeline_namespace_name
  kafka_bootstrap_servers = module.kafka.bootstrap_servers
  kafka_secret_name       = module.secrets.kafka_secret_name
  image                   = "spark:s4-1"
  replicas                = 1
}

module "postgres" {
  source      = "../../modules/postgres"
  namespace   = module.namespace.pipeline_namespace_name
  secret_name = module.secrets.postgres_secret_name
}

module "grafana" {
  source                  = "../../modules/grafana"
  namespace               = module.namespace.monitoring_namespace_name
  grafana_reader_password = module.secrets.grafana_reader_password
}