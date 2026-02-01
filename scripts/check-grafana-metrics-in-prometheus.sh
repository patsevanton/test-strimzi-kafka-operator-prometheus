#!/bin/bash
# Проверка наличия метрик из JSON-дашбордов Grafana Strimzi в Prometheus
# Использование:
#   # Из пода в кластере (или с port-forward):
#   kubectl exec -it deploy/kube-prometheus-stack-prometheus -n monitoring -- sh -c 'apk add curl 2>/dev/null; ./check-grafana-metrics-in-prometheus.sh'
#   # С port-forward (в отдельном терминале: kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090):
#   PROM_URL=http://localhost:9090/api/v1/query ./check-grafana-metrics-in-prometheus.sh

set -e

PROM_URL="${PROM_URL:-http://localhost:9090/api/v1/query}"
if [[ "$PROM_URL" != */api/v1/query ]]; then
  PROM_URL="${PROM_URL%/}/api/v1/query"
fi

# Метрики из strimzi-kafka-exporter.json
KAFKA_EXPORTER_METRICS=(
  kafka_topic_partitions
  kafka_topic_partition_replicas
  kafka_topic_partition_in_sync_replica
  kafka_topic_partition_under_replicated_partition
  kafka_cluster_partition_atminisr
  kafka_cluster_partition_underminisr
  kafka_topic_partition_leader_is_preferred
  kafka_topic_partition_current_offset
  kafka_consumergroup_current_offset
  kafka_consumergroup_lag
  kafka_topic_partition_oldest_offset
  kafka_broker_info
)

# Метрики из strimzi-kafka.json
STRIMZI_KAFKA_METRICS=(
  kafka_server_replicamanager_leadercount
  kafka_controller_kafkacontroller_activecontrollercount
  kafka_controller_controllerstats_uncleanleaderelections_total
  kafka_server_replicamanager_partitioncount
  kafka_server_replicamanager_underreplicatedpartitions
  kafka_cluster_partition_atminisr
  kafka_cluster_partition_underminisr
  kafka_controller_kafkacontroller_offlinepartitionscount
  container_memory_usage_bytes
  container_cpu_usage_seconds_total
  kubelet_volume_stats_available_bytes
  process_open_fds
  jvm_memory_used_bytes
  jvm_gc_collection_seconds_sum
  jvm_gc_collection_seconds_count
  jvm_threads_current
  kafka_server_brokertopicmetrics_bytesin_total
  kafka_server_brokertopicmetrics_bytesout_total
  kafka_server_brokertopicmetrics_messagesin_total
  kafka_server_brokertopicmetrics_totalproducerequests_total
  kafka_server_brokertopicmetrics_failedproducerequests_total
  kafka_server_brokertopicmetrics_totalfetchrequests_total
  kafka_server_brokertopicmetrics_failedfetchrequests_total
  kafka_network_socketserver_networkprocessoravgidle_percent
  kafka_server_kafkarequesthandlerpool_requesthandleravgidle_percent
  kafka_server_kafkaserver_linux_disk_write_bytes
  kafka_server_kafkaserver_linux_disk_read_bytes
  kafka_server_socket_server_metrics_connection_count
  kafka_log_log_size
  kafka_cluster_partition_replicascount
)

# Метрики из strimzi-kraft.json
STRIMZI_KRAFT_METRICS=(
  container_memory_usage_bytes
  container_cpu_usage_seconds_total
  kubelet_volume_stats_available_bytes
  process_open_fds
  jvm_memory_used_bytes
  jvm_gc_collection_seconds_sum
  jvm_gc_collection_seconds_count
  jvm_threads_current
  kafka_server_raftmetrics_append_records_rate
  kafka_server_raftmetrics_fetch_records_rate
  kafka_server_raftmetrics_commit_latency_avg
  kafka_server_raftmetrics_current_state
  kafka_server_raftmetrics_current_leader
  kafka_server_raftmetrics_current_vote
  kafka_server_raftmetrics_current_epoch
  kafka_server_raftchannelmetrics_incoming_byte_total
  kafka_server_raftchannelmetrics_outgoing_byte_total
  kafka_server_raftchannelmetrics_request_total
  kafka_server_raftchannelmetrics_response_total
  kafka_server_raftmetrics_high_watermark
  kafka_server_raftmetrics_log_end_offset
)

# Метрики из strimzi-operators.json
STRIMZI_OPERATORS_METRICS=(
  strimzi_resources
  strimzi_reconciliations_successful_total
  strimzi_reconciliations_failed_total
  strimzi_reconciliations_locked_total
  strimzi_reconciliations_total
  strimzi_reconciliations_periodical_total
  strimzi_reconciliations_duration_seconds_max
  strimzi_certificate_expiration_timestamp_ms
  jvm_memory_used_bytes
  jvm_gc_pause_seconds_sum
  jvm_gc_pause_seconds_count
)

check_metric() {
  local m="$1"
  local r
  r=$(curl -sG "$PROM_URL" --data-urlencode "query=$m" 2>/dev/null) || { echo "нет (ошибка запроса)"; return; }
  if echo "$r" | grep -q '"result":\[\]'; then
    echo "нет"
  elif echo "$r" | grep -q '"result":\['; then
    echo "есть"
  else
    echo "?"
  fi
}

print_section() {
  local title="$1"
  shift
  local metrics=("$@")
  echo ""
  echo "=== $title ==="
  local has=0 no=0
  for m in "${metrics[@]}"; do
    status=$(check_metric "$m")
    printf "  %-55s %s\n" "$m" "$status"
    case "$status" in
      есть) ((has++)) ;;
      нет)  ((no++)) ;;
    esac
  done
  echo "  ---"
  echo "  Итого: есть=$has, нет=$no"
}

echo "Проверка метрик Grafana дашбордов Strimzi в Prometheus"
echo "URL: $PROM_URL"
echo ""

print_section "Kafka Exporter (strimzi-kafka-exporter.json)" "${KAFKA_EXPORTER_METRICS[@]}"
print_section "Strimzi Kafka (strimzi-kafka.json)" "${STRIMZI_KAFKA_METRICS[@]}"
print_section "Strimzi KRaft (strimzi-kraft.json)" "${STRIMZI_KRAFT_METRICS[@]}"

# Strimzi Operators
print_section "Strimzi Operators (strimzi-operators.json)" "${STRIMZI_OPERATORS_METRICS[@]}"

echo ""
echo "Проверка завершена."
