def create_bus(db, data):
    doc_ref = db.collection("buses").document()
    doc_ref.set(data)
    return doc_ref.id

def get_all_buses(db):
    buses = db.collection("buses").stream()
    return [(doc.id, doc.to_dict()) for doc in buses]


def delete_bus_by_id(db, bus_id):
    db.collection("buses").document(bus_id).delete()