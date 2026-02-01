# Kafka Producer Helm Chart

Helm чарт для развертывания Go приложения в режиме producer (отправка данных в Kafka).

## Установка

```bash
helm install kafka-producer ./helm/kafka-producer \
  --namespace myproject \
  --create-namespace \
  -f helm/kafka-producer/values.yaml
```

## Настройка

Основные параметры в `values.yaml`:

### Kafka настройки
- `kafka.brokers` - список брокеров Kafka (через запятую)
- `kafka.topic` - название топика
- `kafka.username` - имя пользователя для SASL/SCRAM (опционально)
- `kafka.password` - пароль для SASL/SCRAM (опционально)

### Schema Registry
- `schemaRegistry.url` - URL Schema Registry API (Karapace/Confluent-compatible)

### Безопасность

Для использования секретов вместо plain text паролей (рекомендуется):

```yaml
secrets:
  create: true
  username: "my-user"
  password: "mypassword"
```

Также можно использовать **уже существующий** secret в namespace релиза:
```bash
helm upgrade --install kafka-producer ./helm/kafka-producer \
  --namespace myproject \
  --set secrets.name=kafka-app-credentials
```

### Пример values.yaml для Strimzi

```yaml
replicaCount: 1

image:
  repository: kafka-app
  tag: "latest"

kafka:
  brokers: "my-cluster-kafka-bootstrap.myproject.svc.cluster.local:9092"
  topic: "my-topic"
  username: "my-user"
  password: "mypassword"

schemaRegistry:
  url: "http://schema-registry.schema-registry:8081"

secrets:
  create: true
  username: "my-user"
  password: "mypassword"
```

## Обновление

```bash
helm upgrade kafka-producer ./helm/kafka-producer \
  --namespace myproject \
  -f helm/kafka-producer/values.yaml
```

## Удаление

```bash
helm uninstall kafka-producer --namespace myproject
```
