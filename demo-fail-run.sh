#!/usr/bin/env bash
set -uo pipefail
# NOTE: we intentionally do NOT use `set -e` so polling will tolerate transient CLI failures;
# we handle errors explicitly to ensure cleanup always runs.

# -------------------------
# EDIT ONLY THESE
REGION="ap-south-1"
ACCOUNT="292285526557"
PIPELINE_NAME="mtech-cicd-pipeline"   # <--- set your pipeline name
CODEBUILD_PROJECT="mtech-cicd"        # <--- set your CodeBuild project name
EVENTBRIDGE_RULE_NAME="demo-ci-failure-notify"  # demo rule to enable for notification
POLICY_NAME="DemoStrongDenyPolicy"    # inline policy name (temporary)
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
  echo "Removing tmpdir $TMPDIR"
  rm -rf "$TMPDIR"
  echo "=== CLEANUP COMPLETE (exit code $rc) ==="
  exit $rc
}
trap cleanup EXIT

echo "Demo strong-fail script starting..."
echo "Region: $REGION  Account: $ACCOUNT"
echo "Pipeline: $PIPELINE_NAME  CodeBuild project: $CODEBUILD_PROJECT"
echo

# 1) Discover CodeBuild service role
echo "[1/8] Fetching CodeBuild service role..."
CB_ROLE_ARN=$(aws codebuild batch-get-projects --names "$CODEBUILD_PROJECT" --region "$REGION" --query 'projects[0].serviceRole' --output text 2>/dev/null || true)
if [[ -z "$CB_ROLE_ARN" || "$CB_ROLE_ARN" == "None" ]]; then
  echo "ERROR: could not find serviceRole for CodeBuild project '$CODEBUILD_PROJECT'. Check the project name and permissions."
  exit 2
fi
ROLE_NAME="${CB_ROLE_ARN##*/}"
echo "Found CodeBuild role ARN: $CB_ROLE_ARN"
echo "Role name: $ROLE_NAME"
echo

# 2) Write strong DENY policy file (ECR auth+push + S3 PutObject)
echo "[2/8] Writing temporary deny policy..."
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
echo "Policy written to: $DENY_POLICY_FILE"
echo

# 3) Attach inline role policy
echo "[3/8] Attaching inline deny policy to role..."
put_out=$(aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY_NAME" --policy-document file://"$DENY_POLICY_FILE" --region "$REGION" 2>&1) || {
  echo "ERROR attaching policy: $put_out"
  exit 3
}
echo "Policy attached as inline policy '$POLICY_NAME' to role '$ROLE_NAME'"
echo

# 4) Enable EventBridge rule (if exists)
echo "[4/8] Enabling EventBridge rule (if exists)..."
if aws events describe-rule --name "$EVENTBRIDGE_RULE_NAME" --region "$REGION" >/dev/null 2>&1; then
  aws events enable-rule --name "$EVENTBRIDGE_RULE_NAME" --region "$REGION" 2>/dev/null || true
  ENABLED_EVENT_RULE="true"
  echo "EventBridge rule '$EVENTBRIDGE_RULE_NAME' enabled."
else
  echo "EventBridge rule '$EVENTBRIDGE_RULE_NAME' not found — continuing without enabling."
fi
echo

# 5) Start the pipeline
echo "[5/8] Starting pipeline..."
EXEC_ID=$(aws codepipeline start-pipeline-execution --name "$PIPELINE_NAME" --region "$REGION" --query 'pipelineExecutionId' --output text 2>/dev/null || true)
if [[ -z "$EXEC_ID" || "$EXEC_ID" == "None" ]]; then
  echo "ERROR: failed to start pipeline '$PIPELINE_NAME'."
  exit 4
fi
echo "Pipeline started. execution id: $EXEC_ID"
echo

# 6) Poll pipeline status
echo "[6/8] Polling pipeline execution status until terminal state (timeout 10 minutes)..."
MAX_ITER=60   # 60 * 10s = 10 minutes
SLEEP=10
i=0
STATUS="UNKNOWN"
while (( i < MAX_ITER )); do
  ((i++))
  # tolerate transient API failures by capturing and defaulting
  STATUS_TMP=$(aws codepipeline get-pipeline-execution --pipeline-name "$PIPELINE_NAME" --pipeline-execution-id "$EXEC_ID" --region "$REGION" --query 'pipelineExecution.status' --output text 2>/dev/null || echo "UNKNOWN")
  STATUS="${STATUS_TMP:-UNKNOWN}"
  echo "$(date -u +"%Y-%m-%d %T UTC") - poll #$i - status: $STATUS"
  if [[ "$STATUS" == "SUCCEEDED" || "$STATUS" == "FAILED" || "$STATUS" == "STOPPED" ]]; then
    break
  fi
  sleep $SLEEP
done

echo
echo "[7/8] Final pipeline status: $STATUS"
if [[ "$STATUS" == "FAILED" ]]; then
  echo "Pipeline FAILED as expected. EventBridge (if enabled) should publish to SNS."
elif [[ "$STATUS" == "SUCCEEDED" ]]; then
  echo "Pipeline SUCCEEDED — the strong deny did not trigger a terminal failure. Consider manual log check or a fallback approach."
else
  echo "Pipeline ended with: $STATUS (timeout or unknown)."
fi

# 7) Try to fetch last CodeBuild build for inspection (best effort)
echo
echo "[8/8] Attempting to locate CodeBuild build & logs for project '$CODEBUILD_PROJECT'..."
BUILD_ID=$(aws codebuild list-builds-for-project --project-name "$CODEBUILD_PROJECT" --region "$REGION" --query 'ids[0]' --output text 2>/dev/null || true)
if [[ -n "$BUILD_ID" && "$BUILD_ID" != "None" ]]; then
  echo "Most recent build id: $BUILD_ID"
  aws codebuild batch-get-builds --ids "$BUILD_ID" --region "$REGION" --query 'builds[0].[buildStatus,buildComplete,logs.deepLink]' --output table || true
else
  echo "Could not determine CodeBuild build id from project '$CODEBUILD_PROJECT'. Check console if needed."
fi

# Script done — cleanup will run via trap

