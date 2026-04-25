#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFESTS_DIR="${ROOT_DIR}/manifests"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

required_envs=(
  AWS_REGION
  REDIS_URL
  AUTH_IMAGE
  CLIENT_IMAGE
  TICKETS_IMAGE
  ORDERS_IMAGE
  PAYMENTS_IMAGE
  EXPIRATION_IMAGE
  AUTH_IRSA_ROLE_ARN
  CLIENT_IRSA_ROLE_ARN
  TICKETS_IRSA_ROLE_ARN
  ORDERS_IRSA_ROLE_ARN
  PAYMENTS_IRSA_ROLE_ARN
  EXPIRATION_IRSA_ROLE_ARN
  SQS_AUTH_QUEUE_URL
  SQS_CLIENT_QUEUE_URL
  SQS_TICKETS_QUEUE_URL
  SQS_ORDERS_SERVICE_QUEUE_URL
  SQS_ORDER_EVENTS_QUEUE_URL
  SQS_PAYMENT_EVENTS_QUEUE_URL
  SQS_EXPIRATION_QUEUE_URL
  SQS_EXPIRATION_EVENTS_QUEUE_URL
  JWT_KEY
  STRIPE_KEY
)

for env_name in "${required_envs[@]}"; do
  if [[ -z "${!env_name:-}" ]]; then
    echo "[ERROR] ${env_name} is required" >&2
    exit 1
  fi
done

escape_sed() {
  printf '%s' "$1" | sed 's/[\\&|]/\\\\&/g'
}

render_file() {
  local source_file="$1"
  local target_file="$2"

  sed \
    -e "s|__AWS_REGION__|$(escape_sed "${AWS_REGION}")|g" \
    -e "s|__REDIS_URL__|$(escape_sed "${REDIS_URL}")|g" \
    -e "s|__AUTH_IMAGE__|$(escape_sed "${AUTH_IMAGE}")|g" \
    -e "s|__CLIENT_IMAGE__|$(escape_sed "${CLIENT_IMAGE}")|g" \
    -e "s|__TICKETS_IMAGE__|$(escape_sed "${TICKETS_IMAGE}")|g" \
    -e "s|__ORDERS_IMAGE__|$(escape_sed "${ORDERS_IMAGE}")|g" \
    -e "s|__PAYMENTS_IMAGE__|$(escape_sed "${PAYMENTS_IMAGE}")|g" \
    -e "s|__EXPIRATION_IMAGE__|$(escape_sed "${EXPIRATION_IMAGE}")|g" \
    -e "s|__AUTH_IRSA_ROLE_ARN__|$(escape_sed "${AUTH_IRSA_ROLE_ARN}")|g" \
    -e "s|__CLIENT_IRSA_ROLE_ARN__|$(escape_sed "${CLIENT_IRSA_ROLE_ARN}")|g" \
    -e "s|__TICKETS_IRSA_ROLE_ARN__|$(escape_sed "${TICKETS_IRSA_ROLE_ARN}")|g" \
    -e "s|__ORDERS_IRSA_ROLE_ARN__|$(escape_sed "${ORDERS_IRSA_ROLE_ARN}")|g" \
    -e "s|__PAYMENTS_IRSA_ROLE_ARN__|$(escape_sed "${PAYMENTS_IRSA_ROLE_ARN}")|g" \
    -e "s|__EXPIRATION_IRSA_ROLE_ARN__|$(escape_sed "${EXPIRATION_IRSA_ROLE_ARN}")|g" \
    -e "s|__SQS_AUTH_QUEUE_URL__|$(escape_sed "${SQS_AUTH_QUEUE_URL}")|g" \
    -e "s|__SQS_CLIENT_QUEUE_URL__|$(escape_sed "${SQS_CLIENT_QUEUE_URL}")|g" \
    -e "s|__SQS_TICKETS_QUEUE_URL__|$(escape_sed "${SQS_TICKETS_QUEUE_URL}")|g" \
    -e "s|__SQS_ORDERS_SERVICE_QUEUE_URL__|$(escape_sed "${SQS_ORDERS_SERVICE_QUEUE_URL}")|g" \
    -e "s|__SQS_ORDER_EVENTS_QUEUE_URL__|$(escape_sed "${SQS_ORDER_EVENTS_QUEUE_URL}")|g" \
    -e "s|__SQS_PAYMENT_EVENTS_QUEUE_URL__|$(escape_sed "${SQS_PAYMENT_EVENTS_QUEUE_URL}")|g" \
    -e "s|__SQS_EXPIRATION_QUEUE_URL__|$(escape_sed "${SQS_EXPIRATION_QUEUE_URL}")|g" \
    -e "s|__SQS_EXPIRATION_EVENTS_QUEUE_URL__|$(escape_sed "${SQS_EXPIRATION_EVENTS_QUEUE_URL}")|g" \
    -e "s|__JWT_KEY__|$(escape_sed "${JWT_KEY}")|g" \
    -e "s|__STRIPE_KEY__|$(escape_sed "${STRIPE_KEY}")|g" \
    "${source_file}" > "${target_file}"
}

apply_manifest() {
  local file_name="$1"
  local rendered_file="${TMP_DIR}/${file_name}"
  render_file "${MANIFESTS_DIR}/${file_name}" "${rendered_file}"
  echo "[INFO] Applying ${file_name}"
  kubectl apply -f "${rendered_file}"
}

apply_manifest "00-namespace.yaml"
apply_manifest "15-serviceaccounts.yaml"
apply_manifest "10-configmap-eks.yaml"
apply_manifest "12-secret-eks.yaml"
apply_manifest "20-deployments.yaml"
apply_manifest "30-services.yaml"
apply_manifest "40-ingress.yaml"

echo "[DONE] Ticket Selling application deployed"