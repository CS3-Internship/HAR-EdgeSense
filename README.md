# EdgeSense — Real-Time Human Activity Recognition

EdgeSense is an end-to-end Human Activity Recognition (HAR) system that classifies a user's physical activity — **Walking, Walking Upstairs, Walking Downstairs, Sitting, Standing, Laying** — in real time from a phone's accelerometer and gyroscope. A Flutter mobile app streams live sensor data to a FastAPI edge server, which runs a trained LSTM model and returns predictions, step counts, and analytics back to the app.

The project has three parts:

| Component | Description |
| :--- | :--- |
| [`frontend/`](frontend) | Flutter app that reads on-device sensors, streams data to the server, and displays live predictions, step counts, and analytics dashboards. |
| [`backend/`](backend) | FastAPI edge server that buffers streamed readings into sliding windows, runs LSTM inference, and persists results to SQLite. |
| [`frontend/ml_pipeline/`](frontend/ml_pipeline) | Python training pipeline that builds and evaluates the LSTM model on the UCI HAR dataset, producing the `.keras` model and `StandardScaler` used by the backend. |
'
---

## How It Works

```
   ┌────────────────────┐   accelerometer + gyroscope   ┌───────────────────────────┐
   │  Flutter Mobile App │ ─────────────────────────────▶│    FastAPI Edge Server    │
   │  (frontend/)         │◀───────────────────────────── │      (backend/)           │
   └────────────────────┘   activity, confidence, steps  └─────────────┬─────────────┘
                                                                        │
                                                  ┌─────────────────────┴─────────────────────┐
                                                  ▼                                             ▼
                                     ┌───────────────────────┐                     ┌───────────────────────┐
                                     │  In-memory session    │                     │  SQLite database      │
                                     │  buffers (sliding      │                     │  (prediction history, │
                                     │  128-sample windows)  │                     │  used by dashboard)    │
                                     └───────────┬───────────┘                     └───────────────────────┘
                                                 ▼
                                     ┌───────────────────────┐
                                     │  StandardScaler +      │
                                     │  LSTM inference        │
                                     │  (trained via           │
                                     │  ml_pipeline/)          │
                                     └───────────────────────┘
```

1. The **Flutter app** collects live accelerometer/gyroscope samples (via `sensors_plus`) and a foreground service, and streams them in batches to the edge server over HTTP.
2. The **FastAPI server** buffers samples per session ID until it has a 128-sample window (2.56s at 50Hz), preprocesses it to match the training format, scales it, and runs it through the LSTM model.
3. The prediction (activity, confidence, step count) is sent back to the app and logged to SQLite for the analytics dashboard (activity breakdown, hourly distribution, history, statistics).
4. The **ML pipeline** is what produced the model and scaler in the first place, trained on the [UCI HAR dataset](dataset).

---

## Repository Structure

```
HAR EdgeSense/
├── backend/               FastAPI edge server (real-time inference + analytics API)
│   ├── app.py             App entrypoint — loads model/scaler, initializes DB
│   ├── routes.py          API endpoints (/send, /send_batch, /predict, /dashboard, ...)
│   ├── database.py        SQLite schema, inserts, analytics queries
│   ├── inference.py       Model loading + prediction logic
│   ├── session_manager.py Thread-safe in-RAM per-session sliding-window buffers
│   ├── preprocessing.py   Converts raw sensor readings to the trained model's input format
│   ├── config.py          Model/scaler paths, activity label mapping
│   ├── models/            best_model.keras, scaler.pkl
│   ├── data/               har_metrics.db (SQLite) + session data
│   ├── Dockerfile / docker-compose.yml
│   └── README.md           Full API reference & DB schema
│
├── frontend/               Flutter mobile app (Android/iOS/desktop/web)
│   ├── lib/
│   │   ├── screens/        Session entry, home/live monitoring, dashboard, activity detail
│   │   ├── widgets/        Prediction, sensor, step, connection, network-info cards, pie chart
│   │   ├── services/       Foreground task handler, fuzzy-logic handover controller, Wi-Fi RSSI channel
│   │   ├── config/         Server URL config + network discovery
│   │   └── main.dart
│   ├── ml_pipeline/         Model training pipeline (see below)
│   └── README.md
│
└── dataset/                 UCI HAR Dataset (raw + preprocessed inertial signals used for training)
    ├── train/, test/          Feature vectors, labels, and raw inertial signals
    ├── features.txt, activity_labels.txt
    └── README.md
```

---

## Machine Learning Model

* **Architecture**: Stacked LSTM — `LSTM(64, return_sequences=True) → Dropout(0.5) → LSTM(64) → Dropout(0.5) → Dense(6, softmax)`
* **Input**: 128-sample windows × 6 channels (3-axis accelerometer + 3-axis gyroscope), 50Hz, 50% window overlap
* **Training data**: [UCI HAR Dataset](dataset/README.md) — 30 subjects, 6 activities, waist-mounted smartphone
* **Results**: ~91% test accuracy, precision, recall, and F1-score on the held-out UCI HAR test set
* **Pipeline** ([`frontend/ml_pipeline/`](frontend/ml_pipeline)): `data_loader.py` (loads/standardizes signals) → `model.py` (architecture) → `train.py` (training, early stopping, checkpointing) → `evaluate.py` (test metrics, confusion matrix)

See [`frontend/walkthrough.md`](frontend/walkthrough.md) for the full training write-up, and [`backend/README.md`](backend/README.md#architecture-overview) for how the model is served in production.

---

## Multi-Edge-Server Handover

EdgeSense supports deploying the backend on **multiple edge servers**, each its own Docker container (e.g. one per hotspot/location). Each keeps its own `./data` volume — the SQLite history and in-RAM buffer for a session live wherever that session started. When a phone roams onto a different edge server's network, that session would normally break: the new container's `./data` is empty and its buffer starts cold.

To keep the session alive, the Flutter app runs a small **fuzzy-logic handover controller** that fuzzifies Wi-Fi signal strength (RSSI) and request latency into an urgency score, and uses it to migrate the session to the new edge server the moment a network change is detected — pre-fetching everything ahead of time once the connection looks like it's degrading, so there's minimal gap in inference. Two things move on handoff: the small in-RAM state (buffer/step count/last prediction) via a JSON snapshot API, and the session's **actual SQLite file** from `./data/sessions/` — downloaded whole from the old container and uploaded whole into the new container's `./data` volume, so history moves byte-for-byte rather than being replayed row by row. See [`backend/README.md#multi-edge-server-handover`](backend/README.md#multi-edge-server-handover) for the full design and the four `/session/{id}/...` endpoints, and [`frontend/lib/services/handover_controller.dart`](frontend/lib/services/handover_controller.dart) / [`fuzzy_handover.dart`](frontend/lib/services/fuzzy_handover.dart) for the client-side logic.

---

## Getting Started

### 1. Run the backend

```bash
cd backend
pip install -r requirements.txt
uvicorn app:app --host 0.0.0.0 --port 5000
```

Or with Docker:

```bash
cd backend
docker compose up --build
```

The server exposes `GET /ping` to verify it's reachable, plus streaming and analytics endpoints documented in [`backend/README.md`](backend/README.md).

Deploy one of these per edge server/hotspot location. Each is fully independent — there's no central cloud component; the phone talks to whichever edge server it's currently connected to, and the [handover mechanism](#multi-edge-server-handover) above carries a session between them.

### 2. Get the app

**Download a build**: grab the latest APK from this repo's [Releases page](../../releases) and install it directly (no Play Store needed). A new release is published automatically whenever a version tag is pushed — see [`frontend/README.md#downloading-a-build`](frontend/README.md#downloading-a-build) for how that works and its signing caveat.

**Or run from source**:

```bash
cd frontend
flutter pub get
flutter run
```

On first launch, enter a Session ID and point the app at your backend's address (see [`frontend/lib/config/network_config.dart`](frontend/lib/config/network_config.dart)) — the phone and server must be reachable on the same network.

### 3. (Optional) Retrain the model

```bash
cd frontend/ml_pipeline
python train.py
python evaluate.py
```

Trained artifacts (`best_model.keras`, `scaler.pkl`) land in `ml_pipeline/output/` — copy them into `backend/models/` to deploy an updated model.

---

## Further Reading

* [`backend/README.md`](backend/README.md) — full API reference, request/response examples, and database schema
* [`frontend/README.md`](frontend/README.md) — Flutter project setup
* [`frontend/walkthrough.md`](frontend/walkthrough.md) — model design, training curves, and evaluation report
* [`dataset/README.md`](dataset/README.md) — UCI HAR Dataset description and citation
