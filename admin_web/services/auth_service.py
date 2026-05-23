from functools import wraps
from flask import request, jsonify
from firebase_admin import auth

def firebase_required(admin=False):
    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            session_cookie = request.cookies.get("session")

            if not session_cookie:
                return jsonify({"error": "Unauthorized"}), 401

            try:
                decoded_token = auth.verify_session_cookie(session_cookie)

                # ✅ Attach user info to request
                request.user = decoded_token
                request.user_role = decoded_token.get("role", "user")

                # ✅ Admin check
                if admin and request.user_role != "admin":
                    return jsonify({"error": "Admin only"}), 403

                return f(*args, **kwargs)

            except Exception:
                return jsonify({"error": "Invalid session"}), 401

        return wrapper
    return decorator