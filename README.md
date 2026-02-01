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
kubectl apply -f kafka/kafka-jbod.yaml

# Топик (опционально)
kubectl apply -f topic/kafka-topic.yaml

# Пользователь Kafka (опционально)
kubectl apply -f user/kafka-user.yaml
```

### Metrics (examples/metrics)

```bash
# Включить метрики на Kafka-кластере
kubectl apply -f metrics/kafka-metrics.yaml

# PodMonitors и правила для Prometheus/VictoriaMetrics (namespace monitoring)
kubectl apply -f metrics/prometheus-install/pod-monitors/
```

# Импорт Дашборды Grafana — импорт JSON из examples/metrics/grafana-dashboards/ через UI Grafana
