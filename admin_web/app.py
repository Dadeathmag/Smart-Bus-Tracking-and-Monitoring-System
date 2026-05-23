import os
from flask import Flask, render_template, Response
from env_config import get_firebase_client_config
from firebase_init import initialize_firebase
from routes.admin_student_routes import student_bp
from routes.admin_bus_routes import bus_bp
from routes.auth_routes import auth_bp
from routes.settings_route import settings_bp
from apscheduler.schedulers.background import BackgroundScheduler

from services.fee_service import generate_fees

def start_scheduler():
    if not scheduler.running:
        scheduler.start()

app = Flask(__name__)

db,rtdb = initialize_firebase()
scheduler = BackgroundScheduler()
scheduler.add_job(
    func=generate_fees,
    trigger="cron",
    month="1,7",
    day=1,
    hour=0,
    minute=0
)

scheduler.start()

app.config["db"] = db
app.config["rtdb"] = rtdb
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024 

app.register_blueprint(student_bp)
app.register_blueprint(bus_bp)
app.register_blueprint(auth_bp)
app.register_blueprint(settings_bp)


@app.route("/")
def login():
    return render_template(
        "login.html",
        firebase_config=get_firebase_client_config(),
    )

@app.route("/favicon.ico")
def favicon():
    return Response(status=204)

if __name__ == "__main__":
    if not app.debug or os.environ.get("WERKZEUG_RUN_MAIN") == "true":
        start_scheduler()
    app.run(debug=True)