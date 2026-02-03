## Установка Prometheus stack (kube-prometheus-stack)

1. Добавить репозиторий Helm:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

**Когда команды не нужны:** если репозиторий уже добавлен (`helm repo list | grep prometheus-community`), команду `helm repo add` можно пропустить; `helm repo update` полезен для получения актуальных чартов.

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

**Когда команда не нужна:** если kube-prometheus-stack уже установлен в namespace `monitoring` (`helm list -n monitoring | grep kube-prometheus-stack`), повторная установка не требуется.

3. Получить пароль администратора Grafana:

```bash
kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d
echo
```

**Когда команда не нужна:** если пароль уже сохранён или получен ранее.

4. Открыть Grafana: http://grafana.apatsev.org.ru (логин по умолчанию: `admin`).

### Strimzi

Strimzi — оператор для управления Kafka в Kubernetes; мониторинг вынесен в отдельные компоненты (Kafka Exporter, kube-state-metrics, PodMonitors для брокеров и операторов).

Манифесты из examples Strimzi сохранены локально в директории **strimzi/** (kafka-metrics, kafka-topic, kafka-user, PodMonitors, kube-state-metrics). Установка — через `kubectl apply -f strimzi/...`.

### Установка Strimzi

Namespace `myproject` должен существовать заранее (в примерах Strimzi по умолчанию используется именно он):

```bash
# Идемпотентно: создаёт namespace только если его ещё нет
kubectl get ns myproject 2>/dev/null || kubectl create namespace myproject
```

**Когда команда не нужна:** если namespace `myproject` уже существует, `kubectl get ns myproject` выполнится успешно и `kubectl create namespace` не запустится.

```bash
helm upgrade --install strimzi-cluster-operator \
  oci://quay.io/strimzi-helm/strimzi-kafka-operator \
  --namespace strimzi \
  --create-namespace \
  --set 'watchNamespaces={myproject}' \
  --wait \
  --version 0.50.0
```

**Когда команда не нужна:** если Strimzi operator уже установлен в namespace `strimzi` (`helm list -n strimzi | grep strimzi-cluster-operator`), установку можно пропустить.

### Установка Kafka из examples (локальные манифесты в strimzi/)

```bash
# Kafka-кластер (KRaft, persistent, JMX-метрики и Kafka Exporter из коробки)
kubectl apply -n myproject -f strimzi/kafka-metrics.yaml

# Топик
kubectl apply -n myproject -f strimzi/kafka-topic.yaml

# Пользователь Kafka
kubectl apply -n myproject -f strimzi/kafka-user.yaml
```

**Когда команды не нужны:** если Kafka-кластер, топик и пользователь уже созданы в `myproject`, повторный `kubectl apply` можно пропустить (идемпотентно обновит ресурсы при изменении манифестов).

```bash
# Дождаться готовности Kafka (при первом развёртывании может занять несколько минут)
kubectl wait kafka/my-cluster -n myproject --for=condition=Ready --timeout=600s
```

### Metrics (examples/metrics)

Kafka развёрнут из **kafka-metrics.yaml** — JMX-метрики (`metricsConfig`) и Kafka Exporter уже включены в манифест. Остаётся применить PodMonitors для сбора метрик в Prometheus.

```bash
# PodMonitors для Prometheus: сбор метрик Strimzi Cluster Operator, Entity Operator (Topic/User) и Kafka-брокеров (JMX)
kubectl apply -n monitoring -f strimzi/cluster-operator-metrics.yaml
kubectl apply -n monitoring -f strimzi/entity-operator-metrics.yaml
kubectl apply -n monitoring -f strimzi/kafka-resources-metrics.yaml

# В примерах Strimzi по умолчанию namespaceSelector: myproject (Kafka и Entity Operator в myproject). Добавить label для kube-prometheus-stack и поправить только cluster-operator на namespace strimzi:
kubectl label podmonitor -n monitoring cluster-operator-metrics entity-operator-metrics kafka-resources-metrics release=kube-prometheus-stack --overwrite
kubectl patch podmonitor -n monitoring cluster-operator-metrics --type=json -p='[{"op": "replace", "path": "/spec/namespaceSelector/matchNames", "value": ["strimzi"]}]'
# entity-operator-metrics и kafka-resources-metrics уже с matchNames: [myproject] — не патчим
```

**ServiceMonitor для Strimzi Kafka Exporter** (kafka-metrics.yaml включает Kafka Exporter в ресурсе Kafka). Strimzi создаёт Service `my-cluster-kafka-exporter` в myproject. Создайте ServiceMonitor, чтобы Prometheus собирал метрики топиков и consumer groups:

```bash
kubectl apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kafka-exporter
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      strimzi.io/kind: KafkaExporter
  namespaceSelector:
    matchNames:
      - myproject
  endpoints:
    - port: metrics
      path: /metrics
EOF
```

```bash
# 1. ConfigMap с конфигом метрик по CRD Strimzi
kubectl apply -n myproject -f strimzi/kube-state-metrics-configmap.yaml

# 2. Deployment, Service, RBAC и ServiceMonitor
kubectl apply -n myproject -f strimzi/kube-state-metrics-ksm.yaml

# 3. Добавить label release: kube-prometheus-stack в ServiceMonitor, чтобы Prometheus его выбирал
kubectl label servicemonitor -n myproject strimzi-kube-state-metrics release=kube-prometheus-stack --overwrite

# 4. Добавить labels на Service (в манифесте Strimzi их нет — ServiceMonitor не находит Service)
kubectl label svc -n myproject strimzi-kube-state-metrics app.kubernetes.io/name=kube-state-metrics app.kubernetes.io/instance=strimzi-kube-state-metrics --overwrite

# 5. В манифесте Strimzi namespace=myproject — при деплое в myproject патч не нужен
```

## Kafka Exporter

Kafka Exporter ([danielqsj/kafka_exporter](https://github.com/danielqsj/kafka_exporter)) подключается к брокерам по Kafka API и отдаёт метрики в формате Prometheus.

**kafka-metrics.yaml** уже включает Kafka Exporter в ресурсе `Kafka` (`spec.kafkaExporter`). Strimzi развернёт его в namespace кластера. Для сбора метрик добавьте ServiceMonitor с label `release=kube-prometheus-stack`.

## Импорт дашбордов Grafana

Импорт JSON из `examples/metrics/grafana-dashboards/` через UI Grafana:

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-kafka-exporter.json

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-kafka.json

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-kraft.json

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-operators.json

Проверка метрик: `./scripts/check-grafana-metrics-in-prometheus.sh` (скрипт поднимает port-forward к Prometheus). Либо в UI Prometheus (Status → Targets): targets `strimzi-kube-state-metrics`, `cluster-operator-metrics`, `kafka-resources-metrics`, `kafka-exporter` в состоянии up.

Метрики `kafka_consumergroup_current_offset` и `kafka_consumergroup_lag` появляются в Prometheus только при наличии активных consumer groups (например, после запуска Consumer); без потребителей скрипт проверки покажет их как отсутствующие — это ожидаемо. **После установки Producer и Consumer подождите 30–60 секунд** перед запуском скрипта проверки метрик, чтобы Prometheus успел собрать метрики consumer group.

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

**Когда команды не нужны:** если namespace `schema-registry` уже есть, топик `schemas-topic` и Deployment Schema Registry уже развёрнуты — повторный apply идемпотентен; `sleep 60` можно пропустить при перезапуске уже работавшего Karapace.

**Ожидание:** `sleep 60` или дольше нужен после первого запуска Karapace, чтобы успел выбраться master; иначе приложение Producer при регистрации схем может получить ошибку 503.

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

