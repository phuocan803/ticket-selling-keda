#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-ticket-selling}"
TARGET_DEPLOYMENTS=(auth tickets orders payments expiration client)
AWS_REGION="${AWS_REGION:-us-east-1}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[ERROR] kubectl is required" >&2
  exit 1
fi

echo "[INFO] ScaledObject status"
kubectl -n "${NAMESPACE}" get scaledobject -o wide

echo "[INFO] HPA status"
kubectl -n "${NAMESPACE}" get hpa -o wide

echo "[INFO] Target deployment replicas"
for deployment in "${TARGET_DEPLOYMENTS[@]}"; do
  kubectl -n "${NAMESPACE}" get deploy "${deployment}" \
    -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,DESIRED:.spec.replicas,AVAILABLE:.status.availableReplicas || true
done

echo "[INFO] Current pod counts"
for deployment in "${TARGET_DEPLOYMENTS[@]}"; do
  count="$(kubectl -n "${NAMESPACE}" get pods -l app="${deployment}" --no-headers 2>/dev/null | wc -l || true)"
  echo "- ${deployment}: ${count}"
done

if command -v aws >/dev/null 2>&1; then
  declare -A sqs_queues=(
    ["auth"]="${SQS_AUTH_QUEUE_URL:-}"
    ["client"]="${SQS_CLIENT_QUEUE_URL:-}"
    ["tickets"]="${SQS_TICKETS_QUEUE_URL:-}"
    ["orders-service"]="${SQS_ORDERS_SERVICE_QUEUE_URL:-}"
    ["orders"]="${SQS_ORDER_EVENTS_QUEUE_URL:-}"
    ["payments"]="${SQS_PAYMENT_EVENTS_QUEUE_URL:-}"
    ["expiration"]="${SQS_EXPIRATION_QUEUE_URL:-}"
    ["expiration-events"]="${SQS_EXPIRATION_EVENTS_QUEUE_URL:-}"
  )

  for queue_name in "${!sqs_queues[@]}"; do
    queue_url="${sqs_queues[${queue_name}]}"
    if [[ -n "${queue_url}" ]]; then
      echo "[INFO] SQS approximate queue depth (${queue_name})"
      aws sqs get-queue-attributes \
        --queue-url "${queue_url}" \
        --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
        --region "${AWS_REGION}" \
        --query 'Attributes' \
        --output table
    else
      echo "[WARN] Skipping ${queue_name} queue depth check (${queue_name} queue URL is not set)"
    fi
  done
else
  echo "[WARN] Skipping all SQS queue depth checks (aws CLI missing)"
fi

echo "[DONE] Verification completed"
