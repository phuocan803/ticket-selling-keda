#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MONITORING_DIR="${ROOT_DIR}/monitoring"

AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)}"
CLUSTER_NAME="${CLUSTER_NAME:-}"
AMP_WORKSPACE_ID="${AMP_WORKSPACE_ID:-}"
KEDA_NAMESPACE="${KEDA_NAMESPACE:-keda}"
KEDA_SERVICE_ACCOUNT_NAME="${KEDA_SERVICE_ACCOUNT_NAME:-keda-operator}"
KEDA_AMP_ROLE_NAME="${KEDA_AMP_ROLE_NAME:-ticket-selling-keda-amp-role}"
KEDA_AMP_POLICY_NAME="${KEDA_AMP_POLICY_NAME:-ticket-selling-keda-amp-policy}"
ADOT_NAMESPACE="${ADOT_NAMESPACE:-adot}"
ADOT_SERVICE_ACCOUNT_NAME="${ADOT_SERVICE_ACCOUNT_NAME:-adot-collector}"
ADOT_AMP_ROLE_NAME="${ADOT_AMP_ROLE_NAME:-ticket-selling-adot-amp-role}"
ADOT_AMP_POLICY_NAME="${ADOT_AMP_POLICY_NAME:-ticket-selling-adot-amp-policy}"
PAYMENTS_IRSA_ROLE_ARN="${PAYMENTS_IRSA_ROLE_ARN:-}"
EXPIRATION_IRSA_ROLE_ARN="${EXPIRATION_IRSA_ROLE_ARN:-}"
CONFIGURE_AWS_IAM="${CONFIGURE_AWS_IAM:-true}"

escape_sed() {
  printf '%s' "$1" | sed 's/[\\&|]/\\\\&/g'
}

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

ensure_irsa_role() {
  local role_name="$1"
  local policy_arn="$2"
  local namespace="$3"
  local service_account_name="$4"

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
          "${OIDC_PROVIDER_HOSTPATH}:sub": "system:serviceaccount:${namespace}:${service_account_name}"
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

update_sqs_role_trust() {
  local role_arn="$1"
  local service_account_subject="$2"
  local role_name="${role_arn##*/}"
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
          "${OIDC_PROVIDER_HOSTPATH}:sub": "${service_account_subject}"
        }
      }
    },
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${KEDA_AMP_ROLE_NAME}"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON

  aws iam update-assume-role-policy \
    --role-name "${role_name}" \
    --policy-document "file://${trust_doc_file}" >/dev/null

  rm -f "${trust_doc_file}"
}

configure_aws_iam() {
  local amp_workspace_arn="arn:aws:aps:${AWS_REGION}:${AWS_ACCOUNT_ID}:workspace/${AMP_WORKSPACE_ID}"
  OIDC_ISSUER="$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" --query 'cluster.identity.oidc.issuer' --output text)"
  OIDC_PROVIDER_HOSTPATH="${OIDC_ISSUER#https://}"

  local keda_policy_doc adot_policy_doc
  keda_policy_doc="$(mktemp)"
  adot_policy_doc="$(mktemp)"
  trap 'rm -f "${keda_policy_doc}" "${adot_policy_doc}"' RETURN

  cat > "${keda_policy_doc}" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "aps:QueryMetrics",
        "aps:GetSeries",
        "aps:GetLabels",
        "aps:GetMetricMetadata"
      ],
      "Resource": "${amp_workspace_arn}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sts:AssumeRole"
      ],
      "Resource": [
        "${PAYMENTS_IRSA_ROLE_ARN}",
        "${EXPIRATION_IRSA_ROLE_ARN}"
      ]
    }
  ]
}
JSON

  cat > "${adot_policy_doc}" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "aps:RemoteWrite"
      ],
      "Resource": "${amp_workspace_arn}"
    }
  ]
}
JSON

  local keda_policy_arn adot_policy_arn keda_role_arn adot_role_arn
  keda_policy_arn="$(ensure_policy "${KEDA_AMP_POLICY_NAME}" "${keda_policy_doc}")"
  adot_policy_arn="$(ensure_policy "${ADOT_AMP_POLICY_NAME}" "${adot_policy_doc}")"
  keda_role_arn="$(ensure_irsa_role "${KEDA_AMP_ROLE_NAME}" "${keda_policy_arn}" "${KEDA_NAMESPACE}" "${KEDA_SERVICE_ACCOUNT_NAME}")"
  adot_role_arn="$(ensure_irsa_role "${ADOT_AMP_ROLE_NAME}" "${adot_policy_arn}" "${ADOT_NAMESPACE}" "${ADOT_SERVICE_ACCOUNT_NAME}")"

  if [[ -n "${PAYMENTS_IRSA_ROLE_ARN}" ]]; then
    update_sqs_role_trust "${PAYMENTS_IRSA_ROLE_ARN}" "system:serviceaccount:ticket-selling:payments-sa"
  fi

  if [[ -n "${EXPIRATION_IRSA_ROLE_ARN}" ]]; then
    update_sqs_role_trust "${EXPIRATION_IRSA_ROLE_ARN}" "system:serviceaccount:ticket-selling:expiration-sa"
  fi

  kubectl annotate serviceaccount "${KEDA_SERVICE_ACCOUNT_NAME}" -n "${KEDA_NAMESPACE}" \
    eks.amazonaws.com/role-arn="${keda_role_arn}" --overwrite
  kubectl annotate serviceaccount "${ADOT_SERVICE_ACCOUNT_NAME}" -n "${ADOT_NAMESPACE}" \
    eks.amazonaws.com/role-arn="${adot_role_arn}" --overwrite

  kubectl rollout restart deployment/keda-operator -n "${KEDA_NAMESPACE}"
  kubectl rollout restart daemonset/adot-collector -n "${ADOT_NAMESPACE}"
  kubectl rollout status deployment/keda-operator -n "${KEDA_NAMESPACE}" --timeout=180s
  kubectl rollout status daemonset/adot-collector -n "${ADOT_NAMESPACE}" --timeout=180s
}

required_cmds=(kubectl)
if [[ "${CONFIGURE_AWS_IAM}" == "true" ]]; then
  required_cmds+=(aws)
fi
for cmd in "${required_cmds[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[ERROR] ${cmd} is required" >&2
    exit 1
  fi
done

required_envs=(AWS_REGION AMP_REMOTE_WRITE_ENDPOINT)
if [[ "${CONFIGURE_AWS_IAM}" == "true" ]]; then
  required_envs+=(AWS_ACCOUNT_ID CLUSTER_NAME AMP_WORKSPACE_ID PAYMENTS_IRSA_ROLE_ARN EXPIRATION_IRSA_ROLE_ARN)
fi
for env_name in "${required_envs[@]}"; do
  if [[ -z "${!env_name:-}" ]]; then
    echo "[ERROR] ${env_name} is required" >&2
    exit 1
  fi
done

files=(
  "${MONITORING_DIR}/adot-configmap.yaml"
  "${MONITORING_DIR}/adot-collector.yaml"
  "${MONITORING_DIR}/keda-sigv4-proxy.yaml"
)

for file in "${files[@]}"; do
  if [[ ! -f "${file}" ]]; then
    echo "[ERROR] missing file: ${file}" >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

if [[ "${CONFIGURE_AWS_IAM}" == "true" ]]; then
  echo "[INFO] Ensuring IAM for KEDA AMP and ADOT remote write"
  configure_aws_iam
fi

for file in "${files[@]}"; do
  out_file="${TMP_DIR}/$(basename "${file}")"
  sed \
    -e "s|__AWS_REGION__|$(escape_sed "${AWS_REGION}")|g" \
    -e "s|__AMP_REMOTE_WRITE_ENDPOINT__|$(escape_sed "${AMP_REMOTE_WRITE_ENDPOINT}")|g" \
    "${file}" > "${out_file}"

  echo "[INFO] Applying $(basename "${file}")"
  kubectl apply -f "${out_file}"
done

echo "[INFO] ADOT pods"
kubectl get pods -n adot

echo "[INFO] SigV4 proxy"
kubectl get deploy,svc -n keda -l app=keda-sigv4

echo "[DONE] AMP monitoring stack applied"
