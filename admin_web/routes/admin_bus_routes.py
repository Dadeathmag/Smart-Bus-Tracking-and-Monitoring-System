import base64
import cv2
from flask import Blueprint, jsonify, request, current_app, render_template, url_for,redirect
from services.auth_service import firebase_required
from services.bus_service import (
    create_bus, 
    get_all_buses,
    delete_bus_by_id
)
from firebase_admin import db, firestore, auth
import uuid
from werkzeug.utils import secure_filename
import os

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


bus_bp = Blueprint("bus_bp", __name__)

@bus_bp.route("/admin/buses")
@firebase_required(admin=True)
def bus_home():
    return render_template("bus_home.html")


#<<<--------add--buses------------->>>
@bus_bp.route("/admin/buses/add-bus")
@firebase_required(admin=True)
def add_bus_form():
    return render_template("add_bus.html")

ALLOWED_EXTENSIONS = {"png", "jpg", "jpeg"}
def allowed_file(filename):
    return "." in filename and \
           filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS

#add bus
@bus_bp.route("/admin/buses/add", methods=["POST"])
@firebase_required(admin=True)
def add_bus():
    db = current_app.config["db"]
    rtdb = current_app.config["rtdb"]

    name = request.form.get("name")
    bus_number = request.form.get("bus_number")
    student_limit = request.form.get("student_limit")

    if not name or not bus_number or not student_limit:
        return "Missing required fields", 400

    existing = list(db.collection("buses").where("bus_number", "==", bus_number).stream())
    if existing:
        return f"Bus with bus_number {bus_number} already exists.", 400
    # -------------------------
    # Handle Permit Image Upload
    # -------------------------
    permit_file = request.files.get("permit_photo")

    permit_path = None

    if not allowed_file(permit_file.filename):
        return "Invalid file type", 400

    if permit_file and permit_file.filename != "":
        UPLOAD_FOLDER = os.path.join(
            current_app.root_path,
            "static/uploads/buses"
        )
        os.makedirs(UPLOAD_FOLDER, exist_ok=True)

        original_filename = secure_filename(permit_file.filename)
        unique_name = f"{uuid.uuid4()}_{original_filename}"
        file_path = os.path.join(UPLOAD_FOLDER, unique_name)

        permit_file.save(file_path)

        permit_path = f"/static/uploads/buses/{unique_name}"

        photo_base64 = generate_base64_image(file_path)
    # -------------------------
    # Save Bus Data
    # -------------------------
    bus_data = {
        "name": name,
        "bus_number": bus_number,
        "student_limit": int(student_limit),
        "current_strength": 0,
        "status": "inactive",
        "permit_photo": permit_path,
        "permit_photo_base64": photo_base64,
        "created_at": firestore.SERVER_TIMESTAMP
    }

    bus_id=create_bus(db, bus_data)
    rtdb.child("buses").child(bus_id).set({
        "status": "inactive",
        "last_seen": -1,
        "tracking": {
            "latitude": 0,
            "longitude": 0,
            "speed": 0,
            "last_updated": 0
        },
        "attendance": {}
    })

    return redirect(url_for("bus_bp.bus_home"))




#<<<--------manage--buses------------->>>

@bus_bp.route("/api/buses")
@firebase_required(admin=True)
def api_buses():
    db = current_app.config["db"]
    buses_ref = db.collection("buses").stream()

    buses = []
    for doc in buses_ref:
        data = doc.to_dict()
        
        # Fetch routes subcollection
        routes_data = {}
        routes_ref = db.collection("buses").document(doc.id).collection("routes").stream()
        for route_doc in routes_ref:
            routes_data[route_doc.id] = route_doc.to_dict()
            
        buses.append({
            "id": doc.id,
            "bus_number": data.get("bus_number"),
            "student_limit": data.get("student_limit"),
            "current_strength": data.get("current_strength"),
            "name": data.get("name", ""),
            "routes": routes_data
        })

    return jsonify(buses)


@bus_bp.route("/api/buses/<bus_id>/tracking")
@firebase_required(admin=True)
def api_bus_tracking(bus_id):
    rtdb = current_app.config["rtdb"]

    tracking_ref = rtdb.child("buses").child(str(bus_id)).child("tracking")
    data = tracking_ref.get()

    if not data:
        return jsonify({"error": "Tracking not found"}), 404

    # Attendance is stored under RTDB per-bus.
    attendance_ref = rtdb.child("buses").child(str(bus_id)).child("attendance")
    attendance_data = attendance_ref.get() or {}

    return jsonify(
        {
            "latitude": data.get("latitude", 0),
            "longitude": data.get("longitude", 0),
            "speed": data.get("speed", 0),
            "last_updated": data.get("last_updated", 0),
            "attendance": attendance_data,
        }
    )

@bus_bp.route("/admin/buses/manage")
@firebase_required(admin=True)
def manage_buses():
    db = current_app.config["db"]
    buses = get_all_buses(db)
    return render_template("manage_buses.html", buses=buses)


# -------------------------
# Manage drivers (page + APIs)
# -------------------------
@bus_bp.route("/admin/buses/drivers")
@firebase_required(admin=True)
def manage_drivers_page():
    return render_template("manage_drivers.html")


@bus_bp.route("/admin/drivers/list-all")
@firebase_required(admin=True)
def list_all_drivers():
    db = current_app.config["db"]

    drivers_ref = db.collection("drivers").stream()
    drivers = []
    for doc in drivers_ref:
        data = doc.to_dict() or {}
        assigned_bus_id = data.get("assigned_bus_id")

        assigned_bus_number = ""
        if assigned_bus_id:
            bus_doc = db.collection("buses").document(assigned_bus_id).get()
            if bus_doc.exists:
                bus_data = bus_doc.to_dict() or {}
                assigned_bus_number = bus_data.get("bus_number", "") or ""

        drivers.append(
            {
                "id": doc.id,
                "uid": data.get("uid"),
                "name": data.get("name", ""),
                "phone": data.get("phone", ""),
                "email": data.get("email", ""),
                "status": data.get("status"),
                "assigned_bus_id": assigned_bus_id,
                "assigned_bus_number": assigned_bus_number,
            }
        )

    return jsonify(drivers)


@bus_bp.route("/admin/drivers/delete/<driver_id>", methods=["POST"])
@firebase_required(admin=True)
def delete_driver(driver_id):
    db = current_app.config["db"]

    driver_doc = db.collection("drivers").document(driver_id).get()
    if not driver_doc.exists:
        return jsonify({"error": "Driver not found"}), 404

    driver_data = driver_doc.to_dict() or {}

    # If this driver is assigned, clear the bus assignment.
    bus_id = driver_data.get("assigned_bus_id")
    if bus_id:
        db.collection("buses").document(bus_id).update(
            {"assigned_driver_id": None}
        )

    uid = driver_data.get("uid")

    # Delete Firestore doc first.
    db.collection("drivers").document(driver_id).delete()

    # Then delete Firebase Auth user.
    if uid:
        try:
            auth.delete_user(uid)
        except Exception:
            # Don't fail deletion if auth user was already removed.
            pass

    return jsonify({"message": "Driver deleted successfully"})


@bus_bp.route("/admin/buses/delete/<bus_id>", methods=["POST"])
@firebase_required(admin=True)
def delete_bus_route(bus_id):
    db = current_app.config["db"]
    rtdb = current_app.config["rtdb"]
    
    bus_doc = db.collection("buses").document(bus_id).get()

    if bus_doc.exists:
        bus_data = bus_doc.to_dict()

        permit_path = bus_data.get("permit_photo")
        if permit_path:
            file_path = os.path.join(
                current_app.root_path,
                permit_path.lstrip("/")
            )
            if os.path.exists(file_path):
                os.remove(file_path)

        db.collection("buses").document(bus_id).delete()
        rtdb.child("buses").child(bus_id).delete()

    return redirect(url_for("bus_bp.manage_buses"))


@bus_bp.route("/admin/buses/manage/<bus_id>")
@firebase_required(admin=True)
def view_bus(bus_id):
    db = current_app.config["db"]

    doc = db.collection("buses").document(bus_id).get()

    if not doc.exists:
        return "Bus not found", 404

    bus = doc.to_dict()
    bus["id"] = doc.id

    # 🔽 Fetch assigned driver
    assigned_driver_name = None

    driver_id = bus.get("assigned_driver_id")
    if driver_id:
        driver_doc = db.collection("drivers").document(driver_id).get()
        if driver_doc.exists:
            assigned_driver_name = driver_doc.to_dict().get("name")

    bus["assigned_driver_name"] = assigned_driver_name
    # Center maps on configured college location.
    college_lat = 12.9716
    college_lng = 77.5946
    try:
        college_doc = db.collection("config").document("college_location").get()
        if college_doc.exists:
            data = college_doc.to_dict() or {}
            # stored values might be floats or strings
            college_lat = float(data.get("latitude", college_lat))
            college_lng = float(data.get("longitude", college_lng))
    except Exception:
        # Keep defaults if config read fails
        pass

    return render_template(
        "bus_detail.html",
        bus=bus,
        college_lat=college_lat,
        college_lng=college_lng,
    )


@bus_bp.route("/admin/buses/update/<bus_id>", methods=["POST"])
@firebase_required(admin=True)
def update_bus_route(bus_id):
    db = current_app.config["db"]

    name = request.form.get("name")
    bus_number = request.form.get("bus_number")
    student_limit = request.form.get("student_limit")

    permit_file = request.files.get("permit_photo")

    bus_ref = db.collection("buses").document(bus_id)
    bus_doc = bus_ref.get()

    if not bus_doc.exists:
        return "Bus not found", 404

    bus_data = bus_doc.to_dict()
    update_data = {
        "name": name,
        "bus_number": bus_number,
        "student_limit": int(student_limit),
    }

    # -------------------------
    # If new permit uploaded
    # -------------------------
    if permit_file and permit_file.filename != "":

        UPLOAD_FOLDER = os.path.join(
            current_app.root_path,
            "static/uploads/buses"
        )
        os.makedirs(UPLOAD_FOLDER, exist_ok=True)

        #  Delete old permit
        old_permit = bus_data.get("permit_photo")
        if old_permit:
            old_path = os.path.join(
                current_app.root_path,
                old_permit.lstrip("/")
            )
            if os.path.exists(old_path):
                os.remove(old_path)

        #  Save new permit
        original_filename = secure_filename(permit_file.filename)
        unique_name = f"{uuid.uuid4()}_{original_filename}"
        file_path = os.path.join(UPLOAD_FOLDER, unique_name)

        permit_file.save(file_path)
        photo_base64 = generate_base64_image(file_path)
        
        update_data["permit_photo_base64"] = photo_base64
        update_data["permit_photo"] = f"/static/uploads/buses/{unique_name}"

    bus_ref.update(update_data)

    return redirect(url_for("bus_bp.manage_buses"))




@bus_bp.route("/admin/buses/manage/<bus_id>/save-route", methods=["POST"])
@firebase_required(admin=True)
def save_route(bus_id):
    db = current_app.config["db"]

    # Check bus exists
    bus_doc = db.collection("buses").document(bus_id).get()
    if not bus_doc.exists:
        return jsonify({"error": "Bus not found"}), 404

    data = request.get_json()
    route_type = data.get("type")
    stops = data.get("stops")

    if route_type not in ["morning", "evening"]:
        return jsonify({"error": "Invalid route type"}), 400

    if not isinstance(stops, list):
        return jsonify({"error": "Stops must be a list"}), 400

    route_ref = (
        db.collection("buses")
        .document(bus_id)
        .collection("routes")
        .document(route_type)
    )

    route_ref.set({
        "stops": stops
    })

    return jsonify({"message": "Route saved successfully"})


@bus_bp.route("/admin/buses/manage/<bus_id>/get-route/<route_type>")
@firebase_required(admin=True)
def get_route(bus_id, route_type):
    db = current_app.config["db"]

    route_doc = (
        db.collection("buses")
        .document(bus_id)
        .collection("routes")
        .document(route_type)
        .get()
    )

    if not route_doc.exists:
        return jsonify({"stops": []})

    route_data = route_doc.to_dict()

    return jsonify({"stops": route_data.get("stops", [])})

@bus_bp.route("/admin/drivers/list")
@firebase_required(admin=True)
def list_drivers():
    db = current_app.config["db"]

    drivers_ref = (
        db.collection("drivers")
        .where("status", "==", "available")
        .stream()
    )

    drivers = []
    for doc in drivers_ref:
        data = doc.to_dict()
        data["id"] = doc.id
        drivers.append(data)

    return jsonify(drivers)

@bus_bp.route("/admin/drivers/add", methods=["POST"])
@firebase_required(admin=True)
def add_driver():
    db = current_app.config["db"]

    data = request.get_json()
    if not data:
        return jsonify({"error": "Missing JSON body"}), 400

    name = data.get("name")
    phone = data.get("phone")
    email = data.get("email")
    password = data.get("password")

    if not name or not phone or not email or not password:
        return jsonify({"error": "Missing fields"}), 400

    # Create Firebase Auth user first.
    try:
        user = auth.create_user(
            email=email,
            password=password,
        )
        uid = user.uid
    except Exception as e:
        return jsonify({"error": f"Firebase Auth Error: {str(e)}"}), 400

    # Set custom claim so firebase_required(admin=False) can recognize role.
    try:
        auth.set_custom_user_claims(uid, {"role": "driver"})
    except Exception as e:
        # If claims fail, don't lose the driver account; just report.
        return jsonify({"error": f"Failed to set driver role claims: {str(e)}"}), 500

    # Store driver record in Firestore.
    driver_ref = db.collection("drivers").add({
        "uid": uid,
        "name": name,
        "phone": phone,
        "email": email,
        "status": "available",
        "assigned_bus_id": None
    })

    return jsonify({"message": "Driver added successfully"})

@bus_bp.route("/admin/buses/manage/<bus_id>/assign-driver", methods=["POST"])
@firebase_required(admin=True)
def assign_driver(bus_id):
    db = current_app.config["db"]
    data = request.get_json()
    driver_id = data.get("driver_id")

    if not driver_id:
        return jsonify({"error": "Driver ID required"}), 400

    bus_ref = db.collection("buses").document(bus_id)
    driver_ref = db.collection("drivers").document(driver_id)

    bus_doc = bus_ref.get()
    bus_data = bus_doc.to_dict()

    old_driver_id = bus_data.get("assigned_driver_id")

    if old_driver_id:
        db.collection("drivers").document(old_driver_id).update({
            "status": "available",
            "assigned_bus_id": None
        })

    driver_doc = driver_ref.get()

    if not driver_doc.exists:
        return jsonify({"error": "Driver not found"}), 404

    driver_data = driver_doc.to_dict()

    # Safety check
    if driver_data.get("status") != "available":
        return jsonify({"error": "Driver not available"}), 400

    # Assign
    driver_ref.update({
        "status": "assigned",
        "assigned_bus_id": bus_id
    })

    bus_ref.update({
        "assigned_driver_id": driver_id
    })

    return jsonify({"message": "Driver assigned successfully"})

@bus_bp.route("/admin/buses/manage/<bus_id>/unassign-driver", methods=["POST"])
@firebase_required(admin=True)
def unassign_driver(bus_id):
    db = current_app.config["db"]

    bus_ref = db.collection("buses").document(bus_id)
    bus_doc = bus_ref.get()

    if not bus_doc.exists:
        return jsonify({"error": "Bus not found"}), 404

    bus_data = bus_doc.to_dict()
    driver_id = bus_data.get("assigned_driver_id")

    if not driver_id:
        return jsonify({"error": "No driver assigned"}), 400

    driver_ref = db.collection("drivers").document(driver_id)

    # Make driver available again
    driver_ref.update({
        "status": "available",
        "assigned_bus_id": None
    })

    # Remove driver from bus
    bus_ref.update({
        "assigned_driver_id": None
    })

    return jsonify({"message": "Driver unassigned successfully"})