# Human Activity Recognition ML Pipeline Walkthrough

This walkthrough details the design, implementation, and training results of our Human Activity Recognition (HAR) sequential model.

---

## 1. Accomplishments & Created Files

We implemented a modular, production-ready python package [ml_pipeline](file:///c:/Users/Vibhish vs/EdgeSense/edge_sense/ml_pipeline) containing:
1. **`config.py`**: Model, data, and training configuration parameters.
2. **`data_loader.py`**: Loads 9 inertial signals, stacks them, corrects label indices, splits train/validation, and standardizes data channel-wise.
3. **`model.py`**: LSTM architecture using stacked LSTMs and regularizing Dropout layers.
4. **`train.py`**: Compiles model, sets early stopping and checkpointing callbacks, runs training, plots history, and saves Keras and SavedModel formats along with the StandardScaler.
5. **`evaluate.py`**: Scores the model on test set, prints metrics, saves classification reports, and outputs the confusion matrix plot.

All model output files and plots were successfully generated in the [output folder](file:///c:/Users/Vibhish vs/EdgeSense/edge_sense/ml_pipeline/output).

---

## 2. Model Architecture Detail (Phase 4)

The sequential model utilizes stacked **LSTMs** (Long Short-Term Memory) because human activity sensor feeds contain strong temporal patterns (e.g. step cycles in WALKING).
```
Input Sequence: (128 samples, 9 channels)
      ↓
LSTM Layer 1: 64 units, returns sequences (Shape: None, 128, 64)
      ↓
Dropout Layer 1: rate=0.5 (Shape: None, 128, 64)
      ↓
LSTM Layer 2: 64 units, collapses sequences (Shape: None, 64)
      ↓
Dropout Layer 2: rate=0.5 (Shape: None, 64)
      ↓
Dense Classification Layer: 6 units (Shape: None, 6)
      ↓
Softmax Activation: probability distribution over 6 activity classes
```

---

## 3. Training & Validation Performance (Phase 5)

We trained the model with the following configuration:
* **Optimizer**: Adam (learning rate = 0.001)
* **Loss Function**: Sparse Categorical Crossentropy (labels converted to `0-5`)
* **Callbacks**: `EarlyStopping` (patience=8, monitored `val_loss`) & `ModelCheckpoint`
* **Result**: Training automatically stopped at **Epoch 21** due to early stopping, restoring the best model weights from **Epoch 13**.

### Training Curves
![Training Curves](/C:/Users/Vibhish%20vs/.gemini/antigravity-ide/brain/f74e2d9a-b422-4726-820c-7f5d0951121f/training_curves.png)

---

## 4. Evaluation Performance (Phase 6)

Evaluating the best checkpointed model against the unseen **test set** yielded outstanding results:
* **Test Accuracy**: **91.08%**
* **Precision**: **91.29%**
* **Recall**: **91.15%**
* **F1-Score**: **91.15%**

### Classification Report
```
                    precision    recall  f1-score   support

           WALKING       0.99      0.95      0.97       496
  WALKING_UPSTAIRS       0.84      0.95      0.89       471
WALKING_DOWNSTAIRS       0.95      0.93      0.94       420
           SITTING       0.85      0.82      0.83       491
          STANDING       0.85      0.86      0.86       532
            LAYING       1.00      0.95      0.97       537

          accuracy                           0.91      2947
         macro avg       0.91      0.91      0.91      2947
      weighted avg       0.91      0.91      0.91      2947
```

### Confusion Matrix
![Confusion Matrix](/C:/Users/Vibhish%20vs/.gemini/antigravity-ide/brain/f74e2d9a-b422-4726-820c-7f5d0951121f/confusion_matrix.png)

* **Analysis**: The model easily identifies **LAYING** ($100\%$ precision, $95\%$ recall) and **WALKING** ($99\%$ precision). It experiences slight confusion between **SITTING** and **STANDING** (which share identical stationary sensor profiles, differing only by phone angle) and **WALKING_UPSTAIRS** vs **WALKING_DOWNSTAIRS**.

---

## 5. FastAPI Integration Design (Phase 7 & 8)

To connect the model to the existing Flutter $\rightarrow$ FastAPI structure:

1. **Model & Scaler Loading inside FastAPI (`app.py`)**:
   ```python
   import joblib
   import tensorflow as tf
   import numpy as np

   # Load during startup
   model = tf.keras.models.load_model("ml_pipeline/output/best_model.keras")
   scaler = joblib.load("ml_pipeline/output/scaler.pkl")
   ```

2. **Windowing & Scaling on the Server**:
   Flutter sends continuous streams of individual sensor readings. The server needs to buffer these readings into **sliding windows of 128 elements** (2.56 seconds of data at 50Hz) with 50% overlap.
   * A queue of size 128 is maintained per session.
   * When the queue reaches 128 items, we extract the accelerometer and gyroscope axes.
   * Format the window to shape `(128, 9)` matching the 9 channels.
   * Scale using the training scaler:
     ```python
     window_2d = window_raw.reshape(-1, 9)
     window_scaled_2d = scaler.transform(window_2d)
     window_scaled = window_scaled_2d.reshape(1, 128, 9)  # Add batch dimension
     ```

3. **Inference & Response**:
   ```python
   prediction = model.predict(window_scaled, verbose=0)
   predicted_class_id = int(np.argmax(prediction[0]))
   activity_name = ACTIVITY_LABELS[predicted_class_id]
   return {"prediction": activity_name}
   ```
