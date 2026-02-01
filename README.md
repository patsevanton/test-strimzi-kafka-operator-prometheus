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
```

Проверка: в Prometheus должен появиться target для `strimzi-kube-state-metrics` в namespace `monitoring`, метрики с префиксами `strimzi_kafka_topic_*`, `strimzi_kafka_user_*`, `strimzi_kafka_*` и т.д.

# Импорт Дашборды Grafana — импорт JSON из examples/metrics/grafana-dashboards/ через UI Grafana:

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-kafka-exporter.json

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-kafka.json

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-kraft.json

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-operators.json



## Статус проверки (2026-02-01)

### Strimzi в K8s
- **Установлен** — pods: `strimzi-cluster-operator` (strimzi), `strimzi-kube-state-metrics` (default)
- **CRD** — kafkas, kafkatopics, kafkausers и др.
- **Kafka** — my-cluster (Ready), my-topic, my-user

### Метрики из JSON-дашбордов Grafana (Strimzi)

Список метрик Prometheus, используемых в дашбордах. Статус проверки в Prometheus:

### Kafka Exporter (strimzi-kafka-exporter.json)
- `kafka_topic_partitions` — **отсутствует метрика**
- `kafka_topic_partition_replicas` — **отсутствует метрика**
- `kafka_topic_partition_in_sync_replica` — **отсутствует метрика**
- `kafka_topic_partition_under_replicated_partition` — **отсутствует метрика**
- `kafka_cluster_partition_atminisr` — **отсутствует метрика**
- `kafka_cluster_partition_underminisr` — **отсутствует метрика**
- `kafka_topic_partition_leader_is_preferred` — **отсутствует метрика**
- `kafka_topic_partition_current_offset` — **отсутствует метрика**
- `kafka_topic_partition_oldest_offset` — **отсутствует метрика**
- `kafka_consumergroup_current_offset` — **отсутствует метрика**
- `kafka_consumergroup_lag` — **отсутствует метрика**
- `kafka_broker_info` — **отсутствует метрика**

### Strimzi Kafka (strimzi-kafka.json)
- `kafka_server_replicamanager_leadercount` — **отсутствует метрика**
- `kafka_controller_kafkacontroller_activecontrollercount` — **отсутствует метрика**
- `kafka_controller_controllerstats_uncleanleaderelections_total` — **отсутствует метрика**
- `kafka_server_replicamanager_partitioncount` — **отсутствует метрика**
- `kafka_server_replicamanager_underreplicatedpartitions` — **отсутствует метрика**
- `kafka_cluster_partition_atminisr` — **отсутствует метрика**
- `kafka_cluster_partition_underminisr` — **отсутствует метрика**
- `kafka_controller_kafkacontroller_offlinepartitionscount` — **отсутствует метрика**
- `container_memory_usage_bytes` — **есть**
- `container_cpu_usage_seconds_total` — **есть**
- `kubelet_volume_stats_available_bytes` — **есть**
- `process_open_fds` — **есть**
- `jvm_memory_used_bytes` — **отсутствует метрика**
- `jvm_gc_collection_seconds_sum` — **отсутствует метрика**
- `jvm_gc_collection_seconds_count` — **отсутствует метрика**
- `jvm_threads_current` — **отсутствует метрика**
- `kafka_server_brokertopicmetrics_bytesin_total` — **отсутствует метрика**
- `kafka_server_brokertopicmetrics_bytesout_total` — **отсутствует метрика**
- `kafka_server_brokertopicmetrics_messagesin_total` — **отсутствует метрика**
- `kafka_server_brokertopicmetrics_totalproducerequests_total` — **отсутствует метрика**
- `kafka_server_brokertopicmetrics_failedproducerequests_total` — **отсутствует метрика**
- `kafka_server_brokertopicmetrics_totalfetchrequests_total` — **отсутствует метрика**
- `kafka_server_brokertopicmetrics_failedfetchrequests_total` — **отсутствует метрика**
- `kafka_network_socketserver_networkprocessoravgidle_percent` — **отсутствует метрика**
- `kafka_server_kafkarequesthandlerpool_requesthandleravgidle_percent` — **отсутствует метрика**
- `kafka_server_kafkaserver_linux_disk_write_bytes` — **отсутствует метрика**
- `kafka_server_kafkaserver_linux_disk_read_bytes` — **отсутствует метрика**
- `kafka_server_socket_server_metrics_connection_count` — **отсутствует метрика**
- `kafka_log_log_size` — **отсутствует метрика**
- `kafka_cluster_partition_replicascount` — **отсутствует метрика**

### Strimzi KRaft (strimzi-kraft.json)
- `container_memory_usage_bytes` — **есть**
- `container_cpu_usage_seconds_total` — **есть**
- `kubelet_volume_stats_available_bytes` — **есть**
- `process_open_fds` — **есть**
- `jvm_memory_used_bytes` — **отсутствует метрика**
- `jvm_gc_collection_seconds_sum` — **отсутствует метрика**
- `jvm_gc_collection_seconds_count` — **отсутствует метрика**
- `jvm_threads_current` — **отсутствует метрика**
- `kafka_server_raftmetrics_append_records_rate` — **отсутствует метрика**
- `kafka_server_raftmetrics_fetch_records_rate` — **отсутствует метрика**
- `kafka_server_raftmetrics_commit_latency_avg` — **отсутствует метрика**
- `kafka_server_raftmetrics_current_state` — **отсутствует метрика**
- `kafka_server_raftmetrics_current_leader` — **отсутствует метрика**
- `kafka_server_raftmetrics_current_vote` — **отсутствует метрика**
- `kafka_server_raftmetrics_current_epoch` — **отсутствует метрика**
- `kafka_server_raftchannelmetrics_incoming_byte_total` — **отсутствует метрика**
- `kafka_server_raftchannelmetrics_outgoing_byte_total` — **отсутствует метрика**
- `kafka_server_raftchannelmetrics_request_total` — **отсутствует метрика**
- `kafka_server_raftchannelmetrics_response_total` — **отсутствует метрика**
- `kafka_server_raftmetrics_high_watermark` — **отсутствует метрика**
- `kafka_server_raftmetrics_log_end_offset` — **отсутствует метрика**

### Strimzi Operators (strimzi-operators.json)
- `strimzi_resources` — **отсутствует метрика**
- `strimzi_reconciliations_successful_total` — **отсутствует метрика**
- `strimzi_reconciliations_failed_total` — **отсутствует метрика**
- `strimzi_reconciliations_locked_total` — **отсутствует метрика**
- `strimzi_reconciliations_total` — **отсутствует метрика**
- `strimzi_reconciliations_periodical_total` — **отсутствует метрика**
- `strimzi_reconciliations_duration_seconds_max` — **отсутствует метрика**
- `strimzi_certificate_expiration_timestamp_ms` — **отсутствует метрика**
- `jvm_memory_used_bytes` — **отсутствует метрика**
- `jvm_gc_pause_seconds_sum` — **отсутствует метрика**
- `jvm_gc_pause_seconds_count` — **отсутствует метрика**
сдел
### Почему большинство метрик отсутствуют

- **Kafka Exporter** — не установлен (отдельный компонент, не входит в Strimzi). См. ниже раздел «Kafka Exporter».
- **strimzi_*** — ServiceMonitor `strimzi-kube-state-metrics` в namespace `default` не имеет label `release: kube-prometheus-stack`, Prometheus его не выбирает
- **kafka_server_***, **jvm_*** — PodMonitors (cluster-operator, entity-operator, kafka-resources) не применены или не выбираются Prometheus; метрики Kafka включить через kafka-metrics.yaml и применить PodMonitors в namespace `monitoring` с label `release: kube-prometheus-stack`
- **container_***, **kubelet_***, **process_open_fds** — собираются kubelet и node-exporter (уже есть)



## Kafka Exporter

**Почему Kafka Exporter не входит в Strimzi**

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

