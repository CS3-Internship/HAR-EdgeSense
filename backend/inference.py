import os
import joblib
import numpy as np
import tensorflow as tf
import threading

from config import MODEL_PATH, SCALER_PATH, ACTIVITY_LABELS
from preprocessing import preprocess_window

# Global model and scaler variables
model = None
scaler = None
model_lock = threading.Lock()  # Ensure thread-safe inference

def load_assets():
    global model, scaler
    print("\n--- LOADING HAR ASSETS ---")
    if os.path.exists(MODEL_PATH):
        print(f"Loading Keras model from: {MODEL_PATH}")
        model = tf.keras.models.load_model(MODEL_PATH)
        print("Model loaded successfully.")
    else:
        print(f"ERROR: Model file not found at {MODEL_PATH}")
        
    if os.path.exists(SCALER_PATH):
        print(f"Loading StandardScaler from: {SCALER_PATH}")
        scaler = joblib.load(SCALER_PATH)
        print("Scaler loaded successfully.")
    else:
        print(f"ERROR: Scaler file not found at {SCALER_PATH}")
    print("--------------------------\n")

def process_inference_for_session(store: dict, session_id: str = "Unknown") -> dict:
    """
    Checks if there are enough samples, scales them, runs model inference,
    handles sliding window overlap, and updates the last prediction.
    """
    global model, scaler
    if model is None or scaler is None:
        return {"error": "Model or scaler not loaded on server"}
        
    buffer = store["buffer"]
    
    # Check if we have the minimum required window size
    if len(buffer) < 128:
        prediction_result = {
            "status": "collecting",
            "samples": len(buffer),
            "required": 128
        }
        store["last_prediction"] = prediction_result
        # Return a copy that includes step_count
        res = prediction_result.copy()
        res["step_count"] = store.get("step_count", 0)
        return res
        
    # Extract the first window of 128 samples
    window_raw = np.array(buffer[:128])  # shape: (128, 6)
    
    # 50% overlap sliding window: remove the oldest 64 samples
    store["buffer"] = buffer[64:]
    
    window_scaled_2D = preprocess_window(window_raw, scaler)
    
    # Add batch dimension -> (1, 128, 6)
    input_tensor = np.expand_dims(window_scaled_2D, axis=0)
    
    # Thread-safe model inference
    with model_lock:
        predictions = model.predict(input_tensor, verbose=0)
        
    # Get class ID and probability confidence
    class_id = int(np.argmax(predictions[0]))
    confidence = float(predictions[0][class_id])
    activity_name = ACTIVITY_LABELS.get(class_id, "Unknown")
    
    prediction_result = {
        "status": "predicted",
        "activity": activity_name,
        "confidence": round(confidence, 3)
    }
    
    store["last_prediction"] = prediction_result
    
    # Save the prediction history to the database
    try:
        from database import insert_prediction
        insert_prediction(
            session_id=session_id,
            activity=activity_name,
            confidence=round(confidence, 3),
            step_count=store.get("step_count", 0)
        )
        print(f"Saved prediction to database: {activity_name} ({round(confidence, 3)}) for session {session_id}")
    except Exception as e:
        print(f"Failed to save prediction to database: {e}")
    
    # Return a copy that includes step_count
    res = prediction_result.copy()
    res["step_count"] = store.get("step_count", 0)
    return res
