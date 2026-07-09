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

## Multi-Edge-Server Handover

In a deployment with multiple edge servers (one per physical location/gateway, e.g. each running the `docker-compose.yml` container over its own hotspot), a session must migrate when its phone roams from one edge server's network to another's — otherwise the new server starts with an empty in-RAM buffer and an empty `data/` volume, breaking inference and losing history.

Since the OS decides which Wi-Fi AP the phone associates with (the app can't force that choice), the client — not the server — drives the migration. It runs a small fuzzy-logic controller (`frontend/lib/services/handover_controller.dart` + `fuzzy_handover.dart`) that fuzzifies Wi-Fi RSSI and request latency into an "urgency" score (0–100) via a Sugeno-style rule base. That score is used to:

1. **Predictively cache** a snapshot and a copy of the session database from the current server once urgency crosses a threshold, so they're already in hand if the connection dies before a network change is even detected.
2. **Detect a gateway/network change** (the phone associated with a different edge server's AP) and migrate: pull the session's live state and its SQLite file from the old server if it's still reachable (falling back to the predictive cache if not), push both to the new server, then switch the app's active server URL.
3. **Purge the old server** once the new one confirms it has the data — so if the phone ever roams back to a server it already left, it starts clean instead of finding (and potentially conflicting with) stale pre-handoff history.
4. **Surface a "signal weak" status** in the UI when no alternate edge server is visible on the current network — there's nothing to hand off to, so the app just warns instead of guessing.

Two things move on a handoff, via five endpoints (see below):

* **In-RAM state** (unconsumed sliding-window buffer, step count, last prediction) — `GET/POST /session/{id}/snapshot|restore`, JSON. This is what lets inference keep running without a cold start.
* **Persisted history** — the actual SQLite file the session lives in, `data/sessions/session_{id}.db`, which is exactly what `docker-compose.yml` mounts at `/app/data`. `GET/POST /session/{id}/database` downloads/uploads that file whole (as raw bytes), so history migrates byte-for-byte rather than being replayed row by row. On upload, the new server also mirrors those rows into its own main `har_metrics.db` so session-less aggregate endpoints (like `/dashboard`) pick them up too.

Once both of the above have landed on the new server, the client calls `DELETE /session/{id}` on the old one — dropping its dedicated SQLite file, its rows in `har_metrics.db`, and its in-RAM store. This purge only fires after a confirmed successful migration, never on a failed handoff (there'd be nowhere else the data exists), and it's best-effort: if the old server is already unreachable — usually the very reason the phone roamed — there's nothing to clean up there anyway.

Each edge server otherwise still keeps its own independent database files; a handoff explicitly carries one session's data forward (and cleans up behind it) rather than centralizing storage across servers.

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

### 2. Session Handoff — In-RAM Snapshot Export
* **Route**: `GET /session/{session_id}/snapshot`
* **Description**: Exports a session's live in-RAM state (unconsumed sliding-window buffer, step count, last prediction) so the client can migrate the session to a different edge server. Used when the phone roams to a new network/gateway and the old edge server is no longer reachable. See [Multi-Edge-Server Handover](#multi-edge-server-handover) below.
* **Example JSON Response**:
  ```json
  {
    "session_id": "test-session-123",
    "step_count": 35,
    "buffer": [[0.02, 9.78, -0.1, 0.0, 0.0, 0.0]],
    "last_prediction": { "status": "predicted", "activity": "Walking", "confidence": 0.932 }
  }
  ```

### 3. Session Handoff — In-RAM Snapshot Restore
* **Route**: `POST /session/{session_id}/restore`
* **Description**: Imports a snapshot produced by `/session/{session_id}/snapshot` on another edge server, so inference continues uninterrupted on the new server without a cold start.
* **Example JSON Request**: Same shape as the snapshot response above.
* **Example JSON Response**:
  ```json
  {
    "status": "restored",
    "session_id": "test-session-123",
    "buffer_samples": 42
  }
  ```

### 4. Session Handoff — Database Download
* **Route**: `GET /session/{session_id}/database`
* **Description**: Downloads the raw SQLite file backing this session's persisted history (`data/sessions/session_{session_id}.db` — the same file mounted at `/app/data` by `docker-compose.yml`), as `application/octet-stream`. Called on the OLD edge server so the client can carry the file to the new one byte-for-byte.

### 5. Session Handoff — Database Upload
* **Route**: `POST /session/{session_id}/database`
* **Description**: Accepts a `multipart/form-data` file upload (field name `file`) and overwrites this server's copy of the session's SQLite file with it, then mirrors its rows into the local `har_metrics.db` so session-less endpoints (like `/dashboard`) reflect the migrated history too. Called on the NEW edge server as the last step of a handoff. Skips the main-database mirroring if rows for this session already exist there (idempotent against retried uploads).
* **Example JSON Response**:
  ```json
  {
    "status": "restored",
    "session_id": "test-session-123",
    "bytes": 20480
  }
  ```

### 6. Session Handoff — Purge
* **Route**: `DELETE /session/{session_id}`
* **Description**: Deletes this session's data on this server — its in-RAM buffer/state and its dedicated SQLite file, plus its rows in `har_metrics.db`. Called on the OLD edge server as the final step of a handoff, once the client has confirmed the session actually landed on the new server. This prevents a subtle problem: if the phone later roams back to this same edge server, it starts completely clean instead of finding stale pre-handoff history that could conflict with (or be silently skipped by) the idempotency check in `sync_session_into_main_db`.
* **Example JSON Response**:
  ```json
  {
    "status": "purged",
    "session_id": "test-session-123"
  }
  ```

### 7. Polling Prediction
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

### 8. Send Single Sensor Data Packet
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

### 9. Send Batched Sensor Data Packet (Production Optimized)
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

### 10. Get Analytics Dashboard Data
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

### 11. Get Prediction History Logs
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

### 12. Get General Statistics
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

### 13. Get Activity-Specific Statistics
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
