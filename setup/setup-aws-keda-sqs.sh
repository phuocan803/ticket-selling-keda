#!/usr/bin/env bash
set -euo pipefail

export AWS_PAGER=""

required_cmds=(aws kubectl)
for cmd in "${required_cmds[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[ERROR] Missing command: $cmd" >&2
    exit 1
  fi
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
NAMESPACE="${NAMESPACE:-ticket-selling}"

AUTH_SERVICE_ACCOUNT_NAME="${AUTH_SERVICE_ACCOUNT_NAME:-auth-sa}"
CLIENT_SERVICE_ACCOUNT_NAME="${CLIENT_SERVICE_ACCOUNT_NAME:-client-sa}"
TICKETS_SERVICE_ACCOUNT_NAME="${TICKETS_SERVICE_ACCOUNT_NAME:-tickets-sa}"
ORDERS_SERVICE_ACCOUNT_NAME="${ORDERS_SERVICE_ACCOUNT_NAME:-orders-sa}"
PAYMENTS_SERVICE_ACCOUNT_NAME="${PAYMENTS_SERVICE_ACCOUNT_NAME:-payments-sa}"
EXPIRATION_SERVICE_ACCOUNT_NAME="${EXPIRATION_SERVICE_ACCOUNT_NAME:-expiration-sa}"

AUTH_QUEUE_NAME="${AUTH_QUEUE_NAME:-ticket-auth-queue}"
CLIENT_QUEUE_NAME="${CLIENT_QUEUE_NAME:-ticket-client-queue}"
TICKETS_QUEUE_NAME="${TICKETS_QUEUE_NAME:-ticket-tickets-queue}"
ORDERS_SERVICE_QUEUE_NAME="${ORDERS_SERVICE_QUEUE_NAME:-ticket-orders-service-queue}"
ORDER_QUEUE_NAME="${ORDER_QUEUE_NAME:-ticket-orders-queue}"
PAYMENT_QUEUE_NAME="${PAYMENT_QUEUE_NAME:-ticket-payments-queue}"
EXPIRATION_QUEUE_NAME="${EXPIRATION_QUEUE_NAME:-ticket-expiration-queue}"
EXPIRATION_EVENTS_QUEUE_NAME="${EXPIRATION_EVENTS_QUEUE_NAME:-ticket-expiration-events-queue}"

AUTH_IRSA_ROLE_NAME="${AUTH_IRSA_ROLE_NAME:-ticket-selling-auth-sqs-role}"
AUTH_IRSA_POLICY_NAME="${AUTH_IRSA_POLICY_NAME:-ticket-selling-auth-sqs-policy}"

CLIENT_IRSA_ROLE_NAME="${CLIENT_IRSA_ROLE_NAME:-ticket-selling-client-sqs-role}"
CLIENT_IRSA_POLICY_NAME="${CLIENT_IRSA_POLICY_NAME:-ticket-selling-client-sqs-policy}"

TICKETS_IRSA_ROLE_NAME="${TICKETS_IRSA_ROLE_NAME:-ticket-selling-tickets-sqs-role}"
TICKETS_IRSA_POLICY_NAME="${TICKETS_IRSA_POLICY_NAME:-ticket-selling-tickets-sqs-policy}"

ORDERS_IRSA_ROLE_NAME="${ORDERS_IRSA_ROLE_NAME:-ticket-selling-orders-sqs-role}"
ORDERS_IRSA_POLICY_NAME="${ORDERS_IRSA_POLICY_NAME:-ticket-selling-orders-sqs-policy}"

PAYMENTS_IRSA_ROLE_NAME="${PAYMENTS_IRSA_ROLE_NAME:-ticket-selling-payments-sqs-role}"
PAYMENTS_IRSA_POLICY_NAME="${PAYMENTS_IRSA_POLICY_NAME:-ticket-selling-payments-sqs-policy}"

EXPIRATION_IRSA_ROLE_NAME="${EXPIRATION_IRSA_ROLE_NAME:-ticket-selling-expiration-sqs-role}"
EXPIRATION_IRSA_POLICY_NAME="${EXPIRATION_IRSA_POLICY_NAME:-ticket-selling-expiration-sqs-policy}"

OUTPUT_ENV_FILE="${OUTPUT_ENV_FILE:-${ROOT_DIR}/setup/.env.eks-keda}"

if [[ -z "${CLUSTER_NAME}" ]]; then
  echo "[ERROR] CLUSTER_NAME is required" >&2
  exit 1
fi

echo "[INFO] Verifying EKS cluster ${CLUSTER_NAME} in ${AWS_REGION}"
aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null

create_queue() {
  local queue_name="$1"
  aws sqs create-queue \
    --queue-name "${queue_name}" \
    --region "${AWS_REGION}" \
    --query 'QueueUrl' \
    --output text
}

queue_arn_from_url() {
  local queue_url="$1"
  aws sqs get-queue-attributes \
    --queue-url "${queue_url}" \
    --attribute-names QueueArn \
    --region "${AWS_REGION}" \
    --query 'Attributes.QueueArn' \
    --output text
}

echo "[INFO] Creating or reusing SQS queues"
SQS_AUTH_QUEUE_URL="$(create_queue "${AUTH_QUEUE_NAME}")"
SQS_CLIENT_QUEUE_URL="$(create_queue "${CLIENT_QUEUE_NAME}")"
SQS_TICKETS_QUEUE_URL="$(create_queue "${TICKETS_QUEUE_NAME}")"
SQS_ORDERS_SERVICE_QUEUE_URL="$(create_queue "${ORDERS_SERVICE_QUEUE_NAME}")"
SQS_ORDER_EVENTS_QUEUE_URL="$(create_queue "${ORDER_QUEUE_NAME}")"
SQS_PAYMENT_EVENTS_QUEUE_URL="$(create_queue "${PAYMENT_QUEUE_NAME}")"
SQS_EXPIRATION_QUEUE_URL="$(create_queue "${EXPIRATION_QUEUE_NAME}")"
SQS_EXPIRATION_EVENTS_QUEUE_URL="$(create_queue "${EXPIRATION_EVENTS_QUEUE_NAME}")"

AUTH_QUEUE_ARN="$(queue_arn_from_url "${SQS_AUTH_QUEUE_URL}")"
CLIENT_QUEUE_ARN="$(queue_arn_from_url "${SQS_CLIENT_QUEUE_URL}")"
TICKETS_QUEUE_ARN="$(queue_arn_from_url "${SQS_TICKETS_QUEUE_URL}")"
ORDERS_SERVICE_QUEUE_ARN="$(queue_arn_from_url "${SQS_ORDERS_SERVICE_QUEUE_URL}")"
ORDER_QUEUE_ARN="$(queue_arn_from_url "${SQS_ORDER_EVENTS_QUEUE_URL}")"
PAYMENT_QUEUE_ARN="$(queue_arn_from_url "${SQS_PAYMENT_EVENTS_QUEUE_URL}")"
EXPIRATION_QUEUE_ARN="$(queue_arn_from_url "${SQS_EXPIRATION_QUEUE_URL}")"
EXPIRATION_EVENTS_QUEUE_ARN="$(queue_arn_from_url "${SQS_EXPIRATION_EVENTS_QUEUE_URL}")"

OIDC_ISSUER="$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" --query 'cluster.identity.oidc.issuer' --output text)"
OIDC_PROVIDER_HOSTPATH="${OIDC_ISSUER#https://}"

ensure_policy() {
  local policy_name="$1"
  local policy_doc_file="$2"
  local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}"

  if aws iam get-policy --policy-arn "${policy_arn}" >/dev/null 2>&1; then
    local default_version_id
    default_version_id="$(aws iam list-policy-versions \
      --policy-arn "${policy_arn}" \
      --query 'Versions[?IsDefaultVersion==`true`].VersionId' \
      --output text)"

    aws iam create-policy-version \
      --policy-arn "${policy_arn}" \
      --policy-document "file://${policy_doc_file}" \
      --set-as-default >/dev/null

    local non_default_versions
    non_default_versions="$(aws iam list-policy-versions --policy-arn "${policy_arn}" --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text)"
    if [[ -n "${non_default_versions}" ]]; then
      for version_id in ${non_default_versions}; do
        if [[ "${version_id}" != "${default_version_id}" ]]; then
          aws iam delete-policy-version --policy-arn "${policy_arn}" --version-id "${version_id}" >/dev/null 2>&1 || true
        fi
      done
    fi
  else
    aws iam create-policy \
      --policy-name "${policy_name}" \
      --policy-document "file://${policy_doc_file}" >/dev/null
  fi

  echo "${policy_arn}"
}

ensure_irsa_binding() {
  local role_name="$1"
  local policy_arn="$2"
  local service_account_name="$3"

  local trust_doc_file
  trust_doc_file="$(mktemp)"

  cat > "${trust_doc_file}" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER_HOSTPATH}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER_HOSTPATH}:aud": "sts.amazonaws.com",
          "${OIDC_PROVIDER_HOSTPATH}:sub": "system:serviceaccount:${NAMESPACE}:${service_account_name}"
        }
      }
    }
  ]
}
JSON

  if aws iam get-role --role-name "${role_name}" >/dev/null 2>&1; then
    aws iam update-assume-role-policy \
      --role-name "${role_name}" \
      --policy-document "file://${trust_doc_file}" >/dev/null
  else
    aws iam create-role \
      --role-name "${role_name}" \
      --assume-role-policy-document "file://${trust_doc_file}" >/dev/null
  fi

  aws iam attach-role-policy \
    --role-name "${role_name}" \
    --policy-arn "${policy_arn}" >/dev/null

  rm -f "${trust_doc_file}"
  echo "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${role_name}"
}

AUTH_POLICY_DOC="$(mktemp)"
CLIENT_POLICY_DOC="$(mktemp)"
TICKETS_POLICY_DOC="$(mktemp)"
ORDERS_POLICY_DOC="$(mktemp)"
PAYMENTS_POLICY_DOC="$(mktemp)"
EXPIRATION_POLICY_DOC="$(mktemp)"
cleanup() {
  rm -f "${AUTH_POLICY_DOC}" "${CLIENT_POLICY_DOC}" "${TICKETS_POLICY_DOC}" "${ORDERS_POLICY_DOC}" "${PAYMENTS_POLICY_DOC}" "${EXPIRATION_POLICY_DOC}"
}
trap cleanup EXIT

cat > "${AUTH_POLICY_DOC}" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "${AUTH_QUEUE_ARN}"
    }
  ]
}
JSON

cat > "${CLIENT_POLICY_DOC}" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "${CLIENT_QUEUE_ARN}"
    }
  ]
}
JSON

cat > "${TICKETS_POLICY_DOC}" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "${TICKETS_QUEUE_ARN}"
    }
  ]
}
JSON

cat > "${ORDERS_POLICY_DOC}" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility",
        "sqs:SendMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource": [
        "${ORDERS_SERVICE_QUEUE_ARN}",
        "${ORDER_QUEUE_ARN}",
        "${EXPIRATION_QUEUE_ARN}"
      ]
    }
  ]
}
JSON

cat > "${PAYMENTS_POLICY_DOC}" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "${ORDER_QUEUE_ARN}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sqs:SendMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource": [
        "${PAYMENT_QUEUE_ARN}"
      ]
    }
  ]
}
JSON

cat > "${EXPIRATION_POLICY_DOC}" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "${EXPIRATION_QUEUE_ARN}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sqs:SendMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource": [
        "${EXPIRATION_EVENTS_QUEUE_ARN}"
      ]
    }
  ]
}
JSON

echo "[INFO] Ensuring IAM policies for auth, client, tickets, orders, payments, expiration"
AUTH_POLICY_ARN="$(ensure_policy "${AUTH_IRSA_POLICY_NAME}" "${AUTH_POLICY_DOC}")"
CLIENT_POLICY_ARN="$(ensure_policy "${CLIENT_IRSA_POLICY_NAME}" "${CLIENT_POLICY_DOC}")"
TICKETS_POLICY_ARN="$(ensure_policy "${TICKETS_IRSA_POLICY_NAME}" "${TICKETS_POLICY_DOC}")"
ORDERS_POLICY_ARN="$(ensure_policy "${ORDERS_IRSA_POLICY_NAME}" "${ORDERS_POLICY_DOC}")"
PAYMENTS_POLICY_ARN="$(ensure_policy "${PAYMENTS_IRSA_POLICY_NAME}" "${PAYMENTS_POLICY_DOC}")"
EXPIRATION_POLICY_ARN="$(ensure_policy "${EXPIRATION_IRSA_POLICY_NAME}" "${EXPIRATION_POLICY_DOC}")"

echo "[INFO] Ensuring IAM roles for IRSA bindings"
AUTH_IRSA_ROLE_ARN="$(ensure_irsa_binding "${AUTH_IRSA_ROLE_NAME}" "${AUTH_POLICY_ARN}" "${AUTH_SERVICE_ACCOUNT_NAME}")"
CLIENT_IRSA_ROLE_ARN="$(ensure_irsa_binding "${CLIENT_IRSA_ROLE_NAME}" "${CLIENT_POLICY_ARN}" "${CLIENT_SERVICE_ACCOUNT_NAME}")"
TICKETS_IRSA_ROLE_ARN="$(ensure_irsa_binding "${TICKETS_IRSA_ROLE_NAME}" "${TICKETS_POLICY_ARN}" "${TICKETS_SERVICE_ACCOUNT_NAME}")"
ORDERS_IRSA_ROLE_ARN="$(ensure_irsa_binding "${ORDERS_IRSA_ROLE_NAME}" "${ORDERS_POLICY_ARN}" "${ORDERS_SERVICE_ACCOUNT_NAME}")"
PAYMENTS_IRSA_ROLE_ARN="$(ensure_irsa_binding "${PAYMENTS_IRSA_ROLE_NAME}" "${PAYMENTS_POLICY_ARN}" "${PAYMENTS_SERVICE_ACCOUNT_NAME}")"
EXPIRATION_IRSA_ROLE_ARN="$(ensure_irsa_binding "${EXPIRATION_IRSA_ROLE_NAME}" "${EXPIRATION_POLICY_ARN}" "${EXPIRATION_SERVICE_ACCOUNT_NAME}")"

AMP_WORKSPACE_ID="${AMP_WORKSPACE_ID:-}"
AMP_REMOTE_WRITE_ENDPOINT="${AMP_REMOTE_WRITE_ENDPOINT:-}"
REDIS_URL="${REDIS_URL:-}"
ECR_REGISTRY="${ECR_REGISTRY:-${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

AUTH_IMAGE="${AUTH_IMAGE:-${ECR_REGISTRY}/ticket-selling-auth:${IMAGE_TAG}}"
CLIENT_IMAGE="${CLIENT_IMAGE:-${ECR_REGISTRY}/ticket-selling-client:${IMAGE_TAG}}"
TICKETS_IMAGE="${TICKETS_IMAGE:-${ECR_REGISTRY}/ticket-selling-tickets:${IMAGE_TAG}}"
ORDERS_IMAGE="${ORDERS_IMAGE:-${ECR_REGISTRY}/ticket-selling-orders:${IMAGE_TAG}}"
PAYMENTS_IMAGE="${PAYMENTS_IMAGE:-${ECR_REGISTRY}/ticket-selling-payments:${IMAGE_TAG}}"
EXPIRATION_IMAGE="${EXPIRATION_IMAGE:-${ECR_REGISTRY}/ticket-selling-expiration:${IMAGE_TAG}}"

JWT_KEY="${JWT_KEY:-dev-jwt-key}"
STRIPE_KEY="${STRIPE_KEY:-sk_test_local}"

cat > "${OUTPUT_ENV_FILE}" <<ENV
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
CLUSTER_NAME=${CLUSTER_NAME}
NAMESPACE=${NAMESPACE}
REDIS_URL=${REDIS_URL}
AUTH_IMAGE=${AUTH_IMAGE}
CLIENT_IMAGE=${CLIENT_IMAGE}
TICKETS_IMAGE=${TICKETS_IMAGE}
ORDERS_IMAGE=${ORDERS_IMAGE}
PAYMENTS_IMAGE=${PAYMENTS_IMAGE}
EXPIRATION_IMAGE=${EXPIRATION_IMAGE}
SQS_AUTH_QUEUE_URL=${SQS_AUTH_QUEUE_URL}
SQS_CLIENT_QUEUE_URL=${SQS_CLIENT_QUEUE_URL}
SQS_TICKETS_QUEUE_URL=${SQS_TICKETS_QUEUE_URL}
SQS_ORDERS_SERVICE_QUEUE_URL=${SQS_ORDERS_SERVICE_QUEUE_URL}
SQS_ORDER_EVENTS_QUEUE_URL=${SQS_ORDER_EVENTS_QUEUE_URL}
SQS_PAYMENT_EVENTS_QUEUE_URL=${SQS_PAYMENT_EVENTS_QUEUE_URL}
SQS_EXPIRATION_QUEUE_URL=${SQS_EXPIRATION_QUEUE_URL}
SQS_EXPIRATION_EVENTS_QUEUE_URL=${SQS_EXPIRATION_EVENTS_QUEUE_URL}
AUTH_IRSA_ROLE_ARN=${AUTH_IRSA_ROLE_ARN}
CLIENT_IRSA_ROLE_ARN=${CLIENT_IRSA_ROLE_ARN}
TICKETS_IRSA_ROLE_ARN=${TICKETS_IRSA_ROLE_ARN}
ORDERS_IRSA_ROLE_ARN=${ORDERS_IRSA_ROLE_ARN}
PAYMENTS_IRSA_ROLE_ARN=${PAYMENTS_IRSA_ROLE_ARN}
EXPIRATION_IRSA_ROLE_ARN=${EXPIRATION_IRSA_ROLE_ARN}
AMP_WORKSPACE_ID=${AMP_WORKSPACE_ID}
AMP_REMOTE_WRITE_ENDPOINT=${AMP_REMOTE_WRITE_ENDPOINT}
ECR_REGISTRY=${ECR_REGISTRY}
JWT_KEY=${JWT_KEY}
STRIPE_KEY=${STRIPE_KEY}
ENV

echo "[DONE] AWS bootstrap complete"
echo "[INFO] Environment file: ${OUTPUT_ENV_FILE}"
echo "[INFO] Load env with: source ${OUTPUT_ENV_FILE}"
# KEDA configuration enhancements
# SQS autoscaling improvements
