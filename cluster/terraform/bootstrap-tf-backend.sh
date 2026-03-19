#!/usr/bin/env bash
# bootstrap-tf-backend.sh
# Run ONCE before the first `terraform init` to create the S3 + DynamoDB
# state backend. After this runs, copy the bucket name into backend.hcl.
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
CLUSTER_NAME="${CLUSTER_NAME:-ticket-selling-eks}"
BUCKET_NAME="${CLUSTER_NAME}-tf-state-${AWS_ACCOUNT_ID}"
TABLE_NAME="${CLUSTER_NAME}-tf-lock"

echo "Creating S3 bucket: $BUCKET_NAME"
if [[ "$AWS_REGION" == "us-east-1" ]]; then
  aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"
else
  aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" \
    --create-bucket-configuration LocationConstraint="$AWS_REGION"
fi

aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{
    "Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]
  }'

aws s3api put-public-access-block --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
  'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'

echo "Creating DynamoDB table: $TABLE_NAME"
aws dynamodb create-table \
  --table-name "$TABLE_NAME" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$AWS_REGION"

echo ""
echo "✅ Backend ready. Create backend.hcl with:"
echo "bucket         = \"$BUCKET_NAME\""
echo "key            = \"ticket-selling/terraform.tfstate\""
echo "region         = \"$AWS_REGION\""
echo "dynamodb_table = \"$TABLE_NAME\""
echo "encrypt        = true"
