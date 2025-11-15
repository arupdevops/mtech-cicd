#!/usr/bin/env bash
set -uo pipefail
# Faster polling edition: polls every 5s for up to 5 minutes.

# -------------------------
# EDIT ONLY THESE
REGION="ap-south-1"
ACCOUNT="292285526557"
PIPELINE_NAME="mtech-cicd-pipeline"   # <--- your CodePipeline name
CODEBUILD_PROJECT="mtech-cicd"        # <--- your CodeBuild project name
EVENTBRIDGE_RULE_NAME="demo-ci-failure-notify"
POLICY_NAME="DemoStrongDenyPolicy"
# -------------------------

TMPDIR=$(mktemp -d)
DENY_POLICY_FILE="$TMPDIR/demo-strong-deny.json"
EXEC_ID=""
ROLE_NAME=""
ENABLED_EVENT_RULE="false"

cleanup() {
  rc=$?
  echo "=== CLEANUP START ==="
  if [[ -n "$ROLE_NAME" ]]; then
    echo "Removing inline policy '$POLICY_NAME' from role '$ROLE_NAME' (if exists)..."
    aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY_NAME" --region "$REGION" 2>/dev/null || true
  fi
  if [[ "$ENABLED_EVENT_RULE" == "true" ]]; then
    echo "Disabling EventBridge rule '$EVENTBRIDGE_RULE_NAME'..."
    aws events disable-rule --name "$EVENTBRIDGE_RULE_NAME" --region "$REGION" 2>/dev/null || true
  fi
  rm -rf "$TMPDIR"
  echo "=== CLEANUP COMPLETE (exit code $rc) ==="
  exit $rc
}
trap cleanup EXIT

echo "Demo strong-fail script starting (fast polling)..."
echo "Region: $REGION  Account: $ACCOUNT"
echo "Pipeline: $PIPELINE_NAME  CodeBuild project: $CODEBUILD_PROJECT"
echo

# 1) Discover CodeBuild service role
CB_ROLE_ARN=$(aws codebuild batch-get-projects --names "$CODEBUILD_PROJECT" --region "$REGION" --query 'projects[0].serviceRole' --output text 2>/dev/null || true)
if [[ -z "$CB_ROLE_ARN" || "$CB_ROLE_ARN" == "None" ]]; then
  echo "ERROR: could not find serviceRole for CodeBuild project '$CODEBUILD_PROJECT'."
  exit 2
fi
ROLE_NAME="${CB_ROLE_ARN##*/}"
echo "Found CodeBuild role: $ROLE_NAME"
echo

# 2) Strong deny policy (ECR auth + push + S3 PutObject)
cat > "$DENY_POLICY_FILE" <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DemoDenyECRAuthAndPush",
      "Effect": "Deny",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "ecr:PutLifecyclePolicy"
      ],
      "Resource": "arn:aws:ecr:ap-south-1:292285526557:repository/mtech-cicd"
    },
    {
      "Sid": "DemoDenyS3PutObject",
      "Effect": "Deny",
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl"
      ],
      "Resource": "arn:aws:s3:::mtech-cicd-artifacts-arup-11467/*"
    }
  ]
}
JSON

echo "Attaching inline policy '$POLICY_NAME' to role '$ROLE_NAME'..."
aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY_NAME" --policy-document "file://$DENY_POLICY_FILE" --region "$REGION"

# 3) Enable EventBridge rule (if it exists)
if aws events describe-rule --name "$EVENTBRIDGE_RULE_NAME" --region "$REGION" >/dev/null 2>&1; then
  aws events enable-rule --name "$EVENTBRIDGE_RULE_NAME" --region "$REGION" 2>/dev/null || true
  ENABLED_EVENT_RULE="true"
  echo "EventBridge rule '$EVENTBRIDGE_RULE_NAME' enabled."
else
  echo "EventBridge rule '$EVENTBRIDGE_RULE_NAME' not found — skipping enable."
fi
echo

# 4) Start pipeline
echo "Starting pipeline '$PIPELINE_NAME'..."
EXEC_ID=$(aws codepipeline start-pipeline-execution --name "$PIPELINE_NAME" --region "$REGION" --query 'pipelineExecutionId' --output text 2>/dev/null || true)
if [[ -z "$EXEC_ID" || "$EXEC_ID" == "None" ]]; then
  echo "ERROR: failed to start pipeline."
  exit 4
fi
echo "Pipeline started. Execution ID: $EXEC_ID"
echo

# 5) Poll pipeline status (every 5s, up to 5 min)
MAX_ITER=60   # 60 * 5s = 5 min
SLEEP=5
STATUS="UNKNOWN"
for (( i=1; i<=MAX_ITER; i++ )); do
  STATUS_TMP=$(aws codepipeline get-pipeline-execution --pipeline-name "$PIPELINE_NAME" \
              --pipeline-execution-id "$EXEC_ID" --region "$REGION" \
              --query 'pipelineExecution.status' --output text 2>/dev/null || echo "UNKNOWN")
  STATUS="${STATUS_TMP:-UNKNOWN}"
  echo "$(date -u +"%Y-%m-%d %T UTC") - poll #$i - status: $STATUS"
  if [[ "$STATUS" == "SUCCEEDED" || "$STATUS" == "FAILED" || "$STATUS" == "STOPPED" ]]; then
    break
  fi
  sleep $SLEEP
done

echo
echo "Final pipeline status: $STATUS"
if [[ "$STATUS" == "FAILED" ]]; then
  echo "✅ Pipeline FAILED as expected. EventBridge (if enabled) should send SNS notification."
elif [[ "$STATUS" == "SUCCEEDED" ]]; then
  echo "⚠️  Pipeline SUCCEEDED unexpectedly — the deny may not have affected a critical step."
else
  echo "Pipeline ended with $STATUS (timeout/unknown)."
fi
echo

# 6) Show CodeBuild build info
echo "Fetching latest build info..."
BUILD_ID=$(aws codebuild list-builds-for-project --project-name "$CODEBUILD_PROJECT" --region "$REGION" --query 'ids[0]' --output text 2>/dev/null || true)
if [[ -n "$BUILD_ID" && "$BUILD_ID" != "None" ]]; then
  echo "Most recent build ID: $BUILD_ID"
  aws codebuild batch-get-builds --ids "$BUILD_ID" --region "$REGION" \
    --query 'builds[0].[buildStatus,logs.deepLink]' --output table || true
else
  echo "No build ID found."
fi

