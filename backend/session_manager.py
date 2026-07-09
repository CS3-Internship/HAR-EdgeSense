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


def export_session_state(session_id: str) -> dict:
    """
    Snapshots the in-RAM state of a session (unconsumed sliding-window buffer,
    step count, last prediction) so it can be handed off to another edge server
    when the client roams to a different network.
    """
    store = get_session_store(session_id)
    with store["lock"]:
        return {
            "buffer": [list(reading) for reading in store["buffer"]],
            "step_count": store.get("step_count", 0),
            "last_prediction": dict(store.get("last_prediction", {})),
        }


def import_session_state(session_id: str, buffer, step_count: int, last_prediction: dict) -> None:
    """Restores a session's in-RAM state from a snapshot produced by another edge server."""
    store = get_session_store(session_id)
    with store["lock"]:
        store["buffer"] = [list(reading) for reading in buffer]
        store["step_count"] = step_count
        if last_prediction:
            store["last_prediction"] = dict(last_prediction)


def clear_session_state(session_id: str) -> None:
    """
    Removes a session's in-RAM store entirely, e.g. once its data has been
    migrated to another edge server. A later request for the same session_id
    (should the client ever roam back to this server) starts a brand-new store
    instead of finding leftover buffer/step-count state from before it left.
    """
    with stores_lock:
        session_stores.pop(session_id, None)
