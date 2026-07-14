import sqlite3
import os
import json
from collections import Counter
from datetime import datetime
from config import ACTIVITY_LABELS

# ── Paths ─────────────────────────────────────────────────────────────────────
# Main database path

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

DATA_DIR = os.path.join(BASE_DIR, "data")

DB_PATH = os.path.join(DATA_DIR, "har_metrics.db")
SESSIONS_DIR = os.path.join(DATA_DIR, "sessions")


# ── Connection helpers ─────────────────────────────────────────────────────────

def get_connection():
    """Opens a connection to the main database."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def get_session_json_path(session_id: str) -> str:
    """Returns the absolute path for a session's dedicated history file."""
    return os.path.join(SESSIONS_DIR, f"session_{session_id}.json")


def init_session_file(session_id: str):
    """Ensures a session's JSON history file exists."""
    os.makedirs(SESSIONS_DIR, exist_ok=True)
    path = get_session_json_path(session_id)
    if not os.path.exists(path):
        with open(path, "w", encoding="utf-8") as f:
            json.dump([], f)


def _read_session_records(session_id: str) -> list:
    """Reads a session's history as a list of {timestamp, activity, confidence, step_count} dicts."""
    init_session_file(session_id)
    with open(get_session_json_path(session_id), "r", encoding="utf-8") as f:
        try:
            records = json.load(f)
        except json.JSONDecodeError:
            return []
    return records if isinstance(records, list) else []


def _write_session_records(session_id: str, records: list):
    os.makedirs(SESSIONS_DIR, exist_ok=True)
    with open(get_session_json_path(session_id), "w", encoding="utf-8") as f:
        json.dump(records, f)


def _hour_of(timestamp: str) -> str:
    try:
        return datetime.strptime(timestamp, "%Y-%m-%d %H:%M:%S").strftime("%H")
    except (ValueError, TypeError):
        return timestamp[11:13] if timestamp and len(timestamp) >= 13 else ""


def _date_of(timestamp: str) -> str:
    try:
        return datetime.strptime(timestamp, "%Y-%m-%d %H:%M:%S").strftime("%Y-%m-%d")
    except (ValueError, TypeError):
        return timestamp[:10] if timestamp else ""


# ── Schema initialisation ──────────────────────────────────────────────────────

def init_db():
    """Initialises the main database and ensures the sessions directory exists."""
    # Ensure the sessions directory exists.
    os.makedirs(SESSIONS_DIR, exist_ok=True)

    # Initialise the main database (original schema setup)
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS predictions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp DATETIME,
            session_id TEXT,
            activity TEXT,
            confidence REAL,
            step_count INTEGER
        )
    """)
    conn.commit()
    conn.close()
    print(f"Database initialized at: {os.path.abspath(DB_PATH)}")
    print(f"Sessions directory initialized at: {os.path.abspath(SESSIONS_DIR)}")


# ── Write ──────────────────────────────────────────────────────────────────────

def insert_prediction(session_id: str, activity: str, confidence: float, step_count: int, timestamp: str = None):
    """Inserts a prediction record into both the main database and the session's JSON history file."""
    local_time = timestamp or datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # 1. Write to main database exactly as before
    main_conn = get_connection()
    main_cursor = main_conn.cursor()
    main_cursor.execute("""
        INSERT INTO predictions (timestamp, session_id, activity, confidence, step_count)
        VALUES (?, ?, ?, ?, ?)
    """, (local_time, session_id, activity, confidence, step_count))
    main_conn.commit()
    main_conn.close()

    # 2. Additionally append to the session's JSON history file
    records = _read_session_records(session_id)
    records.append({
        "timestamp": local_time,
        "activity": activity,
        "confidence": confidence,
        "step_count": step_count,
    })
    _write_session_records(session_id, records)


# ── Cross-edge-server session migration ────────────────────────────────────────
# The session's history file (data/sessions/session_<id>.json) is exactly what's
# mounted at /app/data by docker-compose.yml. When a client hands its session off to
# a different edge server container, that whole file is transferred (see
# GET/POST /session/{id}/database in routes.py) rather than replaying rows one at a
# time — plain JSON so it's easy to inspect/diff/hand-edit compared to a binary
# SQLite file, at the cost of the read/analytics functions below doing their own
# aggregation in Python instead of SQL for the per-session case.

def has_main_predictions_for_session(session_id: str) -> bool:
    """Checks whether the main database already has rows for this session."""
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT COUNT(*) as total FROM predictions WHERE session_id = ?", (session_id,))
    total = cursor.fetchone()["total"]
    conn.close()
    return total > 0


def get_session_json_bytes(session_id: str) -> bytes:
    """Reads the raw JSON bytes of a session's history file, creating an empty one if needed."""
    init_session_file(session_id)
    with open(get_session_json_path(session_id), "rb") as f:
        return f.read()


def replace_session_json_file(session_id: str, data: bytes):
    """
    Overwrites a session's JSON history file with bytes received from another edge
    server. Validates the payload is a JSON list before accepting it, so a malformed
    upload can't corrupt this server's copy.
    """
    try:
        records = json.loads(data.decode("utf-8"))
        if not isinstance(records, list):
            raise ValueError("session history JSON must be a list of records")
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        raise ValueError(f"invalid session history JSON: {e}")

    os.makedirs(SESSIONS_DIR, exist_ok=True)
    with open(get_session_json_path(session_id), "w", encoding="utf-8") as f:
        json.dump(records, f)


def purge_session(session_id: str):
    """
    Deletes a session's persisted data on this server — its JSON history file
    and its rows in the main database — after that data has been migrated to
    another edge server. Called as the final step of a handoff, on the OLD edge
    server, so that if the client ever roams back here it starts clean instead of
    finding (and colliding with) stale history left over from before it moved on.
    """
    path = get_session_json_path(session_id)
    if os.path.exists(path):
        os.remove(path)

    main_conn = get_connection()
    main_cursor = main_conn.cursor()
    main_cursor.execute("DELETE FROM predictions WHERE session_id = ?", (session_id,))
    main_conn.commit()
    main_conn.close()


def sync_session_into_main_db(session_id: str):
    """
    After a session's JSON history file has been replaced via
    replace_session_json_file, mirrors its records into this server's main
    database so session-less aggregate queries (e.g. the overall /dashboard)
    include the migrated history too. Skipped if the main database already has
    rows for this session (idempotent against retried handoff uploads).
    """
    if has_main_predictions_for_session(session_id):
        return

    records = _read_session_records(session_id)
    if not records:
        return

    main_conn = get_connection()
    main_cursor = main_conn.cursor()
    main_cursor.executemany(
        "INSERT INTO predictions (timestamp, session_id, activity, confidence, step_count) VALUES (?, ?, ?, ?, ?)",
        [(r["timestamp"], session_id, r["activity"], r["confidence"], r["step_count"]) for r in records],
    )
    main_conn.commit()
    main_conn.close()


# ── Read / Analytics ───────────────────────────────────────────────────────────
# Each function below branches on session_id: with one, it aggregates the
# session's JSON records in Python; without one, it queries the main SQLite
# database (all sessions combined) exactly as before.

def get_dashboard_data(session_id: str = None):
    labels = list(ACTIVITY_LABELS.values())

    if session_id:
        records = _read_session_records(session_id)
        total = len(records)

        counts = {label: 0 for label in labels}
        for r in records:
            if r["activity"] in counts:
                counts[r["activity"]] += 1

        percentages = {label: (round(count / total, 3) if total > 0 else 0.0) for label, count in counts.items()}

        hourly = {f"{h:02d}": 0 for h in range(24)}
        for r in records:
            hour = _hour_of(r["timestamp"])
            if hour in hourly:
                hourly[hour] += 1

        recent = []
        for r in sorted(records, key=lambda r: r["timestamp"], reverse=True)[:10]:
            ts = r["timestamp"]
            try:
                time_str = datetime.strptime(ts, "%Y-%m-%d %H:%M:%S").strftime("%H:%M:%S")
            except (ValueError, TypeError):
                time_str = ts
            recent.append({
                "timestamp": ts,
                "time": time_str,
                "activity": r["activity"],
                "confidence": round(r["confidence"], 3),
            })

        return {
            "activity_counts": counts,
            "activity_percentages": percentages,
            "hourly_activity_distribution": hourly,
            "recent_predictions": recent,
            "total_predictions": total,
        }

    conn = get_connection()
    cursor = conn.cursor()

    # 1. Total predictions
    cursor.execute("SELECT COUNT(*) as total FROM predictions")
    total = cursor.fetchone()["total"]

    # 2. Activity counts & percentages
    counts = {label: 0 for label in labels}

    cursor.execute("SELECT activity, COUNT(*) as count FROM predictions GROUP BY activity")
    rows = cursor.fetchall()
    for row in rows:
        counts[row["activity"]] = row["count"]

    percentages = {}
    for label, count in counts.items():
        percentages[label] = round(count / total, 3) if total > 0 else 0.0

    # 3. Hourly distribution (00 to 23)
    hourly = {f"{h:02d}": 0 for h in range(24)}
    cursor.execute("SELECT strftime('%H', timestamp) as hour, COUNT(*) as count FROM predictions GROUP BY hour")
    rows = cursor.fetchall()
    for row in rows:
        if row["hour"] in hourly:
            hourly[row["hour"]] = row["count"]

    # 4. Recent predictions (last 10)
    cursor.execute("""
        SELECT timestamp, activity, confidence
        FROM predictions
        ORDER BY timestamp DESC
        LIMIT 10
    """)
    rows = cursor.fetchall()
    recent = []
    for row in rows:
        ts = row["timestamp"]
        try:
            dt = datetime.strptime(ts, "%Y-%m-%d %H:%M:%S")
            time_str = dt.strftime("%H:%M:%S")
        except Exception:
            time_str = ts

        recent.append({
            "timestamp": ts,
            "time": time_str,
            "activity": row["activity"],
            "confidence": round(row["confidence"], 3)
        })

    conn.close()

    return {
        "activity_counts": counts,
        "activity_percentages": percentages,
        "hourly_activity_distribution": hourly,
        "recent_predictions": recent,
        "total_predictions": total
    }

def get_history_data(limit: int = 50, session_id: str = None):
    if session_id:
        records = _read_session_records(session_id)
        history = []
        for r in sorted(records, key=lambda r: r["timestamp"], reverse=True)[:limit]:
            ts = r["timestamp"]
            try:
                time_str = datetime.strptime(ts, "%Y-%m-%d %H:%M:%S").strftime("%H:%M:%S")
            except (ValueError, TypeError):
                time_str = ts
            history.append({
                "timestamp": ts,
                "time": time_str,
                "session_id": session_id,
                "activity": r["activity"],
                "confidence": round(r["confidence"], 3),
                "step_count": r["step_count"],
            })
        return history

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT timestamp, session_id, activity, confidence, step_count
        FROM predictions
        ORDER BY timestamp DESC
        LIMIT ?
    """, (limit,))
    rows = cursor.fetchall()
    history = []
    for row in rows:
        ts = row["timestamp"]
        try:
            dt = datetime.strptime(ts, "%Y-%m-%d %H:%M:%S")
            time_str = dt.strftime("%H:%M:%S")
        except Exception:
            time_str = ts
        history.append({
            "timestamp": ts,
            "time": time_str,
            "session_id": row["session_id"],
            "activity": row["activity"],
            "confidence": round(row["confidence"], 3),
            "step_count": row["step_count"]
        })
    conn.close()
    return history

def get_statistics_data(session_id: str = None):
    if session_id:
        records = _read_session_records(session_id)
        total = len(records)
        if total == 0:
            return {
                "total_predictions": 0,
                "average_confidence": 0.0,
                "most_active_hour": "N/A",
                "most_common_activity": "N/A",
                "total_steps": 0,
            }

        avg_conf = sum(r["confidence"] for r in records) / total

        hour_counts = Counter(_hour_of(r["timestamp"]) for r in records)
        most_active_hour = f"{hour_counts.most_common(1)[0][0]}:00" if hour_counts else "N/A"

        activity_counts = Counter(r["activity"] for r in records)
        most_common_activity = activity_counts.most_common(1)[0][0] if activity_counts else "N/A"

        total_steps = max((r["step_count"] for r in records), default=0)

        return {
            "total_predictions": total,
            "average_confidence": round(avg_conf, 3) if avg_conf else 0.0,
            "most_active_hour": most_active_hour,
            "most_common_activity": most_common_activity,
            "total_steps": total_steps,
        }

    conn = get_connection()
    cursor = conn.cursor()

    # Total predictions
    cursor.execute("SELECT COUNT(*) as total FROM predictions")
    total = cursor.fetchone()["total"]

    if total == 0:
        conn.close()
        return {
            "total_predictions": 0,
            "average_confidence": 0.0,
            "most_active_hour": "N/A",
            "most_common_activity": "N/A",
            "total_steps": 0
        }

    # Average confidence
    cursor.execute("SELECT AVG(confidence) as avg_conf FROM predictions")
    avg_conf = cursor.fetchone()["avg_conf"]

    # Most active hour
    cursor.execute("SELECT strftime('%H', timestamp) as hour, COUNT(*) as count FROM predictions GROUP BY hour ORDER BY count DESC LIMIT 1")
    row_hour = cursor.fetchone()
    most_active_hour = f"{row_hour['hour']}:00" if row_hour else "N/A"

    # Most common activity
    cursor.execute("SELECT activity, COUNT(*) as count FROM predictions GROUP BY activity ORDER BY count DESC LIMIT 1")
    row_act = cursor.fetchone()
    most_common_activity = row_act["activity"] if row_act else "N/A"

    # Total steps: sum of the maximum steps per unique session ID
    cursor.execute("SELECT SUM(max_steps) as sum_steps FROM (SELECT MAX(step_count) as max_steps FROM predictions GROUP BY session_id)")
    sum_steps = cursor.fetchone()["sum_steps"]

    conn.close()

    return {
        "total_predictions": total,
        "average_confidence": round(avg_conf, 3) if avg_conf else 0.0,
        "most_active_hour": most_active_hour,
        "most_common_activity": most_common_activity,
        "total_steps": sum_steps if sum_steps else 0
    }

def get_activity_statistics(activity: str, session_id: str = None):
    if session_id:
        records = [r for r in _read_session_records(session_id) if r["activity"] == activity]
        count = len(records)

        total_seconds = int(count * 2.56)
        hours = total_seconds // 3600
        minutes = (total_seconds % 3600) // 60
        seconds = total_seconds % 60
        duration_str = f"{hours}h {minutes}m {seconds}s" if hours > 0 else f"{minutes}m {seconds}s"

        hourly = {f"{h:02d}": 0 for h in range(24)}
        for r in records:
            hour = _hour_of(r["timestamp"])
            if hour in hourly:
                hourly[hour] += 1

        return {
            "activity": activity,
            "count": count,
            "duration_seconds": total_seconds,
            "duration_string": duration_str,
            "hourly_distribution": hourly,
        }

    conn = get_connection()
    cursor = conn.cursor()

    # Count predictions for this activity
    cursor.execute("SELECT COUNT(*) as count FROM predictions WHERE activity = ?", (activity,))
    count = cursor.fetchone()["count"]

    # Calculate estimated duration (assuming ~2.56 seconds per prediction window)
    total_seconds = int(count * 2.56)
    hours = total_seconds // 3600
    minutes = (total_seconds % 3600) // 60
    seconds = total_seconds % 60

    duration_str = f"{hours}h {minutes}m {seconds}s" if hours > 0 else f"{minutes}m {seconds}s"

    # Hourly distribution for this activity
    hourly = {f"{h:02d}": 0 for h in range(24)}
    cursor.execute("""
        SELECT strftime('%H', timestamp) as hour, COUNT(*) as count
        FROM predictions
        WHERE activity = ?
        GROUP BY hour
    """, (activity,))
    rows = cursor.fetchall()
    for row in rows:
        if row["hour"] in hourly:
            hourly[row["hour"]] = row["count"]

    conn.close()

    return {
        "activity": activity,
        "count": count,
        "duration_seconds": total_seconds,
        "duration_string": duration_str,
        "hourly_distribution": hourly
    }

def get_today_dashboard_data(session_id: str = None):
    today = datetime.now().strftime("%Y-%m-%d")
    labels = list(ACTIVITY_LABELS.values())

    if session_id:
        records = [r for r in _read_session_records(session_id) if _date_of(r["timestamp"]) == today]
        total = len(records)

        counts = {label: 0 for label in labels}
        for r in records:
            if r["activity"] in counts:
                counts[r["activity"]] += 1

        hourly = {f"{h:02d}": 0 for h in range(24)}
        for r in records:
            hour = _hour_of(r["timestamp"])
            if hour in hourly:
                hourly[hour] += 1

        return {
            "activity_counts": counts,
            "hourly_activity_distribution": hourly,
            "total_predictions": total,
        }

    conn = get_connection()
    cursor = conn.cursor()

    # Total predictions today
    cursor.execute("SELECT COUNT(*) as total FROM predictions WHERE DATE(timestamp) = ?", (today,))
    total = cursor.fetchone()["total"]

    # Activity counts for today
    counts = {label: 0 for label in labels}

    cursor.execute(
        "SELECT activity, COUNT(*) as count FROM predictions WHERE DATE(timestamp) = ? GROUP BY activity",
        (today,)
    )
    rows = cursor.fetchall()
    for row in rows:
        counts[row["activity"]] = row["count"]

    # Hourly distribution for today
    hourly = {f"{h:02d}": 0 for h in range(24)}
    cursor.execute(
        "SELECT strftime('%H', timestamp) as hour, COUNT(*) as count FROM predictions WHERE DATE(timestamp) = ? GROUP BY hour",
        (today,)
    )
    rows = cursor.fetchall()
    for row in rows:
        if row["hour"] in hourly:
            hourly[row["hour"]] = row["count"]

    conn.close()

    return {
        "activity_counts": counts,
        "hourly_activity_distribution": hourly,
        "total_predictions": total
    }

def get_today_activity_statistics(activity: str, session_id: str = None):
    today = datetime.now().strftime("%Y-%m-%d")

    if session_id:
        records = [
            r for r in _read_session_records(session_id)
            if r["activity"] == activity and _date_of(r["timestamp"]) == today
        ]
        count = len(records)

        total_seconds = int(count * 2.56)
        hours = total_seconds // 3600
        minutes = (total_seconds % 3600) // 60
        seconds = total_seconds % 60
        duration_str = f"{hours}h {minutes}m {seconds}s" if hours > 0 else f"{minutes}m {seconds}s"

        hourly = {f"{h:02d}": 0 for h in range(24)}
        for r in records:
            hour = _hour_of(r["timestamp"])
            if hour in hourly:
                hourly[hour] += 1

        return {
            "activity": activity,
            "count": count,
            "duration_seconds": total_seconds,
            "duration_string": duration_str,
            "hourly_distribution": hourly,
        }

    conn = get_connection()
    cursor = conn.cursor()

    # Count predictions for this activity today
    cursor.execute(
        "SELECT COUNT(*) as count FROM predictions WHERE activity = ? AND DATE(timestamp) = ?",
        (activity, today)
    )
    count = cursor.fetchone()["count"]

    # Estimated duration (~2.56 seconds per prediction window)
    total_seconds = int(count * 2.56)
    hours = total_seconds // 3600
    minutes = (total_seconds % 3600) // 60
    seconds = total_seconds % 60

    duration_str = f"{hours}h {minutes}m {seconds}s" if hours > 0 else f"{minutes}m {seconds}s"

    # Hourly distribution for this activity today
    hourly = {f"{h:02d}": 0 for h in range(24)}
    cursor.execute("""
        SELECT strftime('%H', timestamp) as hour, COUNT(*) as count
        FROM predictions
        WHERE activity = ? AND DATE(timestamp) = ?
        GROUP BY hour
    """, (activity, today))
    rows = cursor.fetchall()
    for row in rows:
        if row["hour"] in hourly:
            hourly[row["hour"]] = row["count"]

    conn.close()

    return {
        "activity": activity,
        "count": count,
        "duration_seconds": total_seconds,
        "duration_string": duration_str,
        "hourly_distribution": hourly
    }
