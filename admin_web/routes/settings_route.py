from flask import Blueprint, jsonify, request, current_app, render_template
from services.auth_service import firebase_required

settings_bp = Blueprint("settings_bp", __name__)

@settings_bp.route("/admin/settings/college-location", methods=["GET", "POST"])
@firebase_required(admin=True)
def set_college_location():
    db = current_app.config["db"]

    if request.method == "POST":
        name = request.form.get("name")
        lat = request.form.get("latitude")
        lng = request.form.get("longitude")

        if not name or not lat or not lng:
            # Return the page directly to avoid an extra follow-up request.
            return render_template("config.html", college={"name": name or ""})

        try:
            latitude = float(lat)
            longitude = float(lng)
        except ValueError:
            # Return the page directly to avoid an extra follow-up request.
            return render_template("config.html", college={"name": name or ""})

        db.collection("config").document("college_location").set({
            "name": name,
            "latitude": latitude,
            "longitude": longitude
        })

        # Important: do not redirect here. Redirect causes a second request to the
        # same route, which can fail session verification even after the write
        # succeeded (hence the "Invalid session" response while Firebase updates).
        return render_template(
            "config.html",
            college={"name": name, "latitude": latitude, "longitude": longitude},
        )

    # GET
    doc = db.collection("config").document("college_location").get()
    college = doc.to_dict() if doc.exists else {}

    return render_template("config.html", college=college)



@settings_bp.route("/api/college-location")
@firebase_required(admin=True)
def get_college_location():
    db = current_app.config["db"]

    doc = db.collection("config").document("college_location").get()

    if doc.exists:
        return jsonify(doc.to_dict())
    
    return jsonify({})