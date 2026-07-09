from fastapi import APIRouter, HTTPException, UploadFile, File
from fastapi.responses import Response
from models.schemas import SensorData, BatchSensorData, SessionSnapshot
from session_manager import get_session_store, export_session_state, import_session_state, clear_session_state
from inference import process_inference_for_session
import database

router = APIRouter()

@router.get("/ping")
def ping():
    return {"message": "Edge Server Reachable"}

@router.get("/predict/{session_id}")
def get_prediction(session_id: str):
    """Allows Flutter UI to poll the latest prediction for a session ID."""
    store = get_session_store(session_id)
    with store["lock"]:
        res = store["last_prediction"].copy()
        res["step_count"] = store.get("step_count", 0)
        return res

@router.get("/session/{session_id}/snapshot")
def get_session_snapshot(session_id: str):
    """
    Exports a session's live in-RAM state (unconsumed sliding-window buffer, step
    count, last prediction) so the client can hand it off to a different edge server
    when it roams to a new network. Called on the OLD edge server before switching.
    The persisted history itself is migrated separately via /session/{id}/database.
    """
    state = export_session_state(session_id)
    return {
        "session_id": session_id,
        "step_count": state["step_count"],
        "buffer": state["buffer"],
        "last_prediction": state["last_prediction"],
    }

@router.post("/session/{session_id}/restore")
def restore_session_snapshot(session_id: str, snapshot: SessionSnapshot):
    """
    Imports a session's in-RAM state produced by another edge server's
    /session/{id}/snapshot, so inference continues uninterrupted. Called on the NEW
    edge server right before the client resumes streaming to it.
    """
    if snapshot.session_id != session_id:
        raise HTTPException(status_code=400, detail="session_id mismatch between path and body")

    import_session_state(
        session_id=session_id,
        buffer=snapshot.buffer,
        step_count=snapshot.step_count,
        last_prediction=snapshot.last_prediction,
    )
    return {"status": "restored", "session_id": session_id, "buffer_samples": len(snapshot.buffer)}

@router.get("/session/{session_id}/database")
def download_session_database(session_id: str):
    """
    Downloads the raw SQLite file backing this session's persisted history — the
    same file that lives under the /app/data volume mount in docker-compose.yml.
    Called on the OLD edge server so the client can carry it over byte-for-byte to
    the new one, rather than replaying rows through the JSON API.
    """
    data = database.get_session_db_bytes(session_id)
    return Response(
        content=data,
        media_type="application/octet-stream",
        headers={"Content-Disposition": f'attachment; filename="session_{session_id}.db"'},
    )

@router.post("/session/{session_id}/database")
async def upload_session_database(session_id: str, file: UploadFile = File(...)):
    """
    Replaces this server's copy of a session's SQLite file with one downloaded from
    another edge server, then mirrors its rows into the local main database so
    session-less aggregate endpoints (e.g. /dashboard) reflect the migrated history.
    Called on the NEW edge server as part of a handoff.
    """
    data = await file.read()
    database.replace_session_db_file(session_id, data)
    database.sync_session_into_main_db(session_id)
    return {"status": "restored", "session_id": session_id, "bytes": len(data)}

@router.delete("/session/{session_id}")
def purge_session(session_id: str):
    """
    Deletes a session's data on this server — its in-RAM buffer/state and its
    persisted SQLite history/rows — after that data has been migrated to another
    edge server. Called on the OLD edge server as the final step of a handoff, so
    a later return visit to this server starts clean instead of finding stale state.
    """
    clear_session_state(session_id)
    database.purge_session(session_id)
    return {"status": "purged", "session_id": session_id}

@router.post("/send")
def receive_data(data: SensorData):
    """Handles single packet data streams (for backward compatibility)."""
    store = get_session_store(data.session)
    with store["lock"]:
        if data.step_count is not None:
            store["step_count"] = data.step_count
            print(f"Session '{data.session}' step count updated to: {data.step_count}")
            
        reading = [
            data.accelerometer.x,
            data.accelerometer.y,
            data.accelerometer.z,
            data.gyroscope.x,
            data.gyroscope.y,
            data.gyroscope.z
        ]
        store["buffer"].append(reading)
        
        result = process_inference_for_session(store, session_id=data.session)
        return result

@router.post("/send_batch")
def receive_batch_data(data: BatchSensorData):
    """Handles batch data packets for high-frequency streaming (production optimized)."""
    store = get_session_store(data.session)
    with store["lock"]:
        if data.step_count is not None:
            store["step_count"] = data.step_count
            print(f"Session '{data.session}' step count updated to: {data.step_count}")
            
        for r in data.readings:
            reading = [
                r.accelerometer.x,
                r.accelerometer.y,
                r.accelerometer.z,
                r.gyroscope.x,
                r.gyroscope.y,
                r.gyroscope.z
            ]
            store["buffer"].append(reading)
        
        result = process_inference_for_session(store, session_id=data.session)
        return result

# Analytics & Dashboard APIs
@router.get("/dashboard")
def get_dashboard(session_id: str = None):
    """Returns aggregated analytics data for the dashboard."""
    return database.get_dashboard_data(session_id=session_id)

@router.get("/history")
def get_history(limit: int = 50, session_id: str = None):
    """Returns recent prediction history."""
    return database.get_history_data(limit=limit, session_id=session_id)

@router.get("/statistics")
def get_statistics(session_id: str = None):
    """Returns key statistical summary of the predictions and steps."""
    return database.get_statistics_data(session_id=session_id)

@router.get("/statistics/{activity}")
def get_activity_stats(activity: str, session_id: str = None):
    """Returns detailed statistics and hourly distribution for a specific activity."""
    return database.get_activity_statistics(activity=activity, session_id=session_id)

@router.get("/dashboard/today")
def get_dashboard_today(session_id: str = None):
    """Returns today's aggregated analytics data for the dashboard."""
    return database.get_today_dashboard_data(session_id=session_id)

@router.get("/statistics/today/{activity}")
def get_today_activity_stats(activity: str, session_id: str = None):
    """Returns today's detailed statistics and hourly distribution for a specific activity."""
    return database.get_today_activity_statistics(activity=activity, session_id=session_id)

