#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
KEDA_DIR="${ROOT_DIR}/keda"
KEDA_FILES=(
  "${KEDA_DIR}/auth-sqs-scaledobject.yaml"
  "${KEDA_DIR}/client-sqs-scaledobject.yaml"
  "${KEDA_DIR}/tickets-sqs-scaledobject.yaml"
  "${KEDA_DIR}/orders-sqs-scaledobject.yaml"
  "${KEDA_DIR}/payments-sqs-scaledobject.yaml"
  "${KEDA_DIR}/expiration-sqs-scaledobject.yaml"
)

escape_sed() {
  printf '%s' "$1" | sed 's/[\\&|]/\\\\&/g'
}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[ERROR] kubectl is required" >&2
  exit 1
fi

for keda_file in "${KEDA_FILES[@]}"; do
  if [[ ! -f "${keda_file}" ]]; then
    echo "[ERROR] KEDA manifest not found: ${keda_file}" >&2
    exit 1
  fi
done

required_envs=(AWS_REGION SQS_AUTH_QUEUE_URL SQS_CLIENT_QUEUE_URL SQS_TICKETS_QUEUE_URL SQS_ORDERS_SERVICE_QUEUE_URL SQS_ORDER_EVENTS_QUEUE_URL SQS_EXPIRATION_QUEUE_URL)
for env_name in "${required_envs[@]}"; do
  if [[ -z "${!env_name:-}" ]]; then
    echo "[ERROR] ${env_name} is required" >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

for keda_file in "${KEDA_FILES[@]}"; do
  tmp_keda_file="${TMP_DIR}/$(basename "${keda_file}")"
  sed \
    -e "s|__AWS_REGION__|$(escape_sed "${AWS_REGION}")|g" \
    -e "s|__SQS_AUTH_QUEUE_URL__|$(escape_sed "${SQS_AUTH_QUEUE_URL}")|g" \
    -e "s|__SQS_CLIENT_QUEUE_URL__|$(escape_sed "${SQS_CLIENT_QUEUE_URL}")|g" \
    -e "s|__SQS_TICKETS_QUEUE_URL__|$(escape_sed "${SQS_TICKETS_QUEUE_URL}")|g" \
    -e "s|__SQS_ORDERS_SERVICE_QUEUE_URL__|$(escape_sed "${SQS_ORDERS_SERVICE_QUEUE_URL}")|g" \
    -e "s|__SQS_ORDER_EVENTS_QUEUE_URL__|$(escape_sed "${SQS_ORDER_EVENTS_QUEUE_URL}")|g" \
    -e "s|__SQS_EXPIRATION_QUEUE_URL__|$(escape_sed "${SQS_EXPIRATION_QUEUE_URL}")|g" \
    "${keda_file}" > "${tmp_keda_file}"

  echo "[INFO] Applying $(basename "${keda_file}")"
  kubectl apply -f "${tmp_keda_file}"
done

echo "[INFO] Applied all KEDA SQS manifests"

echo "[INFO] Current scaledobjects"
kubectl get scaledobject -n ticket-selling

echo "[INFO] Current HPAs"
kubectl get hpa -n ticket-selling

echo "[DONE] KEDA SQS deployment applied"
