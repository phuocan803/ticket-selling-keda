#!/usr/bin/env bash
set -euo pipefail

export AWS_PAGER=""

required_cmds=(aws kubectl helm)
for cmd in "${required_cmds[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[ERROR] Missing command: $cmd" >&2
    exit 1
  fi
done

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}"
SQS_AUTH_QUEUE_URL="${SQS_AUTH_QUEUE_URL:-}"
SQS_CLIENT_QUEUE_URL="${SQS_CLIENT_QUEUE_URL:-}"
SQS_TICKETS_QUEUE_URL="${SQS_TICKETS_QUEUE_URL:-}"
SQS_ORDERS_SERVICE_QUEUE_URL="${SQS_ORDERS_SERVICE_QUEUE_URL:-}"
SQS_ORDER_EVENTS_QUEUE_URL="${SQS_ORDER_EVENTS_QUEUE_URL:-}"
SQS_PAYMENT_EVENTS_QUEUE_URL="${SQS_PAYMENT_EVENTS_QUEUE_URL:-}"
SQS_EXPIRATION_QUEUE_URL="${SQS_EXPIRATION_QUEUE_URL:-}"
SQS_EXPIRATION_EVENTS_QUEUE_URL="${SQS_EXPIRATION_EVENTS_QUEUE_URL:-}"
AUTH_IRSA_ROLE_ARN="${AUTH_IRSA_ROLE_ARN:-}"
CLIENT_IRSA_ROLE_ARN="${CLIENT_IRSA_ROLE_ARN:-}"
TICKETS_IRSA_ROLE_ARN="${TICKETS_IRSA_ROLE_ARN:-}"
PAYMENTS_IRSA_ROLE_ARN="${PAYMENTS_IRSA_ROLE_ARN:-}"
ORDERS_IRSA_ROLE_ARN="${ORDERS_IRSA_ROLE_ARN:-}"
EXPIRATION_IRSA_ROLE_ARN="${EXPIRATION_IRSA_ROLE_ARN:-}"
ENABLE_AMP_SCALER="${ENABLE_AMP_SCALER:-false}"
AMP_WORKSPACE_ID="${AMP_WORKSPACE_ID:-}"
AMP_REMOTE_WRITE_ENDPOINT="${AMP_REMOTE_WRITE_ENDPOINT:-}"

if [[ -z "$CLUSTER_NAME" ]]; then
  echo "[ERROR] CLUSTER_NAME is required" >&2
  exit 1
fi
if [[ -z "$AWS_ACCOUNT_ID" ]]; then
  echo "[ERROR] AWS_ACCOUNT_ID is required" >&2
  exit 1
fi

for q in SQS_AUTH_QUEUE_URL SQS_CLIENT_QUEUE_URL SQS_TICKETS_QUEUE_URL SQS_ORDERS_SERVICE_QUEUE_URL SQS_ORDER_EVENTS_QUEUE_URL SQS_PAYMENT_EVENTS_QUEUE_URL SQS_EXPIRATION_QUEUE_URL SQS_EXPIRATION_EVENTS_QUEUE_URL; do
  if [[ -z "${!q}" ]]; then
    echo "[ERROR] ${q} is required" >&2
    exit 1
  fi
done

if [[ -z "$AUTH_IRSA_ROLE_ARN" ]]; then
  echo "[ERROR] AUTH_IRSA_ROLE_ARN is required" >&2
  exit 1
fi
if [[ -z "$CLIENT_IRSA_ROLE_ARN" ]]; then
  echo "[ERROR] CLIENT_IRSA_ROLE_ARN is required" >&2
  exit 1
fi
if [[ -z "$TICKETS_IRSA_ROLE_ARN" ]]; then
  echo "[ERROR] TICKETS_IRSA_ROLE_ARN is required" >&2
  exit 1
fi
if [[ -z "$PAYMENTS_IRSA_ROLE_ARN" ]]; then
  echo "[ERROR] PAYMENTS_IRSA_ROLE_ARN is required" >&2
  exit 1
fi
if [[ -z "$ORDERS_IRSA_ROLE_ARN" ]]; then
  echo "[ERROR] ORDERS_IRSA_ROLE_ARN is required" >&2
  exit 1
fi
if [[ -z "$EXPIRATION_IRSA_ROLE_ARN" ]]; then
  echo "[ERROR] EXPIRATION_IRSA_ROLE_ARN is required" >&2
  exit 1
fi

echo "[INFO] AWS caller identity"
aws sts get-caller-identity >/dev/null

echo "[INFO] Checking EKS cluster ${CLUSTER_NAME} in ${AWS_REGION}"
aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null

echo "[INFO] Checking queue attributes"
aws sqs get-queue-attributes --queue-url "$SQS_AUTH_QUEUE_URL" --attribute-names QueueArn >/dev/null
aws sqs get-queue-attributes --queue-url "$SQS_CLIENT_QUEUE_URL" --attribute-names QueueArn >/dev/null
aws sqs get-queue-attributes --queue-url "$SQS_TICKETS_QUEUE_URL" --attribute-names QueueArn >/dev/null
aws sqs get-queue-attributes --queue-url "$SQS_ORDERS_SERVICE_QUEUE_URL" --attribute-names QueueArn >/dev/null
aws sqs get-queue-attributes --queue-url "$SQS_ORDER_EVENTS_QUEUE_URL" --attribute-names QueueArn >/dev/null
aws sqs get-queue-attributes --queue-url "$SQS_PAYMENT_EVENTS_QUEUE_URL" --attribute-names QueueArn >/dev/null
aws sqs get-queue-attributes --queue-url "$SQS_EXPIRATION_QUEUE_URL" --attribute-names QueueArn >/dev/null
aws sqs get-queue-attributes --queue-url "$SQS_EXPIRATION_EVENTS_QUEUE_URL" --attribute-names QueueArn >/dev/null

echo "[INFO] Checking IRSA roles"
aws iam get-role --role-name "${AUTH_IRSA_ROLE_ARN##*/}" >/dev/null
aws iam get-role --role-name "${CLIENT_IRSA_ROLE_ARN##*/}" >/dev/null
aws iam get-role --role-name "${TICKETS_IRSA_ROLE_ARN##*/}" >/dev/null
aws iam get-role --role-name "${ORDERS_IRSA_ROLE_ARN##*/}" >/dev/null
aws iam get-role --role-name "${PAYMENTS_IRSA_ROLE_ARN##*/}" >/dev/null
aws iam get-role --role-name "${EXPIRATION_IRSA_ROLE_ARN##*/}" >/dev/null

echo "[INFO] Verifying current kubectl context"
kubectl config current-context >/dev/null

if [[ "${ENABLE_AMP_SCALER}" == "true" ]]; then
  if [[ -z "${AMP_WORKSPACE_ID}" ]]; then
    echo "[ERROR] AMP_WORKSPACE_ID is required when ENABLE_AMP_SCALER=true" >&2
    exit 1
  fi
  if [[ -z "${AMP_REMOTE_WRITE_ENDPOINT}" ]]; then
    echo "[ERROR] AMP_REMOTE_WRITE_ENDPOINT is required when ENABLE_AMP_SCALER=true" >&2
    exit 1
  fi

  echo "[INFO] Checking AMP workspace ${AMP_WORKSPACE_ID}"
  aws amp describe-workspace --workspace-id "${AMP_WORKSPACE_ID}" --region "${AWS_REGION}" >/dev/null
fi

echo "[DONE] AWS preflight checks passed"
