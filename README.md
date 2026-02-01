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

# Импорт Дашборды Grafana — импорт JSON из examples/metrics/grafana-dashboards/ через UI Grafana
