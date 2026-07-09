from pydantic import BaseModel
from typing import List, Optional, Any, Dict

class Axis(BaseModel):
    x: float
    y: float
    z: float

class SensorReading(BaseModel):
    time: str
    accelerometer: Axis
    gyroscope: Axis

# Single reading packet (for backward compatibility)
class SensorData(BaseModel):
    session: str
    device: str
    time: str
    accelerometer: Axis
    gyroscope: Axis
    step_count: Optional[int] = None

# Batched readings packet (for high-frequency production streaming)
class BatchSensorData(BaseModel):
    session: str
    device: str
    readings: List[SensorReading]
    step_count: Optional[int] = None

# Snapshot of a session's live in-RAM state (unconsumed sliding-window buffer,
# step count, last prediction), used to migrate a session from one edge server
# to another when the client roams to a different network/gateway. The
# session's persisted history is migrated separately as a raw SQLite file via
# GET/POST /session/{id}/database, since that's the data actually mounted at
# /app/data by docker-compose.yml.
class SessionSnapshot(BaseModel):
    session_id: str
    step_count: int = 0
    buffer: List[List[float]] = []
    last_prediction: Dict[str, Any] = {}
