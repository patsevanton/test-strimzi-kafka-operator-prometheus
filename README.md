Цель этой статьи — восполнить пробел в документации связки Strimzi Kafka и мониторинга. У Strimzi есть [раздел про метрики и Prometheus](https://strimzi.io/docs/operators/latest/deploying.html#assembly-metrics-strimzi) и примеры в репозитории ([examples/metrics/prometheus-install](https://github.com/strimzi/strimzi-kafka-operator/tree/main/examples/metrics/prometheus-install)), но они рассчитаны на общий Prometheus Operator; пошагового руководства именно под Helm-чарт **kube-prometheus-stack** (с порядком установки и нужными label’ами) в открытом доступе не нашлось. Ниже — собранный и проверенный вариант такой установки.

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

Манифесты из examples Strimzi сохранены локально в директории **strimzi/** (kafka-metrics, kafka-topic, kafka-user, PodMonitors, kube-state-metrics). Установка — через `kubectl apply -f strimzi/...`.

### Установка Strimzi

Namespace `myproject` должен существовать заранее (в примерах Strimzi по умолчанию используется именно он):

```bash
# Идемпотентно: создаёт namespace только если его ещё нет
kubectl get ns myproject 2>/dev/null || kubectl create namespace myproject
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

> **Чем отличаются манифесты от upstream Strimzi:** все PodMonitor и ServiceMonitor заранее помечены `release: kube-prometheus-stack`, `cluster-operator-metrics` сразу смотрит в namespace `strimzi`, а Service для `strimzi-kube-state-metrics` уже содержит необходимые `app.kubernetes.io/*` метки. Если использовать оригинальные yaml из [официального репозитория Strimzi](https://github.com/strimzi/strimzi-kafka-operator/tree/main/packaging/examples/metrics), добавьте эти label вручную (`release: kube-prometheus-stack` на PodMonitor/ServiceMonitor и `app.kubernetes.io/*` на Service) и поправьте `namespaceSelector.matchNames` для `cluster-operator-metrics` на `strimzi`.

### Установка Kafka из examples (локальные манифесты в strimzi/)

```bash
# Kafka-кластер (KRaft, persistent, JMX-метрики и Kafka Exporter из коробки)
kubectl apply -n myproject -f strimzi/kafka-metrics.yaml

# Топик
kubectl apply -n myproject -f strimzi/kafka-topic.yaml

# Пользователь Kafka
kubectl apply -n myproject -f strimzi/kafka-user.yaml
```

```bash
# Дождаться готовности Kafka (при первом развёртывании может занять несколько минут)
kubectl wait kafka/my-cluster -n myproject --for=condition=Ready --timeout=600s
```

### Metrics (examples/metrics)

Кластер Kafka задаётся манифестом **kafka-metrics.yaml** (ресурс `Kafka` CR Strimzi) — JMX-метрики (`metricsConfig`) и Kafka Exporter уже включены в манифест. Остаётся применить PodMonitors для сбора метрик в Prometheus.

```bash
# Сбор метрик Strimzi Cluster Operator (состояние оператора, реконсиляция)
kubectl apply -n monitoring -f strimzi/cluster-operator-metrics.yaml

# Сбор метрик Entity Operator — Topic Operator и User Operator
kubectl apply -n monitoring -f strimzi/entity-operator-metrics.yaml

# Сбор JMX-метрик с подов брокеров Kafka
kubectl apply -n monitoring -f strimzi/kafka-resources-metrics.yaml
```

**ServiceMonitor для Strimzi Kafka Exporter** (kafka-metrics.yaml включает Kafka Exporter в ресурсе Kafka). Strimzi создаёт Service `my-cluster-kafka-exporter` в myproject. Создайте ServiceMonitor, чтобы Prometheus собирал метрики топиков и consumer groups:

```bash
kubectl apply -f strimzi/kafka-exporter-servicemonitor.yaml
```

**Kube-state-metrics для Strimzi CRD** — отдельный экземпляр [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics) в режиме `--custom-resource-state-only`: он следит за **кастомными ресурсами Strimzi** (Kafka, KafkaTopic, KafkaUser, KafkaConnect, KafkaConnector и др.) и отдаёт их состояние в формате Prometheus (ready, replicas, topicId, kafka_version и т.д.). Это нужно для дашбордов и алертов по состоянию CR (например, «топик не Ready», «Kafka не на целевой версии»). Обычный kube-state-metrics из kube-prometheus-stack таких метрик по Strimzi не даёт.

- **Шаг 1 (ConfigMap):** описание, какие CRD и какие поля из них экспортировать как метрики (префиксы `strimzi_kafka_topic_*`, `strimzi_kafka_user_*`, `strimzi_kafka_*` и т.д.).
- **Шаг 2 (Deployment + RBAC + ServiceMonitor):** сам под kube-state-metrics с этим конфигом, права на list/watch Strimzi CR в кластере и ServiceMonitor, чтобы Prometheus начал скрейпить метрики.

```bash
# 1. ConfigMap с конфигом метрик по CRD Strimzi
kubectl apply -n myproject -f strimzi/kube-state-metrics-configmap.yaml

# 2. Deployment, Service, RBAC и ServiceMonitor
kubectl apply -n myproject -f strimzi/kube-state-metrics-ksm.yaml
```

## Kafka Exporter

Kafka Exporter ([danielqsj/kafka_exporter](https://github.com/danielqsj/kafka_exporter)) подключается к брокерам по Kafka API и отдаёт метрики в формате Prometheus.

**kafka-metrics.yaml** уже включает Kafka Exporter в ресурсе `Kafka` (`spec.kafkaExporter`). Strimzi развернёт его в namespace кластера. Для сбора метрик добавьте ServiceMonitor с label `release=kube-prometheus-stack`.

### Как включается Kafka Exporter

Активация — добавление блока **`spec.kafkaExporter`** в ресурс **Kafka** (CR Strimzi). Без этого блока Kafka Exporter не создаётся.

При указании `kafkaExporter` Strimzi Cluster Operator поднимает **отдельный Deployment** с подом Kafka Exporter: создаётся Deployment (например, `my-cluster-kafka-exporter`), Pod и Service `my-cluster-kafka-exporter` в namespace кластера (например, `myproject`). То есть это не «просто параметр» в поде Kafka, а отдельное приложение, которым управляет оператор.

Kafka Exporter **встроен в Strimzi** как опциональный компонент: образ и конфигурация задаются оператором, он создаёт и обновляет Deployment/Service при изменении CR. Используется проект [danielqsj/kafka_exporter](https://github.com/danielqsj/kafka_exporter), развёртыванием управляет Strimzi.

## Импорт дашбордов Grafana

Импорт JSON из `examples/metrics/grafana-dashboards/` через UI Grafana:

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-kafka-exporter.json

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-kafka.json

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-kraft.json

https://github.com/strimzi/strimzi-kafka-operator/blob/main/packaging/examples/metrics/grafana-dashboards/strimzi-operators.json

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

