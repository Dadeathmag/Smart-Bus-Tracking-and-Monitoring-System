from datetime import datetime,timedelta

from flask import Blueprint, request, current_app, render_template, url_for, redirect, jsonify
from services.auth_service import firebase_required
from services.student_service import (
    create_student,
    get_all_students,
    delete_student_by_id
)
import os
import uuid
from werkzeug.utils import secure_filename
import cv2
import numpy as np
import mediapipe as mp
import tensorflow as tf
import base64
from firebase_admin import auth, firestore
# ----------------------
# Load FaceNet model once
# ----------------------
BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MODEL_PATH = os.path.join(BASE_DIR, "models", "mobile_face_net.tflite")

interpreter = tf.lite.Interpreter(model_path=MODEL_PATH)
interpreter.allocate_tensors()

input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

# ----------------------
# Load MediaPipe detector once
# ----------------------
mp_face_detection = mp.solutions.face_detection
face_detector = mp_face_detection.FaceDetection(
    model_selection=0,
    min_detection_confidence=0.6
)

def detect_and_crop_face(image_path):
    img = cv2.imread(image_path)
    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    results = face_detector.process(img_rgb)

    if not results.detections:
        return None

    detection = results.detections[0]  # Take first face
    bbox = detection.location_data.relative_bounding_box

    h, w, _ = img.shape

    x1 = int(bbox.xmin * w)
    y1 = int(bbox.ymin * h)
    x2 = int((bbox.xmin + bbox.width) * w)
    y2 = int((bbox.ymin + bbox.height) * h)

    # Add small margin
    margin = 20
    x1 = max(0, x1 - margin)
    y1 = max(0, y1 - margin)
    x2 = min(w, x2 + margin)
    y2 = min(h, y2 + margin)

    face = img[y1:y2, x1:x2]

    return face

def generate_embedding_from_face(face_img):
    face = cv2.resize(face_img, (112, 112))
    face = cv2.cvtColor(face, cv2.COLOR_BGR2RGB)

    face = face.astype("float32")
    face = (face - 127.5) / 128.0
    face = np.expand_dims(face, axis=0)

    interpreter.set_tensor(input_details[0]['index'], face)
    interpreter.invoke()

    embedding = interpreter.get_tensor(output_details[0]['index'])[0]

    # L2 normalize
    embedding = embedding / np.linalg.norm(embedding)

    return embedding

student_bp = Blueprint("student_bp", __name__)


def generate_base64_image(original_file_path):
    try:
        img = cv2.imread(original_file_path)
        if img is None:
            print(f"[DISPLAY] cv2.imread returned None for: {original_file_path}")
            return None

        h, w = img.shape[:2]
        max_dim = 300
        if h > max_dim or w > max_dim:
            scale = max_dim / max(h, w)
            img = cv2.resize(img, (int(w * scale), int(h * scale)),
                             interpolation=cv2.INTER_AREA)

        encode_param = [int(cv2.IMWRITE_JPEG_QUALITY), 75]
        ok, buf = cv2.imencode('.jpg', img, encode_param)
        if not ok:
            print("[DISPLAY] cv2.imencode failed")
            return None

        b64 = base64.b64encode(buf.tobytes()).decode('utf-8')
        result = f"data:image/jpeg;base64,{b64}"
        print(f"[DISPLAY] Base64 length: {len(result)}")
        return result
    except Exception as exc:
        print(f"[DISPLAY] Error: {exc}")
        return None


#student home
@student_bp.route("/admin/students")
@firebase_required(admin=True)
def student_home():
    return render_template("student_home.html")


@student_bp.route("/admin/students/add-student")
@firebase_required(admin=True)
def add_student_form():
    db = current_app.config["db"]
    buses_ref = db.collection("buses").stream()
    available_buses = []
    
    for doc in buses_ref:
        data = doc.to_dict()
        if data.get("bus_number"):
            available_buses.append({
                "id": doc.id,
                "bus_number": data.get("bus_number"),
                "name": data.get("name", ""),
                "routes": data.get("routes", {})  
            })
            
    print("Buses loaded:", available_buses)
    return render_template("add_student.html", available_buses=available_buses)


#add student
@student_bp.route("/admin/students/add", methods=["POST"])
@firebase_required(admin=True)
def add_student():
    db = current_app.config["db"]

    name = request.form.get("name")
    admission_number = request.form.get("admission_number")
    bus_id = request.form.get("bus_id")  
    bus_no = request.form.get("bus_no")
    student_email = request.form.get("student_email")
    student_password = request.form.get("student_password")
    parent_email = request.form.get("parent_email")
    parent_password = request.form.get("parent_password")
    phone_number = request.form.get("phone_number")
    parent_phone_number = request.form.get("parent_phone_number")
    
    morning_stop = request.form.get("morning_stop")
    evening_stop = request.form.get("evening_stop")

    bus_doc = db.collection("buses").document(bus_id).get()
    if not bus_doc.exists:
        return "Bus not found", 404

    bus_data = bus_doc.to_dict() or {}

    # Enforce bus capacity using `student_limit` saved in admin_bus_routes.py.
    # (current_strength is incremented/decremented when students are added/deleted.)
    try:
        current_strength = int(bus_data.get("current_strength", 0) or 0)
        student_limit = int(bus_data.get("student_limit"))
    except (TypeError, ValueError):
        return "Invalid bus capacity configuration", 400

    if student_limit <= 0:
        return "Invalid bus student_limit", 400

    if current_strength >= student_limit:
        return "Bus is full", 400

    routes_data = {
        "morning": None,
        "evening": None
    }

    total_fee = 0
    
    # handle morning
    if morning_stop:
        morning_doc = db.collection("buses").document(bus_id).collection("routes").document("morning").get()
        stops = morning_doc.to_dict().get("stops", []) if morning_doc.exists else []
        selected = next((s for s in stops if s["name"] == morning_stop), None)

        if not selected:
            return "Invalid morning stop", 400

        routes_data["morning"] = {
            "stop_name": morning_stop,
            "fee": selected["fee"]
        }
        total_fee += selected["fee"]

    # handle evening
    if evening_stop:
        evening_doc = db.collection("buses").document(bus_id).collection("routes").document("evening").get()
        stops = evening_doc.to_dict().get("stops", []) if evening_doc.exists else []
        selected = next((s for s in stops if s["name"] == evening_stop), None)

        if not selected:
            return "Invalid evening stop", 400

        routes_data["evening"] = {
            "stop_name": evening_stop,
            "fee": selected["fee"]
        }
        total_fee += selected["fee"]


    embedding = None

    if not name or not admission_number or not bus_no or not student_email or not student_password or not parent_email or not parent_password:
        return "Missing required fields", 400

    photo_files = request.files.getlist("photo")
    photo_file = None

    for f in photo_files:
        if f and f.filename != "":
            photo_file = f
            break
    
    if not photo_file:
        return "Photo is required for face registration.", 400

    # Check duplicates
    existing = list(db.collection("students").where("admission_number", "==", admission_number).stream())
    if existing:
        return f"Student with admission_number {admission_number} already exists.", 400

    try:
        auth.get_user_by_email(student_email)
        return f"Student email {student_email} is already registered.", 400
    except auth.UserNotFoundError:
        pass 

    try:
        auth.get_user_by_email(parent_email)
        return f"Parent email {parent_email} is already registered.", 400
    except auth.UserNotFoundError:
        pass 



    UPLOAD_FOLDER = os.path.join(
        current_app.root_path,
        "static/uploads/students"
    )
    os.makedirs(UPLOAD_FOLDER, exist_ok=True)

    photo_path = None

    if photo_file:
        original_filename = secure_filename(photo_file.filename)
        unique_name = f"{uuid.uuid4()}_{original_filename}"
        file_path = os.path.join(UPLOAD_FOLDER, unique_name)

        photo_file.save(file_path)
        photo_path = f"/static/uploads/students/{unique_name}"
        #  Detect face
        face = detect_and_crop_face(file_path)

    if face is None:
        os.remove(file_path)
        return "No face detected. Please upload a clear photo.", 400

    try:
    #  Generate embedding
        embedding = generate_embedding_from_face(face)

        photo_base64 = generate_base64_image(file_path)
        if not photo_base64 or not photo_base64.startswith("data:image/jpeg;base64,"):
            return "Error: Invalid Base64 prefix generated. Aborting enrollment.", 400
        
    except Exception as e:
        return f"Image pipeline error: {str(e)}", 500


    # ── Create Firebase Auth user ───────────────────────────────────
    uid = None
    try:
        new_user = auth.create_user(
            email=student_email,
            password=student_password
        )
        uid = new_user.uid
    except Exception as e:
        return f"Firebase Auth Error: {str(e)}", 400
    pid = None
    try:
        new_parent = auth.create_user(
            email=parent_email,
            password=parent_password
        )
        pid = new_parent.uid
    except Exception as e:
        return f"Firebase Auth Error: {str(e)}", 400
    

    student_data = {
        "name": name,
        "admission_number": admission_number,
        "bus_id": bus_id,
        "bus_no": bus_no,
        "routes": routes_data,
        "total_fee": total_fee,
        "embedding": embedding.tolist(),
        "uid": uid,
        "pid": pid,
        "email": student_email,
        #"password": student_password,
        "phone_number": phone_number,
        "parent_email": parent_email,
        #"parent_password": parent_password,
        "parent_phone_number": parent_phone_number,
        "photo_path": photo_path,
        "photoBase64": photo_base64,
        "status": "active",
        "createdAt": firestore.SERVER_TIMESTAMP
    }

    try:
        student_id = create_student(db, student_data)


        today = datetime.today()

        # Due date = 20 days after creation
        due_date = today + timedelta(days=20)

        # Decide cycle based on due date month
        if due_date.month <= 6:
            cycle = "JAN"
        else:
            cycle = "JULY"

        months_remaining = 6 - (today.month % 6) + 1
        amount = (student_data["total_fee"] / 6) * months_remaining

        fee_data = {
            "studentId": student_id,
            "studentName": student_data.get("name", ""),
            "admissionNumber": student_data.get("admission_number", ""),
            "busId": student_data.get("bus_id", ""),
            "amount": amount,
            "dueDate": due_date,
            "cycle": cycle,              #  important
            "year": today.year,          #  prevent duplicates
            "status": "pending",
            "paidAt": None,
            "paidBy": None,
            "createdAt": firestore.SERVER_TIMESTAMP,
        }
        existing_fee = db.collection("fees") \
            .where("studentId", "==", student_id) \
            .where("cycle", "==", cycle) \
            .where("year", "==", today.year) \
            .get()

        if len(list(existing_fee)) == 0:
            db.collection("fees").add(fee_data)
            

    except Exception as e:
        if uid or pid:
            try:
                if uid:
                    auth.delete_user(uid)
                if pid:
                    auth.delete_user(pid)
            except Exception:
                pass
        return f"Firestore Error: {str(e)}", 500

    # Update the bus capacity counter only after student creation succeeds.
    db.collection("buses").document(bus_id).update(
        {"current_strength": current_strength + 1}
    )
    
    return redirect(url_for("student_bp.student_home"))





# Get All Students
@student_bp.route("/admin/students/manage")
@firebase_required(admin=True)
def list_students():
    db = current_app.config["db"]
    bus_id = request.args.get("bus_id")

    # Load buses for dropdown (use bus_number as human-friendly label).
    buses = []
    for doc in db.collection("buses").stream():
        data = doc.to_dict() or {}
        buses.append(
            {
                "id": doc.id,
                "bus_number": data.get("bus_number", ""),
                "name": data.get("name", ""),
            }
        )

    if bus_id:
        students = []
        for doc in db.collection("students").where("bus_id", "==", bus_id).stream():
            students.append((doc.id, doc.to_dict() or {}))
    else:
        students = get_all_students(db)

    return render_template(
        "manage_students.html",
        students=students,
        buses=buses,
        selected_bus_id=bus_id,
    )

@student_bp.route("/admin/students/delete/<student_id>", methods=["POST"])
@firebase_required(admin=True)
def delete_student(student_id):
    db = current_app.config["db"]

    student_doc = db.collection("students").document(student_id).get()

    if student_doc.exists:
        student_data = student_doc.to_dict()

        # Delete photo file if exists
        photo_path = student_data.get("photo_path")
        if photo_path:
            file_path = os.path.join(
                current_app.root_path,
                photo_path.lstrip("/")
            )
            if os.path.exists(file_path):
                os.remove(file_path)

        # Delete Firebase Auth User if created
        uid = student_data.get("uid")
        pid = student_data.get("pid")
        if uid or pid:
            try:
                if uid:
                    auth.delete_user(uid)
                if pid:
                    auth.delete_user(pid)
            except Exception as e:
                print(f"Error deleting auth user {uid}: {e}")

        #  Delete student document
        db.collection("students").document(student_id).delete()

        # Decrement bus capacity counter when deleting a student.
        bus_id_for_student = student_data.get("bus_id")
        if bus_id_for_student:
            bus_doc = db.collection("buses").document(bus_id_for_student).get()
            if bus_doc.exists:
                bus_data = bus_doc.to_dict() or {}
                try:
                    current_strength = int(bus_data.get("current_strength", 0) or 0)
                    new_strength = max(0, current_strength - 1)
                except (TypeError, ValueError):
                    new_strength = 0

                db.collection("buses").document(bus_id_for_student).update(
                    {"current_strength": new_strength}
                )

    return redirect(url_for("student_bp.list_students"))

@student_bp.route("/admin/students/manage/<student_id>")
@firebase_required(admin=True)
def manage_student(student_id):
    db = current_app.config["db"]

    student_doc = db.collection("students").document(student_id).get()

    if not student_doc.exists:
        return "Student not found", 404

    student = student_doc.to_dict()

    # Load fees for this student — sorted newest first
    fees_ref = (
        db.collection("fees")
        .where("studentId", "==", student_id)
        .order_by("createdAt", direction=firestore.Query.DESCENDING)
        .stream()
    )
    fees = []
    for f in fees_ref:
        f_data = f.to_dict()
        f_data["id"] = f.id
        fees.append(f_data)

    buses_ref = db.collection("buses").stream()
    available_buses = []
    
    for doc in buses_ref:
        data = doc.to_dict()
        if data.get("bus_number"):
            available_buses.append({
                "id": doc.id,
                "bus_number": data.get("bus_number"),
                "name": data.get("name", "")
            })

    return render_template(
        "student_detail.html",
        student=student,
        student_id=student_id,
        fees=fees,
        available_buses=available_buses
    )

@student_bp.route("/admin/students/update/<student_id>", methods=["POST"])
@firebase_required(admin=True)
def update_student(student_id):
    db = current_app.config["db"]
    student_ref = db.collection("students").document(student_id)
    student_doc = student_ref.get()

    if not student_doc.exists:
        return "Student not found", 404

    student_data = student_doc.to_dict() or {}

    name = request.form.get("name")
    admission_number = request.form.get("admission_number")
    bus_no = request.form.get("bus_no")
    parent_phone_number = request.form.get("parent_phone_number")
    status = request.form.get("status")

    if not name or not admission_number or not bus_no:
        return "Missing required fields", 400

    if status not in {"active", "inactive"}:
        return "Invalid status", 400

    buses = list(db.collection("buses").where("bus_number", "==", bus_no).limit(1).stream())
    if not buses:
        return "Selected bus not found", 404

    target_bus_doc = buses[0]
    target_bus_id = target_bus_doc.id
    target_bus_data = target_bus_doc.to_dict() or {}

    old_bus_id = student_data.get("bus_id")
    bus_changed = old_bus_id and old_bus_id != target_bus_id

    if bus_changed:
        try:
            current_strength = int(target_bus_data.get("current_strength", 0) or 0)
            student_limit = int(target_bus_data.get("student_limit"))
        except (TypeError, ValueError):
            return "Invalid bus capacity configuration", 400

        if current_strength >= student_limit:
            return "Selected bus is full", 400

    updates = {
        "name": name,
        "admission_number": admission_number,
        "bus_id": target_bus_id,
        "bus_no": bus_no,
        "parent_phone_number": parent_phone_number,
        "status": status,
    }

    photo_file = request.files.get("photo")
    if photo_file and photo_file.filename:
        upload_folder = os.path.join(current_app.root_path, "static/uploads/students")
        os.makedirs(upload_folder, exist_ok=True)

        original_filename = secure_filename(photo_file.filename)
        unique_name = f"{uuid.uuid4()}_{original_filename}"
        file_path = os.path.join(upload_folder, unique_name)
        photo_file.save(file_path)

        face = detect_and_crop_face(file_path)
        if face is None:
            os.remove(file_path)
            return "No face detected. Please upload a clear photo.", 400

        try:
            embedding = generate_embedding_from_face(face)
            photo_base64 = generate_base64_image(file_path)
        except Exception as e:
            return f"Image pipeline error: {str(e)}", 500

        updates["embedding"] = embedding.tolist()
        updates["photo_path"] = f"/static/uploads/students/{unique_name}"
        updates["photoBase64"] = photo_base64

        old_photo_path = student_data.get("photo_path")
        if old_photo_path:
            old_file_path = os.path.join(current_app.root_path, old_photo_path.lstrip("/"))
            if os.path.exists(old_file_path):
                os.remove(old_file_path)

    student_ref.update(updates)

    if bus_changed:
        old_bus_doc = db.collection("buses").document(old_bus_id).get()
        if old_bus_doc.exists:
            old_bus_data = old_bus_doc.to_dict() or {}
            try:
                old_strength = int(old_bus_data.get("current_strength", 0) or 0)
            except (TypeError, ValueError):
                old_strength = 0
            db.collection("buses").document(old_bus_id).update(
                {"current_strength": max(0, old_strength - 1)}
            )

        try:
            new_strength = int(target_bus_data.get("current_strength", 0) or 0) + 1
        except (TypeError, ValueError):
            new_strength = 1
        db.collection("buses").document(target_bus_id).update({"current_strength": new_strength})

    return redirect(url_for("student_bp.manage_student", student_id=student_id))

@student_bp.route("/admin/students/mark_fee_paid/<fee_id>", methods=["POST"])
@firebase_required(admin=True)
def mark_fee_paid(fee_id):
    """Admin override: mark a pending fee as paid."""
    db = current_app.config["db"]

    fee_ref = db.collection("fees").document(fee_id)

    try:
        fee_doc = fee_ref.get()
    except Exception as e:
        return {"error": f"Firestore error: {str(e)}"}, 500

    if not fee_doc.exists:
        return {"error": "Fee not found."}, 404

    fee_data = fee_doc.to_dict()

    if fee_data.get("status") == "paid":
        return {"error": "Fee is already marked as paid."}, 400

    try:
        fee_ref.update({
            "status":  "paid",
            "paidAt":  firestore.SERVER_TIMESTAMP,
            "paidBy":  "admin_override",
        })
    except Exception as e:
        return {"error": f"Failed to update fee: {str(e)}"}, 500

    # Redirect back to the student page
    student_id = fee_data.get("studentId", "")
    if student_id:
        return redirect(url_for("student_bp.manage_student", student_id=student_id))
    return {"message": "Fee marked as paid."}, 200

# API: list students assigned to a specific bus
@student_bp.route("/admin/students/by-bus/<bus_id>")
@firebase_required(admin=True)
def list_students_by_bus(bus_id):
    db = current_app.config["db"]

    students_ref = db.collection("students").where("bus_id", "==", bus_id).stream()
    students = []
    for doc in students_ref:
        data = doc.to_dict() or {}
        students.append(
            {
                "id": doc.id,
                "name": data.get("name", ""),
                "admission_number": data.get("admission_number", ""),
                "email": data.get("email", ""),
                "photo_path": data.get("photo_path"),
            }
        )

    return jsonify(students)

