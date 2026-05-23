from datetime import datetime

from firebase_admin import firestore
from flask import current_app



def generate_fees():
    today = datetime.now()
    db = current_app.config["db"]

    if today.month not in [1, 7]:
        return

    # Decide cycle
    if today.month == 1:
        cycle = "JAN"
        due_date = datetime(today.year, 1, 31)
    else:
        cycle = "JULY"
        due_date = datetime(today.year, 7, 31)

    students = db.collection("students").stream()

    for student_doc in students:
        student = student_doc.to_dict()
        student_id = student_doc.id

        # duplicate check
        existing = db.collection("fees") \
            .where("studentId", "==", student_id) \
            .where("cycle", "==", cycle) \
            .where("year", "==", today.year) \
            .get()

        if len(list(existing)) > 0:
            continue

        fee_data = {
            "studentId": student_id,
            "studentName": student.get("name", ""),
            "admissionNumber": student.get("admission_number", ""),
            "busId": student.get("bus_id", ""),
            "amount": student.get("total_fee", 0),
            "dueDate": due_date,
            "cycle": cycle,
            "year": today.year,
            "status": "pending",
            "paidAt": None,
            "paidBy": None,
            "createdAt": firestore.SERVER_TIMESTAMP,
        }

        db.collection("fees").add(fee_data)

    print(f"Fees generated for {cycle} {today.year}")