terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

# ==================
# Network
# ==================
resource "docker_network" "otel_network" {
  name = "opentelemetry-demo-v2"
  driver = "bridge"
}

# ==================
# Volumes (para flagd y postgresql)
# ==================
# Nota: los volúmenes de config (otelcol, grafana, jaeger, prometheus) 
# requieren que los archivos existan en tu máquina local en las rutas indicadas.

# ==================
# Variables locales con todos los valores del .env
# ==================
locals {
  image_version      = "2.2.0"
  image_name         = "ghcr.io/kevinaguirreg/devops-project"
  demo_version       = "latest"

  otel_collector_host      = "otel-collector"
  otel_collector_port_grpc = "4317"
  otel_collector_port_http = "4318"
  otel_exporter_endpoint   = "http://otel-collector:4317"
  otel_resource_attrs      = "service.namespace=opentelemetry-demo,service.version=2.2.0"
  otel_metrics_temporality = "cumulative"

  kafka_host = "kafka"
  kafka_addr = "kafka:9092"

  flagd_host       = "flagd"
  flagd_port       = "8013"
  flagd_ofrep_port = "8016"

  postgres_host     = "postgresql"
  postgres_port     = "5432"
  postgres_db       = "otel"
  postgres_password = "otel"

  valkey_addr = "valkey-cart:6379"

  llm_host      = "llm"
  llm_port      = "8000"
  llm_base_url  = "http://llm:8000/v1"
  llm_model     = "astronomy-llm"
  openai_api_key = "dummy"

  product_catalog_addr  = "product-catalog:3550"
  product_reviews_addr  = "product-reviews:3551"
  recommendation_addr   = "recommendation:9001"
  cart_addr             = "cart:7070"
  currency_addr         = "currency:7001"
  email_addr            = "http://email:6060"
  payment_addr          = "payment:50051"
  shipping_addr         = "http://shipping:50050"
  checkout_addr         = "checkout:5050"
  quote_addr            = "http://quote:8090"
  ad_addr               = "ad:9555"
  frontend_addr         = "frontend:8080"
  frontend_proxy_addr   = "frontend-proxy:8080"
  image_provider_host   = "image-provider"
  image_provider_port   = "8081"

  grafana_host     = "grafana"
  grafana_port     = "3000"
  jaeger_host      = "jaeger"
  jaeger_ui_port   = "16686"
  jaeger_grpc_port = "4317"
  prometheus_addr  = "prometheus:9090"
}

# ==================
# OpenSearch
# ==================
resource "docker_container" "opensearch" {
  name  = "otel-demo-v2-opensearch"
  image = "opensearchproject/opensearch:3.4.0"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["opensearch"]
  }

  ports {
    internal = 9200
    external = 9200
  }

  env = [
    "cluster.name=demo-cluster",
    "node.name=demo-node",
    "bootstrap.memory_lock=true",
    "discovery.type=single-node",
    "OPENSEARCH_JAVA_OPTS=-Xms400m -Xmx400m",
    "DISABLE_INSTALL_DEMO_CONFIG=true",
    "DISABLE_SECURITY_PLUGIN=true",
  ]

  ulimit {
    name = "memlock"
    soft = -1
    hard = -1
  }
  ulimit {
    name = "nofile"
    soft = 65536
    hard = 65536
  }

  healthcheck {
    test         = ["CMD-SHELL", "curl -s http://localhost:9200/_cluster/health | grep -E '\"status\":\"(green|yellow)\"'"]
    start_period = "10s"
    interval     = "5s"
    timeout      = "10s"
    retries      = 10
  }

  memory = 1024
}

# ==================
# Jaeger
# ==================
resource "docker_container" "jaeger" {
  name  = "otel-demo-v2-jaeger"
  image = "jaegertracing/jaeger:2.12.0"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["jaeger"]
  }

  ports {
    internal = 16686
    external = 16686
  }
  ports {
    internal = 4317
    external = 54688
  }

  env = [
    "JAEGER_HOST=${local.jaeger_host}",
    "JAEGER_GRPC_PORT=${local.jaeger_grpc_port}",
    "PROMETHEUS_ADDR=${local.prometheus_addr}",
    "OTEL_COLLECTOR_HOST=${local.otel_collector_host}",
    "OTEL_COLLECTOR_PORT_HTTP=${local.otel_collector_port_http}",
    "MEMORY_MAX_TRACES=25000",
  ]

  command = ["--config=file:/etc/jaeger/config.yml"]

  volumes {
    host_path      = "${path.cwd}/../src/jaeger/config.yml"
    container_path = "/etc/jaeger/config.yml"
    read_only      = true
  }

  memory = 1228
}

# ==================
# Grafana
# ==================
resource "docker_container" "grafana" {
  name  = "otel-demo-v2-grafana"
  image = "grafana/grafana:12.3.1"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["grafana"]
  }

  ports {
    internal = 3000
    external = 3000
  }

  env = [
    "GF_INSTALL_PLUGINS=grafana-opensearch-datasource",
  ]

  volumes {
    host_path      = "${path.cwd}/../src/grafana/grafana.ini"
    container_path = "/etc/grafana/grafana.ini"
    read_only      = true
  }
  volumes {
    host_path      = "${path.cwd}/../src/grafana/provisioning"
    container_path = "/etc/grafana/provisioning"
    read_only      = true
  }

  memory = 179
}

# ==================
# Prometheus
# ==================
resource "docker_container" "prometheus" {
  name  = "otel-demo-v2-prometheus"
  image = "quay.io/prometheus/prometheus:v3.8.1"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["prometheus"]
  }

  ports {
    internal = 9090
    external = 9090
  }

  command = [
    "--web.console.templates=/etc/prometheus/consoles",
    "--web.console.libraries=/etc/prometheus/console_libraries",
    "--storage.tsdb.retention.time=7d",
    "--config.file=/etc/prometheus/prometheus-config.yaml",
    "--storage.tsdb.path=/prometheus",
    "--web.enable-lifecycle",
    "--web.route-prefix=/",
    "--web.enable-otlp-receiver",
    "--enable-feature=exemplar-storage",
  ]

  volumes {
    host_path      = "${path.cwd}/../src/prometheus/prometheus-config.yaml"
    container_path = "/etc/prometheus/prometheus-config.yaml"
    read_only      = true
  }

  memory = 204
}

# ==================
# Valkey (Cache para Cart)
# ==================
resource "docker_container" "valkey_cart" {
  name  = "otel-demo-v2-valkey-cart"
  image = "valkey/valkey:9.0.1-alpine3.23"
  user  = "valkey"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["valkey-cart"]
  }

  ports {
    internal = 6379
    external = 6379
  }

  memory = 20
}

# ==================
# PostgreSQL
# ==================
resource "docker_container" "postgresql" {
  name  = "otel-demo-v2-postgresql"
  image = "postgres:17.6"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["postgresql"]
  }

  ports {
    internal = 5432
    external = 5432
  }

  env = [
    "POSTGRES_USER=root",
    "POSTGRES_PASSWORD=${local.postgres_password}",
    "POSTGRES_DB=${local.postgres_db}",
  ]

  volumes {
    host_path      = "${path.cwd}/../src/postgresql/init.sql"
    container_path = "/docker-entrypoint-initdb.d/init.sql"
    read_only      = true
  }

  memory = 80
}

# ==================
# Flagd
# ==================
resource "docker_container" "flagd" {
  name  = "otel-demo-v2-flagd"
  image = "ghcr.io/open-feature/flagd:v0.12.9"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["flagd"]
  }

  ports {
    internal = 8013
    external = 8013
  }
  ports {
    internal = 8016
    external = 8016
  }

  env = [
    "FLAGD_OTEL_COLLECTOR_URI=${local.otel_collector_host}:${local.otel_collector_port_grpc}",
    "FLAGD_METRICS_EXPORTER=otel",
    "GOMEMLIMIT=60MiB",
    "OTEL_RESOURCE_ATTRIBUTES=${local.otel_resource_attrs}",
    "OTEL_SERVICE_NAME=flagd",
  ]

  command = ["start", "--uri", "file:./etc/flagd/demo.flagd.json"]

  volumes {
    host_path      = "${path.cwd}/../src/flagd"
    container_path = "/etc/flagd"
    read_only      = true
  }

  memory = 75
}

# ==================
# Kafka
# ==================
resource "docker_container" "kafka" {
  name  = "otel-demo-v2-kafka"
  image = "ghcr.io/open-telemetry/demo:latest-kafka"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["kafka"]
  }

  env = [
    "KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://${local.kafka_host}:9092",
    "KAFKA_LISTENERS=PLAINTEXT://${local.kafka_host}:9092,CONTROLLER://${local.kafka_host}:9093",
    "KAFKA_CONTROLLER_QUORUM_VOTERS=1@${local.kafka_host}:9093",
    "OTEL_EXPORTER_OTLP_ENDPOINT=http://${local.otel_collector_host}:${local.otel_collector_port_http}",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=${local.otel_metrics_temporality}",
    "OTEL_RESOURCE_ATTRIBUTES=${local.otel_resource_attrs}",
    "OTEL_SERVICE_NAME=kafka",
    "KAFKA_HEAP_OPTS=-Xmx400m -Xms400m",
  ]

  healthcheck {
    test     = ["CMD-SHELL", "nc -z kafka 9092"]
    start_period = "10s"
    interval = "5s"
    timeout  = "10s"
    retries  = 10
  }

  memory = 634
}

# ==================
# OTel Collector
# ==================
resource "docker_container" "otel_collector" {
  name  = "otel-demo-v2-otel-collector"
  image = "ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.145.0"
  user  = "0:0"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["otel-collector"]
  }

  ports {
    internal = 4317
    external = 4317
  }
  ports {
    internal = 4318
    external = 4318
  }

  command = ["--config=/etc/otelcol-config.yml", "--config=/etc/otelcol-config-extras.yml"]

  env = [
    "FRONTEND_PROXY_ADDR=${local.frontend_proxy_addr}",
    "IMAGE_PROVIDER_HOST=${local.image_provider_host}",
    "IMAGE_PROVIDER_PORT=${local.image_provider_port}",
    "HOST_FILESYSTEM=/",
    "OTEL_COLLECTOR_HOST=${local.otel_collector_host}",
    "OTEL_COLLECTOR_PORT_GRPC=${local.otel_collector_port_grpc}",
    "OTEL_COLLECTOR_PORT_HTTP=${local.otel_collector_port_http}",
    "POSTGRES_HOST=${local.postgres_host}",
    "POSTGRES_PORT=${local.postgres_port}",
    "POSTGRES_PASSWORD=${local.postgres_password}",
    "GOMEMLIMIT=160MiB",
  ]

  volumes {
    host_path      = "/"
    container_path = "/hostfs"
    read_only      = true
  }
  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
    read_only      = false
  }
  volumes {
    host_path      = "${path.cwd}/../src/otel-collector/otelcol-config.yml"
    container_path = "/etc/otelcol-config.yml"
    read_only      = true
  }
  volumes {
    host_path      = "${path.cwd}/../src/otel-collector/otelcol-config-extras.yml"
    container_path = "/etc/otelcol-config-extras.yml"
    read_only      = true
  }

  depends_on = [
    docker_container.jaeger,
    docker_container.opensearch,
  ]

  memory = 204
}

# ==================
# LLM
# ==================
resource "docker_container" "llm" {
  name  = "otel-demo-v2-llm"
  image = "${local.image_name}-llm:${local.demo_version}"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["llm"]
  }

  ports {
    internal = 8000
    external = 8000
  }

  env = [
    "FLAGD_HOST=${local.flagd_host}",
    "FLAGD_PORT=${local.flagd_port}",
  ]

  depends_on = [docker_container.flagd]

  memory = 50
}

# ==================
# Accounting
# ==================
resource "docker_container" "accounting" {
  name  = "otel-demo-v2-accounting"
  image = "${local.image_name}-accounting:${local.demo_version}"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["accounting"]
  }

  env = [
    "KAFKA_ADDR=${local.kafka_addr}",
    "OTEL_EXPORTER_OTLP_ENDPOINT=http://${local.otel_collector_host}:${local.otel_collector_port_http}",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=${local.otel_metrics_temporality}",
    "OTEL_RESOURCE_ATTRIBUTES=${local.otel_resource_attrs}",
    "OTEL_SERVICE_NAME=accounting",
    "DB_CONNECTION_STRING=Host=${local.postgres_host};Username=otelu;Password=otelp;Database=${local.postgres_db}",
    "OTEL_DOTNET_AUTO_TRACES_ENTITYFRAMEWORKCORE_INSTRUMENTATION_ENABLED=false",
  ]

  depends_on = [
    docker_container.otel_collector,
    docker_container.kafka,
  ]

  memory = 160
}

# ==================
# Ad
# ==================
resource "docker_container" "ad" {
  name  = "otel-demo-v2-ad"
  image = "ghcr.io/open-telemetry/demo:latest-ad"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["ad"]
  }

  ports {
    internal = 9555
    external = 9555
  }

  env = [
    "AD_PORT=9555",
    "FLAGD_HOST=${local.flagd_host}",
    "FLAGD_PORT=${local.flagd_port}",
    "OTEL_EXPORTER_OTLP_ENDPOINT=http://${local.otel_collector_host}:${local.otel_collector_port_http}",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=${local.otel_metrics_temporality}",
    "OTEL_RESOURCE_ATTRIBUTES=${local.otel_resource_attrs}",
    "OTEL_LOGS_EXPORTER=otlp",
    "OTEL_SERVICE_NAME=ad",
  ]

  depends_on = [
    docker_container.otel_collector,
    docker_container.flagd,
  ]

  memory = 300
}

# ==================
# Cart
# ==================
resource "docker_container" "cart" {
  name  = "otel-demo-v2-cart"
  image = "${local.image_name}-cart:${local.demo_version}"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["cart"]
  }

  ports {
    internal = 7070
    external = 7070
  }

  env = [
    "CART_PORT=7070",
    "FLAGD_HOST=${local.flagd_host}",
    "FLAGD_PORT=${local.flagd_port}",
    "VALKEY_ADDR=${local.valkey_addr}",
    "OTEL_EXPORTER_OTLP_ENDPOINT=${local.otel_exporter_endpoint}",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=${local.otel_metrics_temporality}",
    "OTEL_RESOURCE_ATTRIBUTES=${local.otel_resource_attrs}",
    "OTEL_SERVICE_NAME=cart",
    "ASPNETCORE_URLS=http://*:7070",
  ]

  depends_on = [
    docker_container.valkey_cart,
    docker_container.otel_collector,
    docker_container.flagd,
  ]

  memory = 160
}

# ==================
# Currency
# ==================
resource "docker_container" "currency" {
  name  = "otel-demo-v2-currency"
  image = "ghcr.io/open-telemetry/demo:latest-currency"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["currency"]
  }

  ports {
    internal = 7001
    external = 7001
  }

  env = [
    "CURRENCY_PORT=7001",
    "IPV6_ENABLED=false",
    "VERSION=${local.image_version}",
    "OTEL_EXPORTER_OTLP_ENDPOINT=${local.otel_exporter_endpoint}",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=${local.otel_metrics_temporality}",
    "OTEL_RESOURCE_ATTRIBUTES=${local.otel_resource_attrs}",
    "OTEL_SERVICE_NAME=currency",
  ]

  depends_on = [docker_container.otel_collector]

  memory = 20
}

# ==================
# Email
# ==================
resource "docker_container" "email" {
  name  = "otel-demo-v2-email"
  image = "${local.image_name}-email:${local.demo_version}"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["email"]
  }

  ports {
    internal = 6060
    external = 6060
  }

  env = [
    "APP_ENV=production",
    "EMAIL_PORT=6060",
    "FLAGD_HOST=${local.flagd_host}",
    "FLAGD_PORT=${local.flagd_port}",
    "OTEL_EXPORTER_OTLP_ENDPOINT=http://${local.otel_collector_host}:${local.otel_collector_port_http}",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=${local.otel_metrics_temporality}",
    "OTEL_RESOURCE_ATTRIBUTES=${local.otel_resource_attrs}",
    "OTEL_SERVICE_NAME=email",
  ]

  depends_on = [docker_container.otel_collector]

  memory = 100
}

# ==================
# Fraud Detection
# ==================
resource "docker_container" "fraud_detection" {
  name  = "otel-demo-v2-fraud-detection"
  image = "ghcr.io/open-telemetry/demo:latest-fraud-detection"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["fraud-detection"]
  }

  env = [
    "FLAGD_HOST=${local.flagd_host}",
    "FLAGD_PORT=${local.flagd_port}",
    "KAFKA_ADDR=${local.kafka_addr}",
    "OTEL_EXPORTER_OTLP_ENDPOINT=http://${local.otel_collector_host}:${local.otel_collector_port_http}",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=${local.otel_metrics_temporality}",
    "OTEL_INSTRUMENTATION_KAFKA_EXPERIMENTAL_SPAN_ATTRIBUTES=true",
    "OTEL_INSTRUMENTATION_MESSAGING_EXPERIMENTAL_RECEIVE_TELEMETRY_ENABLED=true",
    "OTEL_RESOURCE_ATTRIBUTES=${local.otel_resource_attrs}",
    "OTEL_SERVICE_NAME=fraud-detection",
  ]

  depends_on = [
    docker_container.otel_collector,
    docker_container.kafka,
  ]

  memory = 300
}

# ==================
# Payment
# ==================
resource "docker_container" "payment" {
  name  = "otel-demo-v2-payment"
  image = "${local.image_name}-payment:${local.demo_version}"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["payment"]
  }

  ports {
    internal = 50051
    external = 50051
  }

  env = [
    "IPV6_ENABLED=false",
    "PAYMENT_PORT=50051",
    "FLAGD_HOST=${local.flagd_host}",
    "FLAGD_PORT=${local.flagd_port}",
    "OTEL_EXPORTER_OTLP_ENDPOINT=${local.otel_exporter_endpoint}",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=${local.otel_metrics_temporality}",
    "OTEL_RESOURCE_ATTRIBUTES=${local.otel_resource_attrs}",
    "OTEL_SERVICE_NAME=payment",
  ]

  depends_on = [
    docker_container.otel_collector,
    docker_container.flagd,
  ]

  memory = 140
}

# ==================
# Product Catalog
# ==================
resource "docker_container" "product_catalog" {
  name  = "otel-demo-v2-product-catalog"
  image = "${local.image_name}-product-catalog:${local.demo_version}"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["product-catalog"]
  }

  ports {
    internal = 3550
    external = 3550
  }

  env = [
    "PRODUCT_CATALOG_PORT=3550",
    "FLAGD_HOST=${local.flagd_host}",
    "FLAGD_PORT=${local.flagd_port}",
    "GOMEMLIMIT=16MiB",
    "OTEL_EXPORTER_OTLP_ENDPOINT=${local.otel_exporter_endpoint}",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=${local.otel_metrics_temporality}",
    "OTEL_RESOURCE_ATTRIBUTES=${local.otel_resource_attrs}",
    "OTEL_SERVICE_NAME=product-catalog",
    "OTEL_SEMCONV_STABILITY_OPT_IN=database",
    "DB_CONNECTION_STRING=postgres://otelu:otelp@${local.postgres_host}/${local.postgres_db}?sslmode=disable",
  ]

  depends_on = [
    docker_container.otel_collector,
    docker_container.flagd,
    docker_container.postgresql,
  ]

  memory = 20
}

# ==================
# Quote
# ==================
resource "docker_container" "quote" {
  name  = "otel-demo-v2-quote"
  image = "${local.image_name}-quote:${local.demo_version}"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["quote"]
  }

  ports {
    internal = 8090
    external = 8090
  }

  env = [
    "IPV6_ENABLED=false",
    "QUOTE_PORT=8090",
    "OTEL_EXPORTER_OTLP_ENDPOINT=http://${local.otel_collector_host}:${local.otel_collector_port_http}",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=${local.otel_metrics_temporality}",
    "OTEL_PHP_AUTOLOAD_ENABLED=true",
    "OTEL_PHP_INTERNAL_METRICS_ENABLED=true",
    "OTEL_RESOURCE_ATTRIBUTES=${local.otel_resource_attrs}",
    "OTEL_SERVICE_NAME=quote",
  ]

  depends_on = [docker_container.otel_collector]

  memory = 40
}

# ==================
# Shipping
# ==================
resource "docker_container" "shipping" {
  name  = "otel-demo-v2-shipping"
  image = "${local.image_name}-shipping:${local.demo_version}"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["shipping"]
  }

  ports {
    internal = 50050
    external = 50050
  }

  env = [
    "IPV6_ENABLED=false",
    "SHIPPING_PORT=50050",
    "QUOTE_ADDR=${local.quote_addr}",
    "OTEL_EXPORTER_OTLP_ENDPOINT=${local.otel_exporter_endpoint}",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=${local.otel_metrics_temporality}",
    "OTEL_RESOURCE_ATTRIBUTES=${local.otel_resource_attrs}",
    "OTEL_SERVICE_NAME=shipping",
  ]

  depends_on = [docker_container.otel_collector]

  memory = 20
}

# ==================
# Image Provider
# ==================
resource "docker_container" "image_provider" {
  name  = "otel-demo-v2-image-provider"
  image = "${local.image_name}-image-provider:${local.demo_version}"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["image-provider"]
  }

  ports {
    internal = 8081
    external = 8081
  }

  env = [
    "IMAGE_PROVIDER_PORT=8081",
    "OTEL_COLLECTOR_HOST=${local.otel_collector_host}",
    "OTEL_COLLECTOR_PORT_GRPC=${local.otel_collector_port_grpc}",
    "OTEL_RESOURCE_ATTRIBUTES=${local.otel_resource_attrs}",
    "OTEL_SERVICE_NAME=image-provider",
  ]

  depends_on = [docker_container.otel_collector]

  memory = 120
}

# ==================
# Recommendation
# ==================
resource "docker_container" "recommendation" {
  name  = "otel-demo-v2-recommendation"
  image = "ghcr.io/open-telemetry/demo:latest-recommendation"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["recommendation"]
  }

  ports {
    internal = 9001
    external = 9001
  }

  env = [
    "RECOMMENDATION_PORT=9001",
    "PRODUCT_CATALOG_ADDR=${local.product_catalog_addr}",
    "FLAGD_HOST=${local.flagd_host}",
    "FLAGD_PORT=${local.flagd_port}",
    "OTEL_PYTHON_LOG_CORRELATION=true",
    "OTEL_EXPORTER_OTLP_ENDPOINT=${local.otel_exporter_endpoint}",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=${local.otel_metrics_temporality}",
    "OTEL_RESOURCE_ATTRIBUTES=${local.otel_resource_attrs}",
    "OTEL_SERVICE_NAME=recommendation",
    "PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python",
  ]

  depends_on = [
    docker_container.product_catalog,
    docker_container.otel_collector,
    docker_container.flagd,
  ]

  memory = 500
}

# ==================
# Product Reviews
# ==================
resource "docker_container" "product_reviews" {
  name  = "otel-demo-v2-product-reviews"
  image = "ghcr.io/open-telemetry/demo:latest-product-reviews"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["product-reviews"]
  }

  ports {
    internal = 3551
    external = 3551
  }

  env = [
    "PRODUCT_REVIEWS_PORT=3551",
    "OTEL_PYTHON_LOG_CORRELATION=true",
    "OTEL_EXPORTER_OTLP_ENDPOINT=${local.otel_exporter_endpoint}",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=${local.otel_metrics_temporality}",
    "OTEL_RESOURCE_ATTRIBUTES=${local.otel_resource_attrs}",
    "OTEL_SERVICE_NAME=product-reviews",
    "OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=true",
    "PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python",
    "DB_CONNECTION_STRING=host=${local.postgres_host} user=otelu password=otelp dbname=${local.postgres_db}",
    "LLM_BASE_URL=${local.llm_base_url}",
    "OPENAI_API_KEY=${local.openai_api_key}",
    "LLM_MODEL=${local.llm_model}",
    "PRODUCT_CATALOG_ADDR=${local.product_catalog_addr}",
    "FLAGD_HOST=${local.flagd_host}",
    "FLAGD_PORT=${local.flagd_port}",
    "LLM_HOST=${local.llm_host}",
    "LLM_PORT=${local.llm_port}",
  ]

  depends_on = [
    docker_container.product_catalog,
    docker_container.llm,
    docker_container.postgresql,
    docker_container.otel_collector,
  ]

  memory = 100
}

# ==================
# Checkout
# ==================
resource "docker_container" "checkout" {
  name  = "otel-demo-v2-checkout"
  image = "${local.image_name}-checkout:${local.demo_version}"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["checkout"]
  }

  ports {
    internal = 5050
    external = 5050
  }

  env = [
    "FLAGD_HOST=${local.flagd_host}",
    "FLAGD_PORT=${local.flagd_port}",
    "CHECKOUT_PORT=5050",
    "CART_ADDR=${local.cart_addr}",
    "CURRENCY_ADDR=${local.currency_addr}",
    "EMAIL_ADDR=${local.email_addr}",
    "PAYMENT_ADDR=${local.payment_addr}",
    "PRODUCT_CATALOG_ADDR=${local.product_catalog_addr}",
    "SHIPPING_ADDR=${local.shipping_addr}",
    "KAFKA_ADDR=${local.kafka_addr}",
    "GOMEMLIMIT=16MiB",
    "OTEL_EXPORTER_OTLP_ENDPOINT=${local.otel_exporter_endpoint}",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=${local.otel_metrics_temporality}",
    "OTEL_RESOURCE_ATTRIBUTES=${local.otel_resource_attrs}",
    "OTEL_SERVICE_NAME=checkout",
  ]

  depends_on = [
    docker_container.cart,
    docker_container.currency,
    docker_container.email,
    docker_container.payment,
    docker_container.product_catalog,
    docker_container.shipping,
    docker_container.otel_collector,
    docker_container.kafka,
    docker_container.flagd,
  ]

  memory = 20
}

# ==================
# Flagd UI
# ==================
resource "docker_container" "flagd_ui" {
  name  = "otel-demo-v2-flagd-ui"
  image = "${local.image_name}-flagd-ui:${local.demo_version}"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["flagd-ui"]
  }

  ports {
    internal = 4000
    external = 4000
  }

  env = [
    "FLAGD_UI_PORT=4000",
    "OTEL_EXPORTER_OTLP_ENDPOINT=http://${local.otel_collector_host}:${local.otel_collector_port_http}",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=${local.otel_metrics_temporality}",
    "OTEL_RESOURCE_ATTRIBUTES=${local.otel_resource_attrs}",
    "OTEL_SERVICE_NAME=flagd-ui",
    "SECRET_KEY_BASE=yYrECL4qbNwleYInGJYvVnSkwJuSQJ4ijPTx5tirGUXrbznFIBFVJdPl5t6O9ASw",
    "PHX_HOST=localhost",
  ]

  volumes {
    host_path      = "${path.cwd}/../src/flagd"
    container_path = "/app/data"
  }

  depends_on = [
    docker_container.otel_collector,
    docker_container.flagd,
  ]

  memory = 200
}

# ==================
# Frontend
# ==================
resource "docker_container" "frontend" {
  name  = "otel-demo-v2-frontend"
  image = "${local.image_name}-frontend:${local.demo_version}"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["frontend"]
  }

  ports {
    internal = 8080
    external = 54716
  }

  env = [
    "PORT=8080",
    "FRONTEND_ADDR=${local.frontend_addr}",
    "AD_ADDR=${local.ad_addr}",
    "CART_ADDR=${local.cart_addr}",
    "CHECKOUT_ADDR=${local.checkout_addr}",
    "CURRENCY_ADDR=${local.currency_addr}",
    "PRODUCT_CATALOG_ADDR=${local.product_catalog_addr}",
    "PRODUCT_REVIEWS_ADDR=${local.product_reviews_addr}",
    "RECOMMENDATION_ADDR=${local.recommendation_addr}",
    "SHIPPING_ADDR=${local.shipping_addr}",
    "OTEL_EXPORTER_OTLP_ENDPOINT=${local.otel_exporter_endpoint}",
    "OTEL_RESOURCE_ATTRIBUTES=${local.otel_resource_attrs}",
    "ENV_PLATFORM=local",
    "OTEL_SERVICE_NAME=frontend",
    "PUBLIC_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://localhost:8080/otlp-http/v1/traces",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=${local.otel_metrics_temporality}",
    "WEB_OTEL_SERVICE_NAME=frontend-web",
    "OTEL_COLLECTOR_HOST=${local.otel_collector_host}",
    "FLAGD_HOST=${local.flagd_host}",
    "FLAGD_PORT=${local.flagd_port}",
  ]

  depends_on = [
    docker_container.ad,
    docker_container.cart,
    docker_container.checkout,
    docker_container.currency,
    docker_container.product_catalog,
    docker_container.quote,
    docker_container.recommendation,
    docker_container.shipping,
    docker_container.otel_collector,
    docker_container.image_provider,
    docker_container.flagd,
  ]

  memory = 250
}

# ==================
# Load Generator
# ==================
resource "docker_container" "load_generator" {
  name  = "otel-demo-v2-load-generator"
  image = "${local.image_name}-load-generator:${local.demo_version}"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["load-generator"]
  }

  ports {
    internal = 8089
    external = 8089
  }

  env = [
    "LOCUST_WEB_PORT=8089",
    "LOCUST_USERS=5",
    "LOCUST_HOST=http://${local.frontend_proxy_addr}",
    "LOCUST_HEADLESS=false",
    "LOCUST_AUTOSTART=true",
    "LOCUST_BROWSER_TRAFFIC_ENABLED=true",
    "OTEL_EXPORTER_OTLP_ENDPOINT=${local.otel_exporter_endpoint}",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=${local.otel_metrics_temporality}",
    "OTEL_RESOURCE_ATTRIBUTES=${local.otel_resource_attrs}",
    "OTEL_SERVICE_NAME=load-generator",
    "PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python",
    "LOCUST_WEB_HOST=0.0.0.0",
    "FLAGD_HOST=${local.flagd_host}",
    "FLAGD_PORT=${local.flagd_port}",
    "FLAGD_OFREP_PORT=${local.flagd_ofrep_port}",
  ]

  depends_on = [
    docker_container.frontend,
    docker_container.flagd,
  ]

  memory = 1536
}

# ==================
# Frontend Proxy (Envoy)
# ==================
resource "docker_container" "frontend_proxy" {
  name  = "otel-demo-v2-frontend-proxy"
  image = "${local.image_name}-frontend-proxy:${local.demo_version}"

  networks_advanced {
    name    = docker_network.otel_network.name
    aliases = ["frontend-proxy"]
  }

  ports {
    internal = 8080
    external = 8080
  }
  ports {
    internal = 10000
    external = 10000
  }

  env = [
    "FRONTEND_PORT=8080",
    "FRONTEND_HOST=frontend",
    "LOCUST_WEB_HOST=load-generator",
    "LOCUST_WEB_PORT=8089",
    "GRAFANA_PORT=${local.grafana_port}",
    "GRAFANA_HOST=${local.grafana_host}",
    "JAEGER_UI_PORT=${local.jaeger_ui_port}",
    "JAEGER_HOST=${local.jaeger_host}",
    "OTEL_COLLECTOR_HOST=${local.otel_collector_host}",
    "IMAGE_PROVIDER_HOST=${local.image_provider_host}",
    "IMAGE_PROVIDER_PORT=${local.image_provider_port}",
    "OTEL_COLLECTOR_PORT_GRPC=${local.otel_collector_port_grpc}",
    "OTEL_COLLECTOR_PORT_HTTP=${local.otel_collector_port_http}",
    "OTEL_RESOURCE_ATTRIBUTES=${local.otel_resource_attrs}",
    "OTEL_SERVICE_NAME=frontend-proxy",
    "ENVOY_PORT=8080",
    "ENVOY_ADDR=0.0.0.0",
    "ENVOY_ADMIN_PORT=10000",
    "FLAGD_HOST=${local.flagd_host}",
    "FLAGD_PORT=${local.flagd_port}",
    "FLAGD_UI_HOST=flagd-ui",
    "FLAGD_UI_PORT=4000",
  ]

  depends_on = [
    docker_container.frontend,
    docker_container.load_generator,
    docker_container.jaeger,
    docker_container.grafana,
    docker_container.flagd_ui,
  ]

  memory = 65
}
