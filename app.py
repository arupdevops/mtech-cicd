# app.py
import os
from flask import Flask, jsonify, render_template_string, url_for, request

app = Flask(__name__)

def get_project_details():
    return {
        "project_name": os.environ.get("PROJECT_NAME", "MTech Flask CI/CD Pipeline"),
        "description": os.environ.get(
            "PROJECT_DESCRIPTION",
            "Fully automated AWS ECS CI/CD deployment for a Flask API using CodeBuild, CodePipeline, and Docker."
        ),
        "cluster": os.environ.get("CLUSTER_NAME", "mtech-cicd-cluster"),
        "service": os.environ.get("SERVICE_NAME", "flask-api-service"),
        "task_definition": os.environ.get("TASK_DEF", "flask-api-task"),
        "region": os.environ.get("AWS_REGION", "ap-south-1"),
        "repository": os.environ.get("REPOSITORY", "GitHub → CodePipeline → ECR → ECS"),
        "status": os.environ.get("APP_STATUS", "✅ Deployment successful and running"),
        "message": os.environ.get("APP_MESSAGE", "🚀 Hello World from Flask CI/CD v2!"),
        "contributors": [
            {
                "name": "Arup Jyoti Thakuria",
                "role": "2025mt03131@wilp.bits-pilani.ac.in",
                "contribution": "Infrastructure setup, CI/CD pipeline automation, ECS deployment"
            },
            {
                "name": "Kangkan Mahanta",
                "role": "2025mt03132@wilp.bits-pilani.ac.in",
                "contribution": "Flask API development, Dockerization, AWS integration"
            }
        ]
    }

# (HTML_TEMPLATE is unchanged from the colorful template you already accepted)
HTML_TEMPLATE = """..."""  # paste the full HTML template content you already used here

def wants_json():
    """
    Decide whether to return JSON.
    - If Accept header explicitly prefers application/json.
    - OR if client passed ?format=json.
    - OR if the request is an XHR (optional).
    """
    # query param override
    if request.args.get("format") == "json":
        return True

    accept = request.headers.get("Accept", "")
    if "application/json" in accept:
        return True

    # Some test clients (Flask test_client) send Accept: */* - treat as JSON-friendly.
    # We'll also consider explicit xhr header
    if request.headers.get("X-Requested-With") == "XMLHttpRequest":
        return True

    return False

@app.route("/")
def home():
    project = get_project_details()

    # If client wants JSON, return JSON (keeps tests & API clients happy)
    if wants_json():
        return jsonify(project)

    # Otherwise render the colorful HTML dashboard
    logo_env = os.environ.get("LOGO_URL", "").strip()
    if logo_env:
        logo_url = logo_env
    else:
        try:
            logo_url = url_for('static', filename='logo.png')
        except Exception:
            logo_url = None

    return render_template_string(HTML_TEMPLATE, project=project, logo_url=logo_url)

@app.route("/health")
def health():
    return jsonify({"status": "healthy"}), 200

@app.route("/version")
def version():
    return jsonify({
        "version": os.environ.get("APP_VERSION", "v2.0"),
        "build": os.environ.get("CODEBUILD_BUILD_NUMBER", "manual")
    })

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)

