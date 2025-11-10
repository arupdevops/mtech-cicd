# app.py
import os
from flask import Flask, jsonify, render_template_string, url_for

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

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>{{ project.project_name }}</title>
  <style>
    :root{
      --bg: #f6f9fc;
      --card: #ffffff;
      --text: #243b53;
      --muted: #6b7a86;
      --accent: #5e9cff;
      --success: #27ae60;
      --glass: rgba(255,255,255,0.6);
    }
    [data-theme="dark"]{
      --bg: #0f1724;
      --card: #0b1117;
      --text: #e6eef7;
      --muted: #99a7bf;
      --accent: #4aa3ff;
      --success: #4cd285;
      --glass: rgba(255,255,255,0.03);
    }
    body{
      margin:0;
      font-family: Inter, "Segoe UI", Roboto, Arial, sans-serif;
      background: linear-gradient(135deg, rgba(94,156,255,0.08), rgba(172,182,229,0.06));
      color:var(--text);
      min-height:100vh;
      display:flex;
      align-items:center;
      justify-content:center;
      padding:24px;
      background-color:var(--bg);
    }
    .card{
      width:100%;
      max-width:920px;
      background: linear-gradient(180deg, var(--card), var(--glass));
      border-radius:14px;
      box-shadow: 0 10px 30px rgba(18,35,64,0.12);
      padding:22px;
      overflow:hidden;
      border: 1px solid rgba(0,0,0,0.04);
    }
    .header{
      display:flex;
      gap:18px;
      align-items:center;
      margin-bottom:8px;
    }
    .logo{
      width:84px;
      height:84px;
      border-radius:10px;
      background:linear-gradient(135deg, rgba(94,156,255,0.2), rgba(172,182,229,0.18));
      display:flex;
      align-items:center;
      justify-content:center;
      overflow:hidden;
      flex-shrink:0;
    }
    .logo img{ width:100%; height:100%; object-fit:contain; display:block; }
    h1{ margin:0; font-size:20px; letter-spacing:0.2px; }
    p.desc{ margin:6px 0 0 0; color:var(--muted); font-size:13px; }
    .meta{ display:flex; gap:12px; flex-wrap:wrap; margin-top:14px; }
    .meta .pill{
      background: rgba(0,0,0,0.04);
      padding:8px 12px;
      border-radius:999px;
      font-size:13px;
      color:var(--muted);
      border:1px solid rgba(0,0,0,0.02);
    }
    .status { margin-top:16px; display:flex; align-items:center; gap:12px; }
    .status .dot{ width:12px;height:12px;border-radius:50%; background:var(--success); box-shadow:0 0 8px rgba(39,174,96,0.16); }
    .grid{
      display:grid;
      grid-template-columns: 1fr 320px;
      gap:18px;
      margin-top:18px;
    }
    .section{
      background: transparent;
      padding:14px;
      border-radius:10px;
    }
    .contributors{
      background: linear-gradient(180deg, rgba(255,255,255,0.6), rgba(255,255,255,0.02));
      border-radius:10px;
      padding:12px;
    }
    .contributors li{ margin-bottom:12px; list-style:none; padding-bottom:6px; border-bottom:1px dashed rgba(0,0,0,0.04); }
    .contributors strong{ display:block; font-size:15px; }
    .contributors small{ color:var(--muted); display:block; margin-top:4px; font-size:13px; }
    .message{
      margin-top:10px;
      padding:12px;
      border-radius:8px;
      background: linear-gradient(90deg, rgba(94,156,255,0.05), rgba(39,174,96,0.03));
      border:1px solid rgba(0,0,0,0.03);
      color:var(--text);
    }
    .toggle{
      margin-left:auto;
      display:flex;
      align-items:center;
      gap:8px;
    }
    .toggle button{
      background:transparent;
      border:1px solid rgba(0,0,0,0.06);
      padding:8px 10px;
      border-radius:8px;
      cursor:pointer;
      color:var(--muted);
    }
    footer{ text-align:center; margin-top:18px; color:var(--muted); font-size:13px; }
    @media(max-width:880px){
      .grid{ grid-template-columns: 1fr; }
      .logo{ width:68px; height:68px; }
    }
  </style>
</head>
<body>
  <div class="card" id="root">
    <div class="header">
      <div class="logo">
        {% if logo_url %}
          <img src="{{ logo_url }}" alt="project logo" />
        {% else %}
          <div style="font-weight:700;color:var(--accent)">MF</div>
        {% endif %}
      </div>
      <div style="flex:1">
        <h1>{{ project.project_name }}</h1>
        <p class="desc">{{ project.description }}</p>
        <div class="meta">
          <div class="pill">Cluster: {{ project.cluster }}</div>
          <div class="pill">Service: {{ project.service }}</div>
          <div class="pill">Region: {{ project.region }}</div>
          <div class="pill">Task: {{ project.task_definition }}</div>
        </div>
        <div class="status">
          <div class="dot" aria-hidden="true"></div>
          <div style="font-size:14px;color:var(--muted)"><strong>Status</strong> &nbsp; <span style="color:var(--success)">{{ project.status }}</span></div>
          <div class="toggle">
            <span style="font-size:13px;color:var(--muted)">Theme</span>
            <button id="themeToggle">Toggle Dark</button>
          </div>
        </div>
      </div>
    </div>

    <div class="grid">
      <div class="section">
        <h3>💬 Message</h3>
        <div class="message">{{ project.message }}</div>

        <h3 style="margin-top:18px">📦 Repository & Info</h3>
        <p style="color:var(--muted)"><strong>Repo:</strong> {{ project.repository }}</p>
      </div>

      <aside class="section">
        <h3>👩‍💻 Contributors</h3>
        <ul class="contributors">
          {% for c in project.contributors %}
            <li>
              <strong>{{ c.name }}</strong>
              <small>{{ c.role }}</small>
              <small style="color:var(--muted)">{{ c.contribution }}</small>
            </li>
          {% endfor %}
        </ul>

        <h3 style="margin-top:12px">🔧 Endpoints</h3>
        <p style="color:var(--muted);font-size:13px;margin:0">/health (JSON)</p>
        <p style="color:var(--muted);font-size:13px;margin:0">/version (JSON)</p>
      </aside>
    </div>

    <footer>
      Built with ❤️ using Flask, Docker & AWS ECS — <small style="display:block;margin-top:6px;color:var(--muted)">Theme preference saved locally</small>
    </footer>
  </div>

<script>
  // Dark mode toggle with localStorage
  const root = document.documentElement;
  const stored = localStorage.getItem('theme');
  if (stored === 'dark') {
    document.documentElement.setAttribute('data-theme','dark');
  } else {
    document.documentElement.removeAttribute('data-theme');
  }

  document.getElementById('themeToggle').addEventListener('click', () => {
    const current = document.documentElement.getAttribute('data-theme');
    if (current === 'dark') {
      document.documentElement.removeAttribute('data-theme');
      localStorage.setItem('theme','light');
      document.getElementById('themeToggle').textContent = 'Toggle Dark';
    } else {
      document.documentElement.setAttribute('data-theme','dark');
      localStorage.setItem('theme','dark');
      document.getElementById('themeToggle').textContent = 'Toggle Light';
    }
  });

  // Set correct button text on load
  if (localStorage.getItem('theme') === 'dark') {
    document.getElementById('themeToggle').textContent = 'Toggle Light';
  } else {
    document.getElementById('themeToggle').textContent = 'Toggle Dark';
  }
</script>
</body>
</html>
"""

@app.route("/")
def home():
    project = get_project_details()

    # Use external logo URL if provided; otherwise expect static/logo.png in repo
    logo_env = os.environ.get("LOGO_URL", "").strip()
    if logo_env:
        logo_url = logo_env
    else:
        # url_for works inside request context
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

