## Установка Prometheus stack (kube-prometheus-stack)

1. Добавить репозиторий Helm:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

2. Установить kube-prometheus-stack с Ingress для Grafana на `grafana.apatsev.org.ru` (при первом запуске установка может занять несколько минут из-за `--wait`):

```bash
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --version 81.4.2 \
  --wait \
  --set grafana.ingress.enabled=true \
  --set grafana.ingress.ingressClassName=nginx \
  --set grafana.ingress.hosts[0]=grafana.apatsev.org.ru \
  --timeout 10m
```

3. Получить пароль администратора Grafana:

```bash
kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d
echo
```

4. Открыть Grafana: http://grafana.apatsev.org.ru (логин по умолчанию: `admin`).

### Strimzi

Strimzi — оператор для управления Kafka в Kubernetes; мониторинг вынесен в отдельные компоненты (Kafka Exporter, kube-state-metrics, PodMonitors для брокеров и операторов).

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
# Kafka-кластер (KRaft, persistent — KafkaNodePool controller + broker)
curl -s https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/kafka/kafka-persistent.yaml | kubectl apply -n myproject -f -

# Топик
curl -s https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/topic/kafka-topic.yaml | kubectl apply -n myproject -f -

# Пользователь Kafka
curl -s https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/user/kafka-user.yaml | kubectl apply -n myproject -f -
```

**Ожидание готовности Kafka** (кластер поднимается несколько минут):

```bash
kubectl wait kafka/my-cluster -n myproject --for=condition=Ready --timeout=600s
```

### Metrics (examples/metrics)

**Внимание:** Kafka развёрнут из **kafka-persistent.yaml** (KRaft). Для JMX-метрик добавьте в существующий ресурс `Kafka` блок `spec.kafka.metricsConfig` и ConfigMap `kafka-metrics` (инструкция — в разделе [Как активировать метрики](#как-активировать-метрики)).

```bash
# PodMonitors для Prometheus/VictoriaMetrics (применяем в namespace monitoring)
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

- Kafka Exporter — сторонний проект ([danielqsj/kafka_exporter](https://github.com/danielqsj/kafka_exporter)), который подключается к брокерам по Kafka API и отдаёт метрики в формате Prometheus.

**Установка (Helm, Prometheus Operator)**

Репозиторий уже добавлен для kube-prometheus-stack. Kafka без аутентификации — установите экспортер:

```bash
helm upgrade --install prometheus-kafka-exporter \
  prometheus-community/prometheus-kafka-exporter \
  --namespace monitoring \
  --create-namespace \
  --set kafkaServer[0]=my-cluster-kafka-bootstrap.myproject.svc.cluster.local:9092 \
  --set prometheus.serviceMonitor.enabled=true \
  --set prometheus.serviceMonitor.additionalLabels.release=kube-prometheus-stack
```

Проверка: в Prometheus — target `prometheus-kafka-exporter` (namespace monitoring), метрики `kafka_topic_partitions`, `kafka_topic_partition_current_offset` и др. Метрики `strimzi_*` (`strimzi_kafka_topic_resource_info`, `strimzi_pod_set_resource_info` и т.д.) — от strimzi-kube-state-metrics (раздел [Metrics](#metrics-examplesmetrics)).

## Импорт дашбордов Grafana

Импорт JSON из `examples/metrics/grafana-dashboards/` через UI Grafana:

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-kafka-exporter.json

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-kafka.json

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-kraft.json

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-operators.json

### Проверка наличия метрик (Prometheus)

После установки убедиться, что Prometheus собирает метрики для дашбордов Strimzi.

**Скрипт проверки всех метрик** из JSON-дашбордов Grafana (извлечены из `packaging/examples/metrics/grafana-dashboards/`):

```bash
# Вариант 1: скрипт сам поднимет port-forward к Prometheus (по умолчанию):
./scripts/check-grafana-metrics-in-prometheus.sh
```

Либо вручную: port-forward в одном терминале, в другом — скрипт с `SKIP_PORT_FORWARD=1` (иначе скрипт попытается поднять второй port-forward и будет конфликт портов):

```bash
# Терминал 1:
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Терминал 2:
SKIP_PORT_FORWARD=1 PROM_URL=http://localhost:9090 ./scripts/check-grafana-metrics-in-prometheus.sh
```

```bash
# Вариант 2: из пода в кластере (в образе Prometheus обычно нет curl; при наличии curl или wget):
kubectl cp scripts/check-grafana-metrics-in-prometheus.sh monitoring/$(kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}'):/tmp/check.sh
kubectl exec -n monitoring deploy/kube-prometheus-stack-prometheus -- sh -c 'PROM_URL=http://localhost:9090 sh /tmp/check.sh'
```

**Быстрая проверка ключевых метрик** (нужен curl и доступ к Prometheus из пода; при необходимости запустите временный debug pod в namespace monitoring):

```bash
PROM="http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090/api/v1/query"
for m in strimzi_resources strimzi_reconciliations_total kafka_topic_partitions strimzi_kafka_topic_resource_info container_memory_usage_bytes; do
  r=$(curl -sG "$PROM" --data-urlencode "query=$m"); echo -n "$m: "; echo "$r" | grep -q '"result":\[\]' && echo "нет" || (echo "$r" | grep -q '"result":\[' && echo "есть" || echo "?")
done
```

Либо в UI Prometheus (Status → Targets): targets `strimzi-kube-state-metrics`, `cluster-operator-metrics`, `kafka-resources-metrics`, `prometheus-kafka-exporter` в состоянии up.

## Статус проверки

### Strimzi в K8s
- **Установлен** — pods: `strimzi-cluster-operator` (strimzi), `strimzi-kube-state-metrics` (myproject)
- **CRD** — kafkas, kafkatopics, kafkausers и др.
- **Kafka** — my-cluster (Ready), my-topic, my-user

### strimzi-kube-state-metrics в Prometheus (2026-02-01)
- **Target** — есть (myproject/strimzi-kube-state-metrics, health: up). Требовались: labels на Service (шаг 4). При деплое в myproject patch ClusterRoleBinding не нужен.
- **Метрики** — есть: `strimzi_kafka_topic_resource_info`, `strimzi_kafka_user_resource_info`, `strimzi_kafka_resource_info`, `strimzi_kafka_node_pool_resource_info`, `strimzi_pod_set_resource_info`.

### Метрики из JSON-дашбордов Grafana (Strimzi)

**Почему дашборды Strimzi Kafka и Strimzi KRaft показывают «no data»?** Они строятся по JMX-метрикам брокеров Kafka (`kafka_server_*`, `jvm_*`, `kafka_server_raftmetrics_*` и т.д.). Кластер из **kafka-persistent.yaml** по умолчанию не включает JMX Exporter — метрик нет, дашборды пустые. Чтобы появились данные: включите JMX-метрики по разделу [Как активировать метрики](#как-активировать-метрики) (блок «Команды для JMX-метрик брокеров»).

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

### Как активировать метрики

Чтобы дашборды Grafana (Strimzi) показывали данные, нужно включить сбор метрик и настроить Prometheus:

1. **Метрики брокеров Kafka (JMX)** — `kafka_server_*`, `jvm_*`, `kafka_log_*`, `kafka_cluster_partition_atminisr` и др.:
   - Применить [kafka-metrics.yaml](https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/metrics/kafka-metrics.yaml) в namespace кластера (или добавить в существующий Kafka CR блок `spec.kafka.metricsConfig` и ConfigMap `kafka-metrics`).
   - Применить PodMonitor для брокеров в namespace `monitoring` и добавить label `release=kube-prometheus-stack` (см. раздел [Metrics (examples/metrics)](#metrics-examplesmetrics)).

2. **Метрики Cluster/Entity Operator** — `strimzi_resources`, `strimzi_reconciliations_*`, `strimzi_certificate_expiration_timestamp_ms`:
   - Применить PodMonitors `cluster-operator-metrics.yaml` и при необходимости `entity-operator-metrics.yaml` из `prometheus-install/pod-monitors/` в namespace `monitoring`.
   - Добавить label `release=kube-prometheus-stack` и для cluster-operator поправить `namespaceSelector.matchNames` на `["strimzi"]` (см. раздел [Metrics (examples/metrics)](#metrics-examplesmetrics)).

3. **Метрики по CR (Kafka, Topic, User)** — `strimzi_kafka_*`, `strimzi_pod_set_*`:
   - Развернуть strimzi-kube-state-metrics (configmap + ksm.yaml) и пометить ServiceMonitor и Service нужными labels (см. раздел [Metrics (examples/metrics)](#metrics-examplesmetrics)).

4. **Метрики топиков/офсетов/consumer groups** — Kafka Exporter:
   - Установить Helm chart `prometheus-kafka-exporter` с ServiceMonitor и указать bootstrap брокеров (см. раздел [Kafka Exporter](#kafka-exporter)).
   - Для `kafka_consumergroup_*`: нужны активные consumer groups и права DescribeGroups (ACL для KafkaUser).

5. **Проверка**: выполнить скрипт `scripts/check-grafana-metrics-in-prometheus.sh` или быструю проверку ключевых метрик (см. раздел [Проверка наличия метрик (Prometheus)](#проверка-наличия-метрик-prometheus)).

#### Команды для JMX-метрик брокеров (Strimzi Kafka, Strimzi KRaft)

Если Kafka уже развёрнут из kafka-persistent (KRaft), добавьте JMX-метрики без замены кластера:

```bash
# 1. Извлечь ConfigMap kafka-metrics из kafka-metrics.yaml и применить в namespace Kafka
curl -sL https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/metrics/kafka-metrics.yaml | \
  awk '/^---$/{out=""} {out=out $0 "\n"} END{print out}' | kubectl apply -n myproject -f -

# 2. Добавить metricsConfig в существующий Kafka CR (подставьте my-cluster и myproject)
kubectl patch kafka my-cluster -n myproject --type=json -p='[{"op": "add", "path": "/spec/kafka/metricsConfig", "value": {"type": "jmxPrometheusExporter", "valueFrom": {"configMapKeyRef": {"name": "kafka-metrics", "key": "kafka-metrics-config.yml"}}}}]'

# 3. PodMonitor для брокеров (если ещё не применён)
curl -sL https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/metrics/prometheus-install/pod-monitors/kafka-resources-metrics.yaml | kubectl apply -n monitoring -f -
kubectl label podmonitor -n monitoring kafka-resources-metrics release=kube-prometheus-stack --overwrite

# 4. Дождаться перезапуска брокеров (Strimzi добавит JMX в под и откроет порт 9404). В KRaft брокеры управляются StrimziPodSet, не StatefulSet — просто подождите 2–5 минут и проверьте, что у подов есть порт tcp-prometheus (9404) и метрики доступны
kubectl get pods -n myproject -l strimzi.io/name=my-cluster-kafka -o wide
# Проверка JMX из пода: kubectl exec -n myproject my-cluster-broker-0 -- wget -qO- http://localhost:9404/metrics | head -5
```

#### Команды для метрик Cluster Operator (Strimzi Operators)

```bash
# PodMonitors для Cluster и Entity Operator (если ещё не применены)
curl -sL https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/metrics/prometheus-install/pod-monitors/cluster-operator-metrics.yaml | kubectl apply -n monitoring -f -
curl -sL https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/metrics/prometheus-install/pod-monitors/entity-operator-metrics.yaml | kubectl apply -n monitoring -f -

kubectl label podmonitor -n monitoring cluster-operator-metrics entity-operator-metrics release=kube-prometheus-stack --overwrite
kubectl patch podmonitor -n monitoring cluster-operator-metrics --type=json -p='[{"op": "replace", "path": "/spec/namespaceSelector/matchNames", "value": ["strimzi"]}]'
```

Подробнее: таблица [Можно ли отсутствующие метрики получить из репозитория Strimzi?](#можно-ли-отсутствующие-метрики-получить-из-репозитория-strimzi) и раздел [Почему большинство метрик отсутствуют](#почему-большинство-метрик-отсутствуют).

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

Если кластер уже развёрнут из **kafka-persistent.yaml** (KRaft, без JMX), не обязательно заменять его на **kafka-metrics.yaml**: можно добавить в существующий ресурс `Kafka` блок `spec.kafka.metricsConfig` и отдельно применить ConfigMap `kafka-metrics` (фрагмент из [kafka-metrics.yaml](https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/main/packaging/examples/metrics/kafka-metrics.yaml) — секция `kind: ConfigMap`, `name: kafka-metrics`).

### Почему большинство метрик отсутствуют

Кратко: часть метрик дашборды ждут от **Kafka Exporter** (топики/офсеты/consumer groups), часть — от **JMX брокеров Kafka** (kafka_server_*, jvm_*, kafka_log_* и т.д.), часть — от **Strimzi Cluster/Entity Operator**. Если настроен только Kafka Exporter и кластер kafka-persistent без JMX — метрик из JMX и операторов не будет.

#### Kafka Exporter (strimzi-kafka-exporter.json)

- **`kafka_cluster_partition_atminisr`**, **`kafka_cluster_partition_underminisr`** — Kafka Exporter (danielqsj/kafka_exporter) их **не экспортирует**. Эти метрики идут только из JMX брокеров Kafka. Дашборд ожидает их от Kafka Exporter, но они доступны лишь при сборе JMX через kafka-metrics.yaml и PodMonitors (см. ниже).

- **`kafka_consumergroup_current_offset`**, **`kafka_consumergroup_lag`** — Kafka Exporter их экспортирует, но:
  - В кластере должны быть **активные consumer groups** (если ни один consumer не подключён к группе — метрик нет)
  - Нужны права **DescribeGroups** на Kafka (для Strimzi — ACL для пользователя, если используется)
  - Проверить `group.filter` / `group.exclude` в Helm Kafka Exporter (по умолчанию `.*` / `^$` — все группы)

#### Strimzi Kafka (strimzi-kafka.json), Strimzi KRaft (strimzi-kraft.json)

- **`kafka_server_*`**, **`jvm_*`**, **`kafka_log_log_size`**, **`kafka_cluster_partition_*`** — метрики из **JMX** брокеров Kafka. Для их появления нужно:
  1. Добавить в **Kafka** CR блок `spec.kafka.metricsConfig` и ConfigMap `kafka-metrics` (из [kafka-metrics.yaml](https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/kafka-metrics.yaml))
  2. Применить **PodMonitors** (kafka-resources-metrics и др.) в namespace `monitoring` с label `release: kube-prometheus-stack`

#### Strimzi Operators (strimzi-operators.json)

- **`strimzi_resources`**, **`strimzi_reconciliations_*`**, **`strimzi_certificate_expiration_timestamp_ms`** — отдаёт **Strimzi Cluster Operator** (и при необходимости Entity Operator) со своего HTTP `/metrics`. Нужны **PodMonitor’ы/ServiceMonitor’ы** для оператора с label `release: kube-prometheus-stack`:
  - `cluster-operator-metrics.yaml` и при использовании Entity Operator — `entity-operator-metrics.yaml` из `prometheus-install/pod-monitors/`, применённые в namespace `monitoring`. Без них Prometheus не скрейпит метрики оператора, дашборд «Operators» пустой.
- **`jvm_memory_used_bytes`**, **`jvm_gc_pause_seconds_*`** — JMX-метрики JVM контейнеров `strimzi-cluster-operator`, `topic-operator`, `user-operator`. Появляются, когда для этих подов настроен сбор метрик (например, через те же PodMonitor’ы для операторов с аннотациями/конфигом JMX).
- Для метрик по CR (Kafka, KafkaTopic, KafkaUser и т.д.) отдельно используется **strimzi-kube-state-metrics**; его ServiceMonitor в namespace деплоя (myproject) должен иметь label `release: kube-prometheus-stack`:
  ```bash
  kubectl label servicemonitor -n myproject strimzi-kube-state-metrics release=kube-prometheus-stack --overwrite
  ```

### Schema Registry (Karapace) для Avro

Go-приложение из этого репозитория использует Avro и Schema Registry API. Для удобства здесь добавлены готовые манифесты для **[Karapace](https://github.com/Aiven-Open/karapace)** — open-source реализации API Confluent Schema Registry (drop-in replacement).

Karapace поднимается как обычный HTTP-сервис и хранит схемы в Kafka-топике `_schemas` (как и Confluent SR).

- `strimzi/kafka-topic-schemas.yaml` — KafkaTopic для `_schemas` (важно при `min.insync.replicas: 2`)
- `schema-registry.yaml` — Service/Deployment для Karapace (`ghcr.io/aiven-open/karapace:5.0.3`). Подключение к Kafka без аутентификации (PLAINTEXT). Для одной реплики задан `KARAPACE_MASTER_ELIGIBILITY=true` (иначе возможна ошибка «No master set» при регистрации схем).

Файлы `strimzi/` в репозитории используют `namespace: myproject` и `strimzi.io/cluster: my-cluster`. В `schema-registry.yaml` задан `KARAPACE_BOOTSTRAP_URI`: `my-cluster-kafka-bootstrap.myproject.svc.cluster.local:9092`. Подставьте свой namespace/кластер, если иные.

```bash
kubectl create namespace schema-registry --dry-run=client -o yaml | kubectl apply -f -

# Создать топик для схем
kubectl apply -f strimzi/kafka-topic-schemas.yaml
kubectl wait kafkatopic/schemas-topic -n myproject --for=condition=Ready --timeout=120s

# Развернуть Schema Registry
kubectl apply -f schema-registry.yaml
kubectl rollout status deploy/schema-registry -n schema-registry --timeout=5m
# Подождать выбор master в Karapace (иначе Producer может получить 50003 "forwarding to the master")
sleep 60
kubectl get svc -n schema-registry schema-registry
```

## Producer App и Consumer App

**Producer App и Consumer App** — Go приложение для работы с Apache Kafka через Strimzi. Приложение может работать в режиме producer (отправка сообщений) или consumer (получение сообщений) в зависимости от переменной окружения `MODE`. Сообщения сериализуются в **Avro** с использованием **Schema Registry (Karapace)** — совместимого с Confluent API. Перед запуском Producer/Consumer необходимо развернуть Schema Registry (см. раздел «Schema Registry (Karapace) для Avro») и передать `schemaRegistry.url` в Helm.

### Используемые библиотеки

- **[segmentio/kafka-go](https://github.com/segmentio/kafka-go)** — клиент для работы с Kafka
- **[riferrei/srclient](https://github.com/riferrei/srclient)** — клиент для Schema Registry API (совместим с Karapace)
- **[linkedin/goavro](https://github.com/linkedin/goavro)** — работа с Avro схемами

### Структура исходного кода

- `main.go` — основной код Go-приложения (producer/consumer)
- `go.mod`, `go.sum` — файлы зависимостей Go модуля
- `Dockerfile` — многоэтапная сборка Docker образа

### Сборка и публикация Docker образа

Go-код в `main.go` можно изменять под свои нужды. После внесения изменений соберите и опубликуйте Docker образ:

```bash
# Сборка образа (используйте podman или docker)
podman build -t docker.io/antonpatsev/strimzi-kafka-chaos-testing:3.4.0 .

# Публикация в Docker Hub
podman push docker.io/antonpatsev/strimzi-kafka-chaos-testing:3.4.0
```

После публикации обновите версию образа в Helm values или передайте через `--set`:

```bash
helm upgrade --install kafka-producer ./helm/kafka-producer \
  --namespace myproject \
  --create-namespace \
  --set image.repository="antonpatsev/strimzi-kafka-chaos-testing" \
  --set image.tag="3.4.0"
```

### Переменные окружения

| Переменная | Описание | Значение по умолчанию |
|------------|----------|----------------------|
| `MODE` | Режим работы: `producer` или `consumer` | `producer` |
| `KAFKA_BROKERS` | Список брокеров Kafka (через запятую) | `localhost:9092` |
| `KAFKA_TOPIC` | Название топика | `my-topic` (как в [Strimzi examples](https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/topic/kafka-topic.yaml)) |
| `SCHEMA_REGISTRY_URL` | URL Schema Registry | `http://localhost:8081` |
| `KAFKA_GROUP_ID` | Consumer Group ID (только для consumer) | `my-group` (как в [Strimzi kafka-user](https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/user/kafka-user.yaml)) |
| `HEALTH_PORT` | Порт для health-проверок (liveness/readiness) | `8080` |

### Запуск Producer/Consumer в кластере используя Helm

Для запуска приложений в кластере используйте Helm charts из директории `helm`. Kafka работает без аутентификации. Имена приведены к [примерам Strimzi](https://github.com/strimzi/strimzi-kafka-operator/tree/main/packaging/examples): `my-topic`, `my-group`.

#### 1) Установить Producer
```bash
helm upgrade --install kafka-producer ./helm/kafka-producer \
  --namespace myproject \
  --create-namespace \
  --set kafka.brokers="my-cluster-kafka-bootstrap.myproject.svc.cluster.local:9092" \
  --set schemaRegistry.url="http://schema-registry.schema-registry:8081" \
  --set kafka.topic="my-topic"
```

#### 2) Установить Consumer
```bash
helm upgrade --install kafka-consumer ./helm/kafka-consumer \
  --namespace kafka-consumer \
  --create-namespace \
  --set kafka.brokers="my-cluster-kafka-bootstrap.myproject.svc.cluster.local:9092" \
  --set schemaRegistry.url="http://schema-registry.schema-registry:8081" \
  --set kafka.topic="my-topic" \
  --set kafka.groupId="my-group"
```

#### 3) Дождаться готовности подов Producer/Consumer
```bash
kubectl rollout status deploy/kafka-producer -n myproject --timeout=120s
kubectl rollout status deploy/kafka-consumer -n kafka-consumer --timeout=120s
# Либо следить за подами: kubectl get pods -n myproject; kubectl get pods -n kafka-consumer -w
```

#### 4) Проверка логов
```bash
# Producer logs
kubectl logs -n myproject -l app.kubernetes.io/name=kafka-producer -f

# Consumer logs
kubectl logs -n kafka-consumer -l app.kubernetes.io/name=kafka-consumer -f
```

### Проверка подов и логов после установки

Убедитесь, что все поды в статусе **Running**:

```bash
kubectl get pods -n monitoring
kubectl get pods -n strimzi
kubectl get pods -n myproject
kubectl get pods -n kafka-consumer
kubectl get pods -n schema-registry
```

При необходимости проверьте логи на ошибки (ищите строки с `ERROR`, `error`, `Fatal`):

```bash
# Producer и Consumer
kubectl logs -n myproject -l app.kubernetes.io/name=kafka-producer --tail=50
kubectl logs -n kafka-consumer -l app.kubernetes.io/name=kafka-consumer --tail=50

# Schema Registry, Strimzi operator, Kafka Exporter
kubectl logs -n schema-registry deploy/schema-registry --tail=30
kubectl logs -n strimzi deploy/strimzi-cluster-operator --tail=30
kubectl logs -n monitoring -l app=prometheus-kafka-exporter --tail=20
```
