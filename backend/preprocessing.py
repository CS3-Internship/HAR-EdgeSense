import numpy as np

def preprocess_window(window_raw, scaler):
    """
    Preprocesses the raw window by converting accelerometer data from m/s^2 to g,
    aligning the dominant gravity axis to the X-axis (as expected by the UCI HAR model),
    and applying the standard scaler.
    """
    window_preprocessed = window_raw.copy()
    
    # 1. Identify which axis currently has gravity (largest absolute mean over the window)
    acc_means = np.abs(np.mean(window_preprocessed[:, :3], axis=0))
    dominant_axis = np.argmax(acc_means)
    
    # 2. Swap the dominant axis to the X-axis (index 0) for both accelerometer and gyroscope
    if dominant_axis == 1:
        # Swap X and Y
        # Accelerometer
        window_preprocessed[:, [0, 1]] = window_preprocessed[:, [1, 0]]
        # Gyroscope
        window_preprocessed[:, [3, 4]] = window_preprocessed[:, [4, 3]]
    elif dominant_axis == 2:
        # Swap X and Z
        # Accelerometer
        window_preprocessed[:, [0, 2]] = window_preprocessed[:, [2, 0]]
        # Gyroscope
        window_preprocessed[:, [3, 5]] = window_preprocessed[:, [5, 3]]
        
    # 3. Convert accelerometer data from m/s^2 (Flutter) to g (UCI HAR training format)
    # The first 3 features are total_acc_x, total_acc_y, total_acc_z
    window_preprocessed[:, :3] = window_preprocessed[:, :3] / 9.80665
    
    # 4. Channel-wise standard scaling
    window_scaled_2D = scaler.transform(window_preprocessed)
    
    return window_scaled_2D
