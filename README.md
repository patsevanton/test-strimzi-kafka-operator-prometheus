## Установка Prometheus stack (kube-prometheus-stack)

1. Добавить репозиторий Helm:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

3. Установить kube-prometheus-stack с Ingress для Grafana на `grafana.apatsev.org.ru`:

```bash
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --version 81.4.2 \
  --wait \
  --set grafana.ingress.enabled=true \
  --set grafana.ingress.ingressClassName=nginx \
  --set grafana.ingress.hosts[0]=grafana.apatsev.org.ru
```

4. Получить пароль администратора Grafana:

```bash
kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d
echo
```

5. Открыть Grafana: http://grafana.apatsev.org.ru (логин по умолчанию: `admin`).


### Установка Strimzi

Namespace должен существовать заранее, если вы добавляете его в watchNamespaces
```bash
helm upgrade --install strimzi-cluster-operator \
  oci://quay.io/strimzi-helm/strimzi-kafka-operator \
  --namespace strimzi \
  --create-namespace \
  --set 'watchNamespaces={default}' \
  --wait \
  --version 0.50.0
```

### Установка Kafka из examples

CRD устанавливаются оператором Strimzi. После установки оператора применить ресурсы Kafka из examples:


Clone repo
```bash
git clone https://github.com/strimzi/strimzi-kafka-operator.git
cd strimzi-kafka-operator/packaging/examples/
```

```bash
# Kafka-кластер (JBOD)
curl -s https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/kafka/kafka-jbod.yaml | kubectl apply -f -

# Топик
curl -s https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/topic/kafka-topic.yaml | kubectl apply -f -

# Пользователь Kafka
curl -s https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/user/kafka-user.yaml | kubectl apply -f -
```

### Metrics (examples/metrics)

```bash
# Включить метрики на Kafka-кластере
curl -s https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/metrics/kafka-metrics.yaml | kubectl apply -f -

# PodMonitors и правила для Prometheus/VictoriaMetrics (namespace monitoring)
curl -s https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/metrics/prometheus-install/pod-monitors/cluster-operator-metrics.yaml | kubectl apply -f -

curl -s https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/metrics/prometheus-install/pod-monitors/entity-operator-metrics.yaml | kubectl apply -f -

curl -s https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/metrics/prometheus-install/pod-monitors/kafka-resources-metrics.yaml | kubectl apply -f -
```

```bash
# 1. ConfigMap с конфигом метрик по CRD Strimzi
curl -s https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/metrics/kube-state-metrics/configmap.yaml | kubectl apply -f -

# 2. Deployment, Service, RBAC и ServiceMonitor
curl -s https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/metrics/kube-state-metrics/ksm.yaml | kubectl apply -f -

# 3. Добавить label release: kube-prometheus-stack в ServiceMonitor, чтобы Prometheus его выбирал
kubectl label servicemonitor -n default strimzi-kube-state-metrics release=kube-prometheus-stack --overwrite

# 4. Добавить labels на Service (в манифесте Strimzi их нет — ServiceMonitor не находит Service)
kubectl label svc -n default strimzi-kube-state-metrics app.kubernetes.io/name=kube-state-metrics app.kubernetes.io/instance=strimzi-kube-state-metrics --overwrite

# 5. Исправить ClusterRoleBinding: в манифесте namespace=myproject, при деплое в default — патчим
kubectl patch clusterrolebinding strimzi-kube-state-metrics --type='json' -p='[{"op": "replace", "path": "/subjects/0/namespace", "value": "default"}]'
```

## Kafka Exporter

- Strimzi — оператор для управления Kafka в Kubernetes; мониторинг вынесен в отдельные компоненты.
- Kafka Exporter — сторонний проект ([danielqsj/kafka_exporter](https://github.com/danielqsj/kafka_exporter)), который подключается к брокерам по Kafka API и отдаёт метрики в формате Prometheus.
- Разделение даёт гибкость: можно не ставить экспортер, использовать другой (например, JMX Exporter или Strimzi Metrics Reporter) или ограничить доступ к метрикам (топики, consumer groups) по соображениям безопасности.

**Установка (Helm, Prometheus Operator)**

Репозиторий уже добавлен для kube-prometheus-stack:

```bash
# Установить Kafka Exporter (адрес брокеров — для Strimzi в default: my-cluster-kafka-bootstrap:9092)
helm upgrade --install prometheus-kafka-exporter \
  prometheus-community/prometheus-kafka-exporter \
  --namespace monitoring \
  --create-namespace \
  --set kafkaServer[0]=my-cluster-kafka-bootstrap.default.svc.cluster.local:9092 \
  --set prometheus.serviceMonitor.enabled=true \
  --set prometheus.serviceMonitor.additionalLabels.release=kube-prometheus-stack
```

Проверка: в Prometheus — target `strimzi-kube-state-metrics` (namespace default), метрики `strimzi_kafka_topic_resource_info`, `strimzi_kafka_user_resource_info`, `strimzi_kafka_resource_info`, `strimzi_pod_set_resource_info` и т.д.

# Импорт Дашборды Grafana — импорт JSON из examples/metrics/grafana-dashboards/ через UI Grafana:

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-kafka-exporter.json

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-kafka.json

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-kraft.json

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-operators.json

## Статус проверки

### Strimzi в K8s
- **Установлен** — pods: `strimzi-cluster-operator` (strimzi), `strimzi-kube-state-metrics` (default)
- **CRD** — kafkas, kafkatopics, kafkausers и др.
- **Kafka** — my-cluster (Ready), my-topic, my-user

### strimzi-kube-state-metrics в Prometheus (2026-02-01)
- **Target** — есть (default/strimzi-kube-state-metrics, health: up). Требовались: labels на Service (шаг 4) и patch ClusterRoleBinding (шаг 5).
- **Метрики** — есть: `strimzi_kafka_topic_resource_info`, `strimzi_kafka_user_resource_info`, `strimzi_kafka_resource_info`, `strimzi_kafka_node_pool_resource_info`, `strimzi_pod_set_resource_info`.

### Метрики из JSON-дашбордов Grafana (Strimzi)

Список метрик Prometheus, используемых в дашбордах (сверено с JSON из `packaging/examples/metrics/grafana-dashboards/`). Статус проверки в Prometheus:

### Kafka Exporter (strimzi-kafka-exporter.json)
- `kafka_topic_partitions` — **есть**
- `kafka_topic_partition_replicas` — **есть**
- `kafka_topic_partition_in_sync_replica` — **есть**
- `kafka_topic_partition_under_replicated_partition` — **есть**
- `kafka_cluster_partition_atminisr` — **нет**
- `kafka_cluster_partition_underminisr` — **нет**
- `kafka_topic_partition_leader_is_preferred` — **есть**
- `kafka_topic_partition_current_offset` — **есть**
- `kafka_topic_partition_oldest_offset` — **есть**
- `kafka_consumergroup_current_offset` — **нет**
- `kafka_consumergroup_lag` — **нет**
- `kafka_broker_info` — **есть**

### Strimzi Kafka (strimzi-kafka.json)
- `kafka_server_replicamanager_leadercount` — **нет**
- `kafka_controller_kafkacontroller_activecontrollercount` — **нет**
- `kafka_controller_controllerstats_uncleanleaderelections_total` — **нет**
- `kafka_server_replicamanager_partitioncount` — **нет**
- `kafka_server_replicamanager_underreplicatedpartitions` — **нет**
- `kafka_cluster_partition_atminisr` — **нет**
- `kafka_cluster_partition_underminisr` — **нет**
- `kafka_controller_kafkacontroller_offlinepartitionscount` — **нет**
- `container_memory_usage_bytes` — **есть**
- `container_cpu_usage_seconds_total` — **есть**
- `kubelet_volume_stats_available_bytes` — **есть**
- `process_open_fds` — **есть**
- `jvm_memory_used_bytes` — **нет**
- `jvm_gc_collection_seconds_sum` — **нет**
- `jvm_gc_collection_seconds_count` — **нет**
- `jvm_threads_current` — **нет**
- `kafka_server_brokertopicmetrics_bytesin_total` — **нет**
- `kafka_server_brokertopicmetrics_bytesout_total` — **нет**
- `kafka_server_brokertopicmetrics_messagesin_total` — **нет**
- `kafka_server_brokertopicmetrics_totalproducerequests_total` — **нет**
- `kafka_server_brokertopicmetrics_failedproducerequests_total` — **нет**
- `kafka_server_brokertopicmetrics_totalfetchrequests_total` — **нет**
- `kafka_server_brokertopicmetrics_failedfetchrequests_total` — **нет**
- `kafka_network_socketserver_networkprocessoravgidle_percent` — **нет**
- `kafka_server_kafkarequesthandlerpool_requesthandleravgidle_percent` — **нет**
- `kafka_server_kafkaserver_linux_disk_write_bytes` — **нет**
- `kafka_server_kafkaserver_linux_disk_read_bytes` — **нет**
- `kafka_server_socket_server_metrics_connection_count` — **нет**
- `kafka_log_log_size` — **нет**
- `kafka_cluster_partition_replicascount` — **нет**

### Strimzi KRaft (strimzi-kraft.json)
- `container_memory_usage_bytes` — **есть**
- `container_cpu_usage_seconds_total` — **есть**
- `kubelet_volume_stats_available_bytes` — **есть**
- `process_open_fds` — **есть**
- `jvm_memory_used_bytes` — **нет**
- `jvm_gc_collection_seconds_sum` — **нет**
- `jvm_gc_collection_seconds_count` — **нет**
- `jvm_threads_current` — **нет**
- `kafka_server_raftmetrics_append_records_rate` — **нет**
- `kafka_server_raftmetrics_fetch_records_rate` — **нет**
- `kafka_server_raftmetrics_commit_latency_avg` — **нет**
- `kafka_server_raftmetrics_current_state` — **нет**
- `kafka_server_raftmetrics_current_leader` — **нет**
- `kafka_server_raftmetrics_current_vote` — **нет**
- `kafka_server_raftmetrics_current_epoch` — **нет**
- `kafka_server_raftchannelmetrics_incoming_byte_total` — **нет**
- `kafka_server_raftchannelmetrics_outgoing_byte_total` — **нет**
- `kafka_server_raftchannelmetrics_request_total` — **нет**
- `kafka_server_raftchannelmetrics_response_total` — **нет**
- `kafka_server_raftmetrics_high_watermark` — **нет**
- `kafka_server_raftmetrics_log_end_offset` — **нет**

### Strimzi Operators (strimzi-operators.json)
- `strimzi_resources` — **нет**
- `strimzi_reconciliations_successful_total` — **нет**
- `strimzi_reconciliations_failed_total` — **нет**
- `strimzi_reconciliations_locked_total` — **нет**
- `strimzi_reconciliations_total` — **нет**
- `strimzi_reconciliations_periodical_total` — **нет**
- `strimzi_reconciliations_duration_seconds_max` — **нет**
- `strimzi_certificate_expiration_timestamp_ms` — **нет**
- `jvm_memory_used_bytes` — **нет**
- `jvm_gc_pause_seconds_sum` — **нет**
- `jvm_gc_pause_seconds_count` — **нет**

### Почему большинство метрик отсутствуют

Кратко: часть метрик дашборды ждут от **Kafka Exporter** (топики/офсеты/consumer groups), часть — от **JMX брокеров Kafka** (kafka_server_*, jvm_*, kafka_log_* и т.д.), часть — от **Strimzi Cluster/Entity Operator**. Если настроен только Kafka Exporter и обычный kafka-jbod без JMX — метрик из JMX и операторов не будет.

#### Kafka Exporter (strimzi-kafka-exporter.json)

- **`kafka_cluster_partition_atminisr`**, **`kafka_cluster_partition_underminisr`** — Kafka Exporter (danielqsj/kafka_exporter) их **не экспортирует**. Эти метрики идут только из JMX брокеров Kafka. Дашборд ожидает их от Kafka Exporter, но они доступны лишь при сборе JMX через kafka-metrics.yaml и PodMonitors (см. ниже).

- **`kafka_consumergroup_current_offset`**, **`kafka_consumergroup_lag`** — Kafka Exporter их экспортирует, но:
  - В кластере должны быть **активные consumer groups** (если ни один consumer не подключён к группе — метрик нет)
  - Нужны права **DescribeGroups** на Kafka (для Strimzi — ACL для пользователя, если используется)
  - Проверить `group.filter` / `group.exclude` в Helm Kafka Exporter (по умолчанию `.*` / `^$` — все группы)

#### Strimzi Kafka (strimzi-kafka.json), Strimzi KRaft (strimzi-kraft.json)

- **`kafka_server_*`**, **`jvm_*`**, **`kafka_log_log_size`**, **`kafka_cluster_partition_*`** — метрики из **JMX** брокеров Kafka. Для их появления нужно:
  1. Применить **kafka-metrics.yaml** вместо kafka-jbod.yaml (в нём `metricsConfig: jmxPrometheusExporter` и ConfigMap `kafka-metrics`)
  2. Применить **PodMonitors** (kafka-resources-metrics и др.) в namespace `monitoring` с label `release: kube-prometheus-stack`

#### Strimzi Operators (strimzi-operators.json)

- **`strimzi_resources`**, **`strimzi_reconciliations_*`**, **`strimzi_certificate_expiration_timestamp_ms`** — отдаёт **Strimzi Cluster Operator** (и при необходимости Entity Operator) со своего HTTP `/metrics`. Нужны **PodMonitor’ы/ServiceMonitor’ы** для оператора с label `release: kube-prometheus-stack`:
  - `cluster-operator-metrics.yaml` и при использовании Entity Operator — `entity-operator-metrics.yaml` из `prometheus-install/pod-monitors/`, применённые в namespace `monitoring`. Без них Prometheus не скрейпит метрики оператора, дашборд «Operators» пустой.
- **`jvm_memory_used_bytes`**, **`jvm_gc_pause_seconds_*`** — JMX-метрики JVM контейнеров `strimzi-cluster-operator`, `topic-operator`, `user-operator`. Появляются, когда для этих подов настроен сбор метрик (например, через те же PodMonitor’ы для операторов с аннотациями/конфигом JMX).
- Для метрик по CR (Kafka, KafkaTopic, KafkaUser и т.д.) отдельно используется **strimzi-kube-state-metrics**; его ServiceMonitor в namespace деплоя должен иметь label `release: kube-prometheus-stack`:
  ```bash
  kubectl label servicemonitor -n default strimzi-kube-state-metrics release=kube-prometheus-stack --overwrite
  ```
