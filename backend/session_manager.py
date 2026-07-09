import threading
from typing import Dict

# Thread-safe in-memory session buffers
# Each session stores:
# - "buffer": list of raw [acc_x, acc_y, acc_z, gyro_x, gyro_y, gyro_z]
# - "lock": threading.Lock
# - "last_prediction": dict containing the latest activity and confidence
# - "step_count": int (independent step counter value)
session_stores: Dict[str, dict] = {}
stores_lock = threading.Lock()

def get_session_store(session_id: str) -> dict:
    """Gets or creates the session store in a thread-safe manner."""
    with stores_lock:
        if session_id not in session_stores:
            session_stores[session_id] = {
                "buffer": [],
                "lock": threading.Lock(),
                "step_count": 0,
                "last_prediction": {
                    "status": "collecting",
                    "samples": 0,
                    "required": 128
                }
            }
        return session_stores[session_id]
