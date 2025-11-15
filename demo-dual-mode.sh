#!/usr/bin/env bash
set -uo pipefail
#
# demo-dual-mode.sh
# Usage: ./demo-dual-mode.sh [success|failure|both]
#
# Edits: set the variables below before running.
#

# -------------------------
# EDIT ONLY THESE
REGION="ap-south-1"
ACCOUNT="292285526557"
PIPELINE_NAME="mtech-cicd-pipeline"   # <--- your CodePipeline name
CODEBUILD_PROJECT="mtech-cicd"        # <--- CodeBuild project name used by the pipeline
EVENTBRIDGE_RULE_NAME="demo-ci-failure-notify"  # rule that matches FAILED and has SNS target
POLICY_NAME="DemoStrongDenyPolicy"    # temporary inline policy name
ECR_REPO_ARN="arn:aws:ecr:ap-south-1:292285526557:repository/mtech-cicd"
S3_ARTIFACTS_ARN="arn:aws:s3:::mtech-cicd-artifacts-arup-11467/*"
# -------------------------

# Polling behaviour
SLEEP=5
MAX_ITER=60   # 60 * 5s = 5 minutes

# parse mode
MODE="${1:-both}"
if [[ "$MODE" != "success" && "$MODE" != "failure" && "$MODE" != "both" ]]; then
  echo "Invalid mode. Use one of: success, failure, both"
  exit 1
fi

TMPDIR=$(mktemp -d)
DENY_POLICY_FILE="$TMPDIR/demo-strong-deny.json"
ROLE_NAME=""
ENABLED_EVENT_RULE="false"

trap 'rc=$?; echo "Running cleanup..."; cleanup || true; echo "Exit code $rc"; rm -rf "$TMPDIR"; exit $rc' EXIT

cleanup() {
  # Remove inline policy if attached
  if [[ -n "${ROLE_NAME:-}" ]]; then
    echo "Removing inline policy '$POLICY_NAME' from role '$ROLE_NAME' (if exists)..."
    aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY_NAME" --region "$REGION" 2>/dev/null || true
  fi
  # Disable EventBridge rule if we enabled it in this script
  if [[ "$ENABLED_EVENT_RULE" == "true" ]]; then
    echo "Disabling EventBridge rule '$EVENTBRIDGE_RULE_NAME'..."
    aws events disable-rule --name "$EVENTBRIDGE_RULE_NAME" --region "$REGION" 2>/dev/null || true
  fi
}

# helper: start pipeline and poll until terminal state (returns status)
start_and_poll() {
  local pipeline="$1"
  echo "Starting pipeline '$pipeline'..."
  EXEC_ID=$(aws codepipeline start-pipeline-execution --name "$pipeline" --region "$REGION" --query 'pipelineExecutionId' --output text 2>/dev/null || true)
  if [[ -z "$EXEC_ID" || "$EXEC_ID" == "None" ]]; then
    echo "ERROR: failed to start pipeline '$pipeline'."
    return 2
  fi
  echo "Pipeline started. execution id: $EXEC_ID"
  local status="UNKNOWN"
  for (( i=1; i<=MAX_ITER; i++ )); do
    status_tmp=$(aws codepipeline get-pipeline-execution --pipeline-name "$pipeline" --pipeline-execution-id "$EXEC_ID" --region "$REGION" --query 'pipelineExecution.status' --output text 2>/dev/null || echo "UNKNOWN")
    status="${status_tmp:-UNKNOWN}"
    echo "$(date -u +"%Y-%m-%d %T UTC") - poll #$i - status: $status"
    if [[ "$status" == "SUCCEEDED" || "$status" == "FAILED" || "$status" == "STOPPED" ]]; then
      break
    fi
    sleep $SLEEP
  done
  echo "Final pipeline status: $status"
  # try to show last CodeBuild build & log link (best effort)
  echo "Attempting to fetch latest CodeBuild build info (best effort)..."
  BUILD_ID=$(aws codebuild list-builds-for-project --project-name "$CODEBUILD_PROJECT" --region "$REGION" --query 'ids[0]' --output text 2>/dev/null || true)
  if [[ -n "$BUILD_ID" && "$BUILD_ID" != "None" ]]; then
    aws codebuild batch-get-builds --ids "$BUILD_ID" --region "$REGION" --query 'builds[0].[buildStatus,logs.deepLink]' --output table || true
  else
    echo "No CodeBuild build id found for project '$CODEBUILD_PROJECT'."
  fi
  # return pipeline status in function return via echo
  echo "$status"
  return 0
}

# run success demo: just start pipeline normally
run_success_demo() {
  echo "=== Running SUCCESS demo (start pipeline normally) ==="
  status=$(start_and_poll "$PIPELINE_NAME")
  echo "SUCCESS demo completed with status: $status"
}

# run failure demo: attach deny, enable rule (if exists), start pipeline, cleanup
run_failure_demo() {
  echo "=== Running FAILURE demo (attach temporary deny -> start pipeline) ==="
  # discover role
  CB_ROLE_ARN=$(aws codebuild batch-get-projects --names "$CODEBUILD_PROJECT" --region "$REGION" --query 'projects[0].serviceRole' --output text 2>/dev/null || true)
  if [[ -z "$CB_ROLE_ARN" || "$CB_ROLE_ARN" == "None" ]]; then
    echo "ERROR: could not find CodeBuild service role for project '$CODEBUILD_PROJECT'. Aborting failure demo."
    return 2
  fi
  ROLE_NAME="${CB_ROLE_ARN##*/}"
  echo "CodeBuild role: $ROLE_NAME"

  # write strong deny policy (ECR auth/push + S3 PutObject)
  cat > "$DENY_POLICY_FILE" <<JSON
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
      "Resource": "$ECR_REPO_ARN"
    },
    {
      "Sid": "DemoDenyS3PutObject",
      "Effect": "Deny",
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl"
      ],
      "Resource": "$S3_ARTIFACTS_ARN"
    }
  ]
}
JSON

  # attach inline policy
  echo "Attaching temporary deny inline policy '$POLICY_NAME' to role '$ROLE_NAME'..."
  put_out=$(aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY_NAME" --policy-document "file://$DENY_POLICY_FILE" --region "$REGION" 2>&1) || {
    echo "ERROR attaching policy: $put_out"
    return 3
  }
  echo "Temporary deny policy attached."

  # enable EventBridge demo rule (if exists)
  if aws events describe-rule --name "$EVENTBRIDGE_RULE_NAME" --region "$REGION" >/dev/null 2>&1; then
    aws events enable-rule --name "$EVENTBRIDGE_RULE_NAME" --region "$REGION" 2>/dev/null || true
    ENABLED_EVENT_RULE="true"
    echo "EventBridge rule '$EVENTBRIDGE_RULE_NAME' enabled for demo."
  else
    echo "EventBridge rule '$EVENTBRIDGE_RULE_NAME' not found; continuing without enabling."
  fi

  # start and poll pipeline
  status=$(start_and_poll "$PIPELINE_NAME")

  # after pipeline run, remove inline policy (cleanup will also attempt)
  echo "Removing temporary inline policy..."
  aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY_NAME" --region "$REGION" 2>/dev/null || true
  ROLE_NAME=""  # clear so cleanup won't attempt again
  echo "Temporary inline policy removed."

  # disable event rule if we enabled it
  if [[ "$ENABLED_EVENT_RULE" == "true" ]]; then
    echo "Disabling EventBridge rule '$EVENTBRIDGE_RULE_NAME'..."
    aws events.disable-rule --name "$EVENTBRIDGE_RULE_NAME" --region "$REGION" 2>/dev/null || true
    ENABLED_EVENT_RULE="false"
  fi

  echo "FAILURE demo completed with status: $status"
  return 0
}

# MAIN logic
echo "Demo mode: $MODE"
case "$MODE" in
  success)
    run_success_demo
    ;;
  failure)
    run_failure_demo
    ;;
  both)
    run_success_demo
    echo
    echo "Waiting 5s before running failure demo..."
    sleep 5
    run_failure_demo
    ;;
esac

# normal exit; cleanup trap will run
exit 0

