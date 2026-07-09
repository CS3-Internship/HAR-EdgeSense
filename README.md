# EdgeSense HAR Server

The EdgeSense HAR (Human Activity Recognition) Edge Server is a production-style, modular FastAPI backend that runs real-time LSTM machine learning inference on streamed triaxial accelerometer and gyroscope data. It persists prediction history in SQLite and exposes analytical APIs and a web dashboard.

---

## Architecture Overview

```
                          ┌───────────────────────────┐
                          │   Flutter Mobile Client   │
                          └─────────────┬─────────────┘
                                        │ (Send Batch / Send Data)
                                        ▼
                          ┌───────────────────────────┐
                          │    FastAPI Edge Server    │
                          └─────────────┬─────────────┘
                                        │
                 ┌──────────────────────┴──────────────────────┐
                 ▼                                             ▼
     ┌───────────────────────┐                     ┌───────────────────────┐
     │   In-Memory Session   │                     │  SQLite Database      │
     │   Buffers (in RAM)    │                     │  (Prediction History) │
     └───────────┬───────────┘                     └───────────────────────┘
                 │ (128 Window Samples)
                 ▼
     ┌───────────────────────┐
     │   StandardScaler &    │
     │   LSTM Inference      │
     └───────────────────────┘
```

1. **In-Memory Buffering**: Raw sensor readings are streamed from the client and held in high-speed thread-safe RAM buffers per session ID to construct sliding windows.
2. **Preprocessing**: Once a session buffer accumulates 128 samples, we align the dominant gravity axis to the X-axis, scale the triaxial signals using a pre-trained `StandardScaler`, and apply a 50% overlap sliding window mechanism.
3. **ML Inference**: A pre-trained LSTM Keras model (`.keras`) runs thread-safe inference to predict the user's activity.
4. **SQLite Persistence**: Inference results are logged to an SQLite database (`har_metrics.db`) along with the local timestamp, session ID, activity classification, confidence level, and step counts.
5. **Analytics Engine**: The server aggregates metrics, hourly density distributions, and activity percentages, exposing them via JSON APIs and a real-time web dashboard.

---

## Code Directory Structure

* `app.py`: FastAPI server entrypoint. Runs database initialization and loads ML assets on startup.
* `routes.py`: Contains API routers and GET/POST handlers (including the web dashboard).
* `database.py`: Manages SQLite schemas, insert operations, and analytics queries.
* `inference.py`: Handles model predictions, scaling, and database logging.
* `session_manager.py`: Thread-safe RAM buffers for incoming real-time streams.
* `preprocessing.py`: Conversion of sensor readings to the UCI HAR format.
* `config.py`: Scaler and Keras model path variables, along with activity label indices.

---

## Database Schema

Database: `har_metrics.db`  
Table: `predictions`

| Column | Type | Description |
| :--- | :--- | :--- |
| `id` | `INTEGER` | Primary Key, Auto-incremented ID |
| `timestamp` | `DATETIME` | Date and time (local) of prediction: `YYYY-MM-DD HH:MM:SS` |
| `session_id` | `TEXT` | Unique identifier representing the streaming device session |
| `activity` | `TEXT` | Predicted activity name (`Walking`, `Sitting`, `Laying`, `Standing`, etc.) |
| `confidence` | `REAL` | Model classification confidence (float between `0.0` and `1.0`) |
| `step_count` | `INTEGER` | Step count accumulated during the prediction frame |

---

## API Endpoints Reference

### 1. Ping Check
* **Route**: `GET /ping`
* **Description**: Verifies server reachability.
* **Example JSON Response**:
  ```json
  {
    "message": "Edge Server Reachable"
  }
  ```

### 2. Polling Prediction
* **Route**: `GET /predict/{session_id}`
* **Description**: Polls the last calculated prediction for a specific session ID from active RAM.
* **Example JSON Response**:
  ```json
  {
    "status": "predicted",
    "activity": "Sitting",
    "confidence": 0.985,
    "step_count": 42
  }
  ```

### 3. Send Single Sensor Data Packet
* **Route**: `POST /send`
* **Description**: Handles a single data point stream (primarily for backward compatibility).
* **Example JSON Request**:
  ```json
  {
    "session": "test-session-123",
    "device": "EdgeSense",
    "time": "2026-07-02T15:30:00",
    "accelerometer": { "x": 0.043, "y": 9.801, "z": -0.112 },
    "gyroscope": { "x": 0.001, "y": -0.003, "z": 0.002 },
    "step_count": 12
  }
  ```
* **Example JSON Response** (if collecting samples):
  ```json
  {
    "status": "collecting",
    "samples": 65,
    "required": 128,
    "step_count": 12
  }
  ```
* **Example JSON Response** (if inference executed):
  ```json
  {
    "status": "predicted",
    "activity": "Standing",
    "confidence": 0.994,
    "step_count": 12
  }
  ```

### 4. Send Batched Sensor Data Packet (Production Optimized)
* **Route**: `POST /send_batch`
* **Description**: Streams a batch of sensor readings.
* **Example JSON Request**:
  ```json
  {
    "session": "test-session-123",
    "device": "EdgeSense",
    "step_count": 35,
    "readings": [
      {
        "time": "2026-07-02T15:30:00",
        "accelerometer": { "x": 0.02, "y": 9.78, "z": -0.1 },
        "gyroscope": { "x": 0.0, "y": 0.0, "z": 0.0 }
      },
      {
        "time": "2026-07-02T15:30:01",
        "accelerometer": { "x": 0.05, "y": 9.82, "z": -0.12 },
        "gyroscope": { "x": 0.01, "y": -0.01, "z": 0.0 }
      }
    ]
  }
  ```
* **Example JSON Response**:
  ```json
  {
    "status": "predicted",
    "activity": "Walking",
    "confidence": 0.932,
    "step_count": 35
  }
  ```

### 5. Get Analytics Dashboard Data
* **Route**: `GET /dashboard`
* **Description**: Provides aggregated analytics metrics from the SQLite database for UI visualization.
* **Example JSON Response**:
  ```json
  {
    "activity_counts": {
      "Walking": 34,
      "Walking Upstairs": 12,
      "Walking Downstairs": 8,
      "Sitting": 20,
      "Standing": 45,
      "Laying": 30
    },
    "activity_percentages": {
      "Walking": 0.228,
      "Walking Upstairs": 0.081,
      "Walking Downstairs": 0.054,
      "Sitting": 0.134,
      "Standing": 0.302,
      "Laying": 0.201
    },
    "hourly_activity_distribution": {
      "00": 0, "01": 0, "02": 0, "03": 0, "04": 0, "05": 0,
      "06": 4, "07": 12, "08": 30, "09": 15, "10": 0, "11": 0,
      "12": 24, "13": 18, "14": 42, "15": 4, "16": 0, "17": 0,
      "18": 0, "19": 0, "20": 0, "21": 0, "22": 0, "23": 0
    },
    "recent_predictions": [
      {
        "timestamp": "2026-07-02 15:30:21",
        "time": "15:30:21",
        "activity": "Walking",
        "confidence": 0.942
      }
    ],
    "total_predictions": 149
  }
  ```

### 6. Get Prediction History Logs
* **Route**: `GET /history`
* **Description**: Retrieves a sequence of predictions.
* **Parameters**: `limit` (Optional, Default: `50`)
* **Example JSON Response**:
  ```json
  [
    {
      "timestamp": "2026-07-02 15:30:21",
      "time": "15:30:21",
      "session_id": "test-session-123",
      "activity": "Walking",
      "confidence": 0.942,
      "step_count": 35
    }
  ]
  ```

### 7. Get General Statistics
* **Route**: `GET /statistics`
* **Description**: Calculates high-level summary statistics.
* **Example JSON Response**:
  ```json
  {
    "total_predictions": 149,
    "average_confidence": 0.884,
    "most_active_hour": "14:00",
    "most_common_activity": "Standing",
    "total_steps": 245
  }
  ```

### 8. Get Activity-Specific Statistics
* **Route**: `GET /statistics/{activity}`
* **Description**: Computes total duration and hourly distribution for a single activity.
* **Example JSON Response** (`GET /statistics/Walking`):
  ```json
  {
    "activity": "Walking",
    "count": 34,
    "duration_seconds": 87,
    "duration_string": "1m 27s",
    "hourly_distribution": {
      "00": 0, "01": 0, "02": 0, "03": 0, "04": 0, "05": 0,
      "06": 2, "07": 4, "08": 10, "09": 5, "10": 0, "11": 0,
      "12": 6, "13": 2, "14": 5, "15": 0, "16": 0, "17": 0,
      "18": 0, "19": 0, "20": 0, "21": 0, "22": 0, "23": 0
    }
  }
  ```
