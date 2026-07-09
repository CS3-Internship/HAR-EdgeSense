import sqlite3
import os
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


def get_session_db_path(session_id: str) -> str:
    """Returns the absolute path for a session's dedicated database file."""
    return os.path.join(SESSIONS_DIR, f"session_{session_id}.db")


def get_session_connection(session_id: str):
    """Opens (and if necessary creates) a connection to a session database."""
    db_path = get_session_db_path(session_id)
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def get_db_connection(session_id: str = None):
    """Opens a connection to either the session database or the main database."""
    if session_id:
        init_session_db(session_id)
        db_path = get_session_db_path(session_id)
    else:
        db_path = DB_PATH
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


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


def init_session_db(session_id: str):
    """Ensures a session database exists and has the predictions table with ONLY required columns."""
    conn = get_session_connection(session_id)
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS predictions (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp  DATETIME,
            activity   TEXT,
            confidence REAL,
            step_count INTEGER
        )
    """)
    conn.commit()
    conn.close()


# ── Write ──────────────────────────────────────────────────────────────────────

def insert_prediction(session_id: str, activity: str, confidence: float, step_count: int, timestamp: str = None):
    """Inserts a prediction record into both the main database and session-specific database."""
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

    # 2. Additionally write to session-specific database
    init_session_db(session_id)
    session_conn = get_session_connection(session_id)
    session_cursor = session_conn.cursor()
    session_cursor.execute("""
        INSERT INTO predictions (timestamp, activity, confidence, step_count)
        VALUES (?, ?, ?, ?)
    """, (local_time, activity, confidence, step_count))
    session_conn.commit()
    session_conn.close()


# ── Cross-edge-server session migration ────────────────────────────────────────
# The session-specific SQLite file (data/sessions/session_<id>.db) is exactly what's
# mounted at /app/data by docker-compose.yml. When a client hands its session off to
# a different edge server container, that whole file is transferred (see
# GET/POST /session/{id}/database in routes.py) rather than replaying rows one at a
# time, so the migrated history is a byte-for-byte match of what the old server had.

def has_main_predictions_for_session(session_id: str) -> bool:
    """Checks whether the main database already has rows for this session."""
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT COUNT(*) as total FROM predictions WHERE session_id = ?", (session_id,))
    total = cursor.fetchone()["total"]
    conn.close()
    return total > 0


def get_session_db_bytes(session_id: str) -> bytes:
    """Reads the raw bytes of a session's SQLite file, creating an empty one if needed."""
    init_session_db(session_id)
    with open(get_session_db_path(session_id), "rb") as f:
        return f.read()


def replace_session_db_file(session_id: str, data: bytes):
    """Overwrites a session's SQLite file with bytes received from another edge server."""
    os.makedirs(SESSIONS_DIR, exist_ok=True)
    with open(get_session_db_path(session_id), "wb") as f:
        f.write(data)


def purge_session(session_id: str):
    """
    Deletes a session's persisted data on this server — its dedicated SQLite file
    and its rows in the main database — after that data has been migrated to
    another edge server. Called as the final step of a handoff, on the OLD edge
    server, so that if the client ever roams back here it starts clean instead of
    finding (and colliding with) stale history left over from before it moved on.
    """
    db_path = get_session_db_path(session_id)
    if os.path.exists(db_path):
        os.remove(db_path)

    main_conn = get_connection()
    main_cursor = main_conn.cursor()
    main_cursor.execute("DELETE FROM predictions WHERE session_id = ?", (session_id,))
    main_conn.commit()
    main_conn.close()


def sync_session_into_main_db(session_id: str):
    """
    After a session's SQLite file has been replaced via replace_session_db_file,
    mirrors its rows into this server's main database so session-less aggregate
    queries (e.g. the overall /dashboard) include the migrated history too.
    Skipped if the main database already has rows for this session (idempotent
    against retried handoff uploads).
    """
    if has_main_predictions_for_session(session_id):
        return

    session_conn = get_session_connection(session_id)
    session_cursor = session_conn.cursor()
    session_cursor.execute("SELECT timestamp, activity, confidence, step_count FROM predictions ORDER BY id")
    rows = session_cursor.fetchall()
    session_conn.close()

    if not rows:
        return

    main_conn = get_connection()
    main_cursor = main_conn.cursor()
    main_cursor.executemany(
        "INSERT INTO predictions (timestamp, session_id, activity, confidence, step_count) VALUES (?, ?, ?, ?, ?)",
        [(row["timestamp"], session_id, row["activity"], row["confidence"], row["step_count"]) for row in rows],
    )
    main_conn.commit()
    main_conn.close()


# ── Read / Analytics ───────────────────────────────────────────────────────────

def get_dashboard_data(session_id: str = None):
    conn = get_db_connection(session_id)
    cursor = conn.cursor()
    
    # 1. Total predictions
    cursor.execute("SELECT COUNT(*) as total FROM predictions")
    total = cursor.fetchone()["total"]
    
    # 2. Activity counts & percentages
    labels = list(ACTIVITY_LABELS.values())
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
    conn = get_db_connection(session_id)
    cursor = conn.cursor()
    if session_id:
        cursor.execute("""
            SELECT timestamp, activity, confidence, step_count 
            FROM predictions 
            ORDER BY timestamp DESC 
            LIMIT ?
        """, (limit,))
    else:
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
            "session_id": session_id if session_id else row["session_id"],
            "activity": row["activity"],
            "confidence": round(row["confidence"], 3),
            "step_count": row["step_count"]
        })
    conn.close()
    return history

def get_statistics_data(session_id: str = None):
    conn = get_db_connection(session_id)
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
    if session_id:
        cursor.execute("SELECT MAX(step_count) as sum_steps FROM predictions")
    else:
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
    conn = get_db_connection(session_id)
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
    conn = get_db_connection(session_id)
    cursor = conn.cursor()
    today = datetime.now().strftime("%Y-%m-%d")

    # Total predictions today
    cursor.execute("SELECT COUNT(*) as total FROM predictions WHERE DATE(timestamp) = ?", (today,))
    total = cursor.fetchone()["total"]

    # Activity counts for today
    labels = list(ACTIVITY_LABELS.values())
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
    conn = get_db_connection(session_id)
    cursor = conn.cursor()
    today = datetime.now().strftime("%Y-%m-%d")

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
