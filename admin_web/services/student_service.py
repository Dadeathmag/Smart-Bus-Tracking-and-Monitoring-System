

def create_student(db, data):
    doc_ref = db.collection("students").document()
    doc_ref.set(data)
    return doc_ref.id


def get_all_students(db):
    students = db.collection("students").stream()
    return [(doc.id, doc.to_dict()) for doc in students]


def delete_student_by_id(db, student_id):
    db.collection("students").document(student_id).delete()