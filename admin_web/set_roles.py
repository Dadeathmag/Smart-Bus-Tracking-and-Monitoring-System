import sys

from firebase_admin import auth

from firebase_init import initialize_firebase

# python set_roles.py USER_UID_HERE admin


def set_user_role(uid, role):
    try:
        auth.set_custom_user_claims(uid, {"role": role})
        print(f"Successfully set role '{role}' for UID: {uid}")
    except Exception as e:
        print(f"Error setting role: {e}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage:")
        print("python set_roles.py <USER_UID> <role>")
        print("Example:")
        print("python set_roles.py abc123 admin")
        sys.exit(1)

    uid = sys.argv[1]
    role = sys.argv[2]

    initialize_firebase()
    set_user_role(uid, role)
