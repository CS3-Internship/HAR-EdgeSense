import os
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from ml_pipeline.config import DATASET_DIR, SEQ_LEN, NUM_CHANNELS, VALIDATION_SPLIT

# The 6 inertial signal channels that match Flutter's live sensor data:
# total_acc = Flutter accelerometerEventStream() (raw accelerometer including gravity)
# body_gyro = Flutter gyroscopeEventStream() (raw gyroscope)
# Channel order: [accel_x, accel_y, accel_z, gyro_x, gyro_y, gyro_z]
INERTIAL_FILES = [
    "total_acc_x", "total_acc_y", "total_acc_z",
    "body_gyro_x", "body_gyro_y", "body_gyro_z",
]

def load_single_channel_file(filepath):
    """
    Loads a single inertial signal file using pandas read_csv for speed,
    returning a 2D numpy array of shape (N, 128).
    """
    print(f"Loading signal file: {os.path.basename(filepath)}...")
    df = pd.read_csv(filepath, sep=r"\s+", header=None, engine="python")
    return df.values

def load_inertial_signals(set_name):
    """
    Loads all 9 inertial signal channels for a given set ('train' or 'test')
    and stacks them into a 3D numpy array of shape (N, 128, 9).
    """
    signals_data = []
    
    for channel_name in INERTIAL_FILES:
        filepath = os.path.join(DATASET_DIR, set_name, "Inertial Signals", f"{channel_name}_{set_name}.txt")
        channel_data = load_single_channel_file(filepath)
        signals_data.append(channel_data)
        
    # Stack along the 3rd axis (channels)
    # signals_data is list of 9 arrays, each (N, 128)
    # Stacking yields shape (9, N, 128). We transpose it to (N, 128, 9)
    stacked = np.stack(signals_data, axis=2)
    return stacked

def load_labels(set_name):
    """
    Loads the label file y_{set_name}.txt, maps the 1-6 integers to 0-5
    for categorical indexing, and returns a 1D array of shape (N,).
    """
    filepath = os.path.join(DATASET_DIR, set_name, f"y_{set_name}.txt")
    print(f"Loading labels from: {os.path.basename(filepath)}")
    labels = pd.read_csv(filepath, header=None).values.squeeze()
    # Convert labels from 1-6 range to 0-5 range for Tensorflow indexing
    corrected_labels = labels - 1
    return corrected_labels

def standardize_tensors(X_train, X_val, X_test):
    """
    Standardizes the 3D tensors channel-wise.
    Reshapes the data to 2D (samples * timesteps, channels), fits StandardScaler 
    on training data, transforms train, val, and test, and reshapes back to 3D.
    """
    print("\nStandardizing sensor signals channel-wise...")
    
    # Save original shapes
    shape_train = X_train.shape
    shape_val = X_val.shape
    shape_test = X_test.shape
    
    # Reshape to 2D for scaling
    X_train_2D = X_train.reshape(-1, NUM_CHANNELS)
    X_val_2D = X_val.reshape(-1, NUM_CHANNELS)
    X_test_2D = X_test.reshape(-1, NUM_CHANNELS)
    
    # Fit scaler on train set and transform all sets
    scaler = StandardScaler()
    X_train_scaled_2D = scaler.fit(X_train_2D)
    X_train_scaled_2D = scaler.transform(X_train_2D)
    X_val_scaled_2D = scaler.transform(X_val_2D)
    X_test_scaled_2D = scaler.transform(X_test_2D)
    
    # Reshape back to 3D
    X_train_scaled = X_train_scaled_2D.reshape(shape_train)
    X_val_scaled = X_val_scaled_2D.reshape(shape_val)
    X_test_scaled = X_test_scaled_2D.reshape(shape_test)
    
    return X_train_scaled, X_val_scaled, X_test_scaled, scaler

def get_preprocessed_dataset():
    """
    Runs the complete data loading and preprocessing pipeline:
    - Loads raw signals & labels for train and test sets
    - Performs stratified Train-Validation split on train set
    - Normalizes/standardizes features channel-wise
    - Returns: X_train, y_train, X_val, y_val, X_test, y_test, scaler
    """
    print("--- STARTING DATA LOADING PIPELINE ---")
    
    # Load raw data
    X_train_raw = load_inertial_signals("train")
    y_train_raw = load_labels("train")
    
    X_test_raw = load_inertial_signals("test")
    y_test_raw = load_labels("test")
    
    print(f"\nRaw Train Set Shapes: X={X_train_raw.shape}, y={y_train_raw.shape}")
    print(f"Raw Test Set Shapes: X={X_test_raw.shape}, y={y_test_raw.shape}")
    
    # Perform Stratified Split for Validation Set
    print(f"\nSplitting train set into train and validation sets ({int(VALIDATION_SPLIT*100)}% validation)...")
    X_train_split, X_val_split, y_train_split, y_val_split = train_test_split(
        X_train_raw, y_train_raw, 
        test_size=VALIDATION_SPLIT, 
        stratify=y_train_raw, 
        random_state=42
    )
    
    # Channel-wise standard scaling
    X_train, X_val, X_test, scaler = standardize_tensors(X_train_split, X_val_split, X_test_raw)
    
    print("\n--- LOADING AND PREPROCESSING COMPLETE ---")
    print(f"Train set shape      : X_train={X_train.shape}, y_train={y_train_split.shape}")
    print(f"Validation set shape : X_val={X_val.shape}, y_val={y_val_split.shape}")
    print(f"Test set shape       : X_test={X_test.shape}, y_test={y_test_raw.shape}")
    
    return X_train, y_train_split, X_val, y_val_split, X_test, y_test_raw, scaler

if __name__ == "__main__":
    X_train, y_train, X_val, y_val, X_test, y_test, scaler = get_preprocessed_dataset()
