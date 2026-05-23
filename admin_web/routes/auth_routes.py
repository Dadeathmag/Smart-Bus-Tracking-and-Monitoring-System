from flask import Blueprint, jsonify, redirect, render_template,current_app, request
from datetime import datetime, timedelta    
from services.auth_service import firebase_required
from firebase_admin import auth

auth_bp = Blueprint("auth_bp", __name__)

@auth_bp.route("/redirect")
@firebase_required()
def redirect_user():
    if request.user_role == "admin":
        return jsonify({"redirect": "/admin/dashboard"})
    else:
        return jsonify({"redirect": "/user"})

from datetime import datetime
from flask import current_app, render_template

@auth_bp.route("/admin/dashboard")
@firebase_required(admin=True)
def dashboard():
    db = current_app.config["db"]

    total_buses = len(list(db.collection("buses").stream()))
    total_students = len(list(db.collection("students").stream()))

    today = datetime.now().strftime("%Y-%m-%d")

    attendance_docs = db.collection("attendance").document(today)\
                        .collection("students").stream()

    today_attendance = len(list(attendance_docs))

    # Fetch college location (always provide numeric defaults for templates/JS)
    college_doc = db.collection("config").document("college_location").get()

    college_lat = 12.9716
    college_lng = 77.5946
    college_name = "College"

    if college_doc.exists:
        data = college_doc.to_dict() or {}
        try:
            college_lat = float(data.get("latitude", college_lat))
        except (TypeError, ValueError):
            pass

        try:
            college_lng = float(data.get("longitude", college_lng))
        except (TypeError, ValueError):
            pass

        college_name = data.get("name") or college_name

    return render_template(
        "dashboard.html",
        total_buses=total_buses,
        total_students=total_students,
        today_attendance=today_attendance,
        college_lat=college_lat,
        college_lng=college_lng,
        college_name=college_name
    )

@auth_bp.route("/admin/attendance")
@firebase_required(admin=True)
def attendance():
    db = current_app.config["db"]
    selected_date = request.args.get("date") or datetime.now().strftime("%Y-%m-%d")

    morning_rows = []
    evening_rows = []
    attendance_docs = (
        db.collection("attendance")
        .document(selected_date)
        .collection("students")
        .stream()
    )

    def normalize_shift(data):
        raw = (
            data.get("shift")
            or data.get("route_type")
            or data.get("trip")
            or data.get("session")
            or data.get("time_of_day")
            or data.get("period")
            or ""
        )
        shift_text = str(raw).strip().lower()
        if "morn" in shift_text or shift_text in {"am", "a.m"}:
            return "morning"
        if "even" in shift_text or shift_text in {"pm", "p.m"}:
            return "evening"
        return "morning"

    for doc in attendance_docs:
        data = doc.to_dict() or {}

        student_name = (
            data.get("student_name")
            or data.get("name")
            or data.get("studentName")
            or data.get("student_id")
            or data.get("studentId")
            or doc.id
        )
        admission_number = (
            data.get("admission_number")
            or data.get("admissionNumber")
            or "-"
        )
        bus_no = data.get("bus_no") or data.get("busNo") or "-"
        status = (
            data.get("status")
            or data.get("attendance_status")
            or ("present" if data.get("present") else "absent")
        )
        marked_at = (
            data.get("time")
            or data.get("timestamp")
            or data.get("marked_at")
            or data.get("last_updated")
            or "-"
        )

        row = (
            {
                "student_name": student_name,
                "admission_number": admission_number,
                "bus_no": bus_no,
                "status": str(status).title(),
                "marked_at": marked_at,
            }
        )

        if normalize_shift(data) == "evening":
            evening_rows.append(row)
        else:
            morning_rows.append(row)

    morning_rows.sort(key=lambda row: row["student_name"])
    evening_rows.sort(key=lambda row: row["student_name"])

    return render_template(
        "attendance.html",
        selected_date=selected_date,
        morning_rows=morning_rows,
        evening_rows=evening_rows,
        morning_count=len(morning_rows),
        evening_count=len(evening_rows),
        total_count=len(morning_rows) + len(evening_rows),
    )

@auth_bp.route("/user")
@firebase_required()
def user():
    return "Welcome User 👤"

from flask import make_response

@auth_bp.route("/sessionLogin", methods=["POST"])
def session_login():
    payload = request.get_json(silent=True) or {}
    id_token = payload.get("idToken")

    if not id_token:
        return jsonify({"error": "Missing idToken"}), 400

    expires_in = timedelta(days=5)

    try:
        # Small skew tolerance helps when local machine time drifts slightly.
        auth.verify_id_token(id_token, clock_skew_seconds=60)
        session_cookie = auth.create_session_cookie(
            id_token, expires_in=expires_in
        )

        response = make_response(jsonify({"status": "success"}))
        response.set_cookie(
            "session",
            session_cookie,
            httponly=True,
            secure=False,  # True in production (HTTPS)
            samesite="Lax",
        )
        return response

    except Exception as e:
        # Keep error concise for UI, but include reason for local debugging.
        print(f"[AUTH] sessionLogin failed: {e}")
        return jsonify({"error": f"Unauthorized: {str(e)}"}), 401
    
@auth_bp.route("/logout")
def logout():
    session_cookie = request.cookies.get("session")

    if session_cookie:
        try:
            decoded = auth.verify_session_cookie(session_cookie)
            auth.revoke_refresh_tokens(decoded["uid"])
        except:
            pass

    response = make_response(redirect("/"))
    response.delete_cookie("session")
    return response


