from pydantic import BaseModel
from typing import List, Optional

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
