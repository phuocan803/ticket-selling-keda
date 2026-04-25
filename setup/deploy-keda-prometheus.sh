#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
KEDA_DIR="${ROOT_DIR}/keda"
PROM_SCALER_FILES=(
  "${KEDA_DIR}/client-prometheus-scaledobject.yaml"
  "${KEDA_DIR}/auth-prometheus-scaledobject.yaml"
  "${KEDA_DIR}/orders-prometheus-scaledobject.yaml"
  "${KEDA_DIR}/tickets-prometheus-scaledobject.yaml"
  "${KEDA_DIR}/payments-scaledobject.yaml"
  "${KEDA_DIR}/expiration-scaledobject.yaml"
)

escape_sed() {
  printf '%s' "$1" | sed 's/[\\&|]/\\\\&/g'
}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[ERROR] kubectl is required" >&2
  exit 1
fi

for scaler_file in "${PROM_SCALER_FILES[@]}"; do
  if [[ ! -f "${scaler_file}" ]]; then
    echo "[ERROR] Prometheus scaler manifest not found: ${scaler_file}" >&2
    exit 1
  fi
done

required_envs=(AMP_WORKSPACE_ID AWS_REGION SQS_AUTH_QUEUE_URL SQS_CLIENT_QUEUE_URL SQS_TICKETS_QUEUE_URL SQS_ORDERS_SERVICE_QUEUE_URL SQS_ORDER_EVENTS_QUEUE_URL SQS_EXPIRATION_QUEUE_URL)
for env_name in "${required_envs[@]}"; do
  if [[ -z "${!env_name:-}" ]]; then
    echo "[ERROR] ${env_name} is required" >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "[INFO] Removing SQS-only scalers before applying dual scalers"
kubectl -n ticket-selling delete scaledobject auth-sqs-scaler --ignore-not-found
kubectl -n ticket-selling delete scaledobject client-sqs-scaler --ignore-not-found
kubectl -n ticket-selling delete scaledobject tickets-sqs-scaler --ignore-not-found
kubectl -n ticket-selling delete scaledobject orders-sqs-scaler --ignore-not-found
kubectl -n ticket-selling delete scaledobject payments-sqs-scaler --ignore-not-found
kubectl -n ticket-selling delete scaledobject expiration-sqs-scaler --ignore-not-found

for scaler_file in "${PROM_SCALER_FILES[@]}"; do
  tmp_file="${TMP_DIR}/$(basename "${scaler_file}")"
  sed \
    -e "s|__AMP_WORKSPACE_ID__|$(escape_sed "${AMP_WORKSPACE_ID}")|g" \
    -e "s|__AWS_REGION__|$(escape_sed "${AWS_REGION}")|g" \
    -e "s|__SQS_AUTH_QUEUE_URL__|$(escape_sed "${SQS_AUTH_QUEUE_URL}")|g" \
    -e "s|__SQS_CLIENT_QUEUE_URL__|$(escape_sed "${SQS_CLIENT_QUEUE_URL}")|g" \
    -e "s|__SQS_TICKETS_QUEUE_URL__|$(escape_sed "${SQS_TICKETS_QUEUE_URL}")|g" \
    -e "s|__SQS_ORDERS_SERVICE_QUEUE_URL__|$(escape_sed "${SQS_ORDERS_SERVICE_QUEUE_URL}")|g" \
    -e "s|__SQS_ORDER_EVENTS_QUEUE_URL__|$(escape_sed "${SQS_ORDER_EVENTS_QUEUE_URL}")|g" \
    -e "s|__SQS_EXPIRATION_QUEUE_URL__|$(escape_sed "${SQS_EXPIRATION_QUEUE_URL}")|g" \
    "${scaler_file}" > "${tmp_file}"

  echo "[INFO] Applying $(basename "${scaler_file}")"
  kubectl apply -f "${tmp_file}"
done

echo "[INFO] Current scaledobjects"
kubectl get scaledobject -n ticket-selling

echo "[DONE] KEDA Prometheus scaler applied"
