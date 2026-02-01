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

---

## Метрики из JSON-дашбордов Grafana (Strimzi)

Список метрик Prometheus, используемых в дашбордах `strimzi-kafka-exporter.json`, `strimzi-kafka.json`, `strimzi-kraft.json`, `strimzi-operators.json`:

### Kafka Exporter (strimzi-kafka-exporter.json)
- `kafka_topic_partitions`
- `kafka_topic_partition_replicas`
- `kafka_topic_partition_in_sync_replica`
- `kafka_topic_partition_under_replicated_partition`
- `kafka_cluster_partition_atminisr`
- `kafka_cluster_partition_underminisr`
- `kafka_topic_partition_leader_is_preferred`
- `kafka_topic_partition_current_offset`
- `kafka_topic_partition_oldest_offset`
- `kafka_consumergroup_current_offset`
- `kafka_consumergroup_lag`
- `kafka_broker_info`

### Strimzi Kafka (strimzi-kafka.json)
- `kafka_server_replicamanager_leadercount`
- `kafka_controller_kafkacontroller_activecontrollercount`
- `kafka_controller_controllerstats_uncleanleaderelections_total`
- `kafka_server_replicamanager_partitioncount`
- `kafka_server_replicamanager_underreplicatedpartitions`
- `kafka_cluster_partition_atminisr`
- `kafka_cluster_partition_underminisr`
- `kafka_controller_kafkacontroller_offlinepartitionscount`
- `container_memory_usage_bytes`
- `container_cpu_usage_seconds_total`
- `kubelet_volume_stats_available_bytes`
- `process_open_fds`
- `jvm_memory_used_bytes`
- `jvm_gc_collection_seconds_sum`
- `jvm_gc_collection_seconds_count`
- `jvm_threads_current`
- `kafka_server_brokertopicmetrics_bytesin_total`
- `kafka_server_brokertopicmetrics_bytesout_total`
- `kafka_server_brokertopicmetrics_messagesin_total`
- `kafka_server_brokertopicmetrics_totalproducerequests_total`
- `kafka_server_brokertopicmetrics_failedproducerequests_total`
- `kafka_server_brokertopicmetrics_totalfetchrequests_total`
- `kafka_server_brokertopicmetrics_failedfetchrequests_total`
- `kafka_network_socketserver_networkprocessoravgidle_percent`
- `kafka_server_kafkarequesthandlerpool_requesthandleravgidle_percent`
- `kafka_server_kafkaserver_linux_disk_write_bytes`
- `kafka_server_kafkaserver_linux_disk_read_bytes`
- `kafka_server_socket_server_metrics_connection_count`
- `kafka_log_log_size`
- `kafka_cluster_partition_replicascount`

### Strimzi KRaft (strimzi-kraft.json)
- `container_memory_usage_bytes`
- `container_cpu_usage_seconds_total`
- `kubelet_volume_stats_available_bytes`
- `process_open_fds`
- `jvm_memory_used_bytes`
- `jvm_gc_collection_seconds_sum`
- `jvm_gc_collection_seconds_count`
- `jvm_threads_current`
- `kafka_server_raftmetrics_append_records_rate`
- `kafka_server_raftmetrics_fetch_records_rate`
- `kafka_server_raftmetrics_commit_latency_avg`
- `kafka_server_raftmetrics_current_state`
- `kafka_server_raftmetrics_current_leader`
- `kafka_server_raftmetrics_current_vote`
- `kafka_server_raftmetrics_current_epoch`
- `kafka_server_raftchannelmetrics_incoming_byte_total`
- `kafka_server_raftchannelmetrics_outgoing_byte_total`
- `kafka_server_raftchannelmetrics_request_total`
- `kafka_server_raftchannelmetrics_response_total`
- `kafka_server_raftmetrics_high_watermark`
- `kafka_server_raftmetrics_log_end_offset`

### Strimzi Operators (strimzi-operators.json)
- `strimzi_resources`
- `strimzi_reconciliations_successful_total`
- `strimzi_reconciliations_failed_total`
- `strimzi_reconciliations_locked_total`
- `strimzi_reconciliations_total`
- `strimzi_reconciliations_periodical_total`
- `strimzi_reconciliations_duration_seconds_max`
- `strimzi_certificate_expiration_timestamp_ms`
- `jvm_memory_used_bytes`
- `jvm_gc_pause_seconds_sum`
- `jvm_gc_pause_seconds_count`

