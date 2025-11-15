# app.py
import os
from flask import Flask, jsonify

app = Flask(__name__)

def get_project_details():
    return {
        "project_name": os.environ.get("PROJECT_NAME", "MTech Flask CI/CD Pipeline01"),
        "description": os.environ.get("PROJECT_DESCRIPTION", "Fully automated AWS ECS CI/CD deployment for a Flask API using CodeBuild, CodePipeline, and Docker."),
        "cluster": os.environ.get("CLUSTER_NAME", "mtech-cicd-cluster"),
        "service": os.environ.get("SERVICE_NAME", "flask-api-service"),
        "task_definition": os.environ.get("TASK_DEF", "flask-api-task"),
        "region": os.environ.get("AWS_REGION", "ap-south-1"),
        "repository": os.environ.get("REPOSITORY", "GitHub → ECR → ECS"),
        "status": os.environ.get("APP_STATUS", "Deployment successful and running"),
        "message": os.environ.get("APP_MESSAGE", "Hello World from Flask CI/CD v2!")
    }

@app.route("/")
def home():
    return jsonify(get_project_details())

@app.route("/health")
def health():
    # Simple health check for ALB / monitoring
    return jsonify({"status": "healthy"}), 200

@app.route("/version")
def version():
    return jsonify({
        "version": os.environ.get("APP_VERSION", "v2.0"),
        "build": os.environ.get("CODEBUILD_BUILD_NUMBER", "manual")
    })

if __name__ == "__main__":
    # Use PORT env var, fallback to 8080
    port = int(os.environ.get("PORT", 8080))
    # Bind to 0.0.0.0 so ECS / host can route to the container
    app.run(host="0.0.0.0", port=port)

