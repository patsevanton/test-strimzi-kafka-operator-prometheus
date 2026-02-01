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

Namespace `myproject` должен существовать заранее (в примерах Strimzi по умолчанию используется именно он):

```bash
kubectl create namespace myproject
```

```bash
helm upgrade --install strimzi-cluster-operator \
  oci://quay.io/strimzi-helm/strimzi-kafka-operator \
  --namespace strimzi \
  --create-namespace \
  --set 'watchNamespaces={myproject}' \
  --wait \
  --version 0.50.0
```

### Установка Kafka из examples

```bash
# Kafka-кластер (JBOD)
curl -s https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/kafka/kafka-jbod.yaml | kubectl apply -n myproject -f -

# Топик
curl -s https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/topic/kafka-topic.yaml | kubectl apply -n myproject -f -

# Пользователь Kafka
curl -s https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/user/kafka-user.yaml | kubectl apply -n myproject -f -
```

### Metrics (examples/metrics)

```bash
# Включить метрики на Kafka-кластере
curl -s https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/metrics/kafka-metrics.yaml | kubectl apply -n myproject -f -

# PodMonitors и правила для Prometheus/VictoriaMetrics (применяем в namespace monitoring)
curl -s https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/metrics/prometheus-install/pod-monitors/cluster-operator-metrics.yaml | kubectl apply -n monitoring -f -

curl -s https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/metrics/prometheus-install/pod-monitors/entity-operator-metrics.yaml | kubectl apply -n monitoring -f -

curl -s https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/metrics/prometheus-install/pod-monitors/kafka-resources-metrics.yaml | kubectl apply -n monitoring -f -

# В примерах Strimzi по умолчанию namespaceSelector: myproject (Kafka и Entity Operator в myproject). Добавить label для kube-prometheus-stack и поправить только cluster-operator на namespace strimzi:
kubectl label podmonitor -n monitoring cluster-operator-metrics entity-operator-metrics kafka-resources-metrics release=kube-prometheus-stack --overwrite
kubectl patch podmonitor -n monitoring cluster-operator-metrics --type=json -p='[{"op": "replace", "path": "/spec/namespaceSelector/matchNames", "value": ["strimzi"]}]'
# entity-operator-metrics и kafka-resources-metrics уже с matchNames: [myproject] — не патчим
```

```bash
# 1. ConfigMap с конфигом метрик по CRD Strimzi
curl -s https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/metrics/kube-state-metrics/configmap.yaml | kubectl apply -n myproject -f -

# 2. Deployment, Service, RBAC и ServiceMonitor
curl -s https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/metrics/kube-state-metrics/ksm.yaml | kubectl apply -n myproject -f -

# 3. Добавить label release: kube-prometheus-stack в ServiceMonitor, чтобы Prometheus его выбирал
kubectl label servicemonitor -n myproject strimzi-kube-state-metrics release=kube-prometheus-stack --overwrite

# 4. Добавить labels на Service (в манифесте Strimzi их нет — ServiceMonitor не находит Service)
kubectl label svc -n myproject strimzi-kube-state-metrics app.kubernetes.io/name=kube-state-metrics app.kubernetes.io/instance=strimzi-kube-state-metrics --overwrite

# 5. В манифесте Strimzi namespace=myproject — при деплое в myproject патч не нужен
```

## Kafka Exporter

- Strimzi — оператор для управления Kafka в Kubernetes; мониторинг вынесен в отдельные компоненты.
- Kafka Exporter — сторонний проект ([danielqsj/kafka_exporter](https://github.com/danielqsj/kafka_exporter)), который подключается к брокерам по Kafka API и отдаёт метрики в формате Prometheus.

**Установка (Helm, Prometheus Operator)**

Репозиторий уже добавлен для kube-prometheus-stack:

```bash
# Установить Kafka Exporter (адрес брокеров — для Strimzi в myproject: my-cluster-kafka-bootstrap:9092)
helm upgrade --install prometheus-kafka-exporter \
  prometheus-community/prometheus-kafka-exporter \
  --namespace monitoring \
  --create-namespace \
  --set kafkaServer[0]=my-cluster-kafka-bootstrap.myproject.svc.cluster.local:9092 \
  --set prometheus.serviceMonitor.enabled=true \
  --set prometheus.serviceMonitor.additionalLabels.release=kube-prometheus-stack
```

Проверка: в Prometheus — target `strimzi-kube-state-metrics` (namespace myproject), метрики `strimzi_kafka_topic_resource_info`, `strimzi_kafka_user_resource_info`, `strimzi_kafka_resource_info`, `strimzi_pod_set_resource_info` и т.д.

# Импорт Дашборды Grafana — импорт JSON из examples/metrics/grafana-dashboards/ через UI Grafana:

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-kafka-exporter.json

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-kafka.json

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-kraft.json

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-operators.json

## Статус проверки

### Strimzi в K8s
- **Установлен** — pods: `strimzi-cluster-operator` (strimzi), `strimzi-kube-state-metrics` (myproject)
- **CRD** — kafkas, kafkatopics, kafkausers и др.
- **Kafka** — my-cluster (Ready), my-topic, my-user

### strimzi-kube-state-metrics в Prometheus (2026-02-01)
- **Target** — есть (myproject/strimzi-kube-state-metrics, health: up). Требовались: labels на Service (шаг 4). При деплое в myproject patch ClusterRoleBinding не нужен.
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

### Можно ли отсутствующие метрики получить из репозитория Strimzi?

**Да.** Почти все отсутствующие метрики можно включить с помощью **YAML и инструкций** из официального репозитория [strimzi/strimzi-kafka-operator](https://github.com/strimzi/strimzi-kafka-operator), каталог `packaging/examples/metrics/`:

| Что нужно | Где взять в репозитории |
|-----------|-------------------------|
| JMX-метрики брокеров Kafka (`kafka_server_*`, `jvm_*`, `kafka_log_*`) | [kafka-metrics.yaml](https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/kafka-metrics.yaml) — Kafka CR с `metricsConfig: jmxPrometheusExporter` + ConfigMap `kafka-metrics` |
| Сбор метрик брокеров в Prometheus | [prometheus-install/pod-monitors/kafka-resources-metrics.yaml](https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/prometheus-install/pod-monitors/kafka-resources-metrics.yaml) |
| Метрики Cluster Operator (`strimzi_reconciliations_*`, `strimzi_resources`, сертификаты) | [prometheus-install/pod-monitors/cluster-operator-metrics.yaml](https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/prometheus-install/pod-monitors/cluster-operator-metrics.yaml) |
| Метрики Entity Operator (Topic/User) | [prometheus-install/pod-monitors/entity-operator-metrics.yaml](https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/prometheus-install/pod-monitors/entity-operator-metrics.yaml) |
| Метрики по CR (Kafka, Topic, User) | [kube-state-metrics/](https://github.com/strimzi/strimzi-kafka-operator/tree/main/packaging/examples/metrics/kube-state-metrics) — configmap.yaml, ksm.yaml |
| Правила и алерты Prometheus | [prometheus-install/prometheus-rules/](https://github.com/strimzi/strimzi-kafka-operator/tree/main/packaging/examples/metrics/prometheus-install/prometheus-rules), [prometheus-install/alert-manager.yaml](https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/prometheus-install/alert-manager.yaml) |

**Важно:** для kube-prometheus-stack все PodMonitor’ы нужно применять в namespace `monitoring` и добавить label `release: kube-prometheus-stack`, иначе Prometheus их не выберет. Документация Strimzi по метрикам: [strimzi.io — Metrics](https://strimzi.io/docs/operators/latest/deploying.html#assembly-metrics-strimzi).

Если кластер уже развёрнут из **kafka-jbod.yaml** (без JMX), не обязательно заменять его на полный **kafka-metrics.yaml** (там KRaft + NodePools): можно добавить в существующий ресурс `Kafka` блок `spec.kafka.metricsConfig` и отдельно применить ConfigMap `kafka-metrics` (фрагмент из [kafka-metrics.yaml](https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/metrics/kafka-metrics.yaml) — секция `kind: ConfigMap`, `name: kafka-metrics`).

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
- Для метрик по CR (Kafka, KafkaTopic, KafkaUser и т.д.) отдельно используется **strimzi-kube-state-metrics**; его ServiceMonitor в namespace деплоя (myproject) должен иметь label `release: kube-prometheus-stack`:
  ```bash
  kubectl label servicemonitor -n myproject strimzi-kube-state-metrics release=kube-prometheus-stack --overwrite
  ```
