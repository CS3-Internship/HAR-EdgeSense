from fastapi import APIRouter, HTTPException
from models.schemas import SensorData, BatchSensorData
from session_manager import get_session_store
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

