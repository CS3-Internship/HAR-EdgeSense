import os
import joblib
import numpy as np
import matplotlib.pyplot as plt
import tensorflow as tf
from tensorflow.keras.callbacks import EarlyStopping, ModelCheckpoint
from tensorflow.keras.optimizers import Adam

from ml_pipeline.config import (
    OUTPUT_DIR, BATCH_SIZE, EPOCHS, LEARNING_RATE
)
from ml_pipeline.data_loader import get_preprocessed_dataset
from ml_pipeline.model import build_lstm_model

def plot_training_history(history, save_path):
    """
    Plots the training and validation loss and accuracy curves
    and saves the figure to disk.
    """
    epochs_range = range(1, len(history.history['loss']) + 1)
    
    plt.figure(figsize=(12, 5))
    
    # 1. Accuracy Plot
    plt.subplot(1, 2, 1)
    plt.plot(epochs_range, history.history['accuracy'], label='Training Accuracy', color='#1f77b4', linewidth=2)
    plt.plot(epochs_range, history.history['val_accuracy'], label='Validation Accuracy', color='#ff7f0e', linewidth=2)
    plt.title('Training and Validation Accuracy', fontsize=12, fontweight='bold')
    plt.xlabel('Epochs', fontsize=10)
    plt.ylabel('Accuracy', fontsize=10)
    plt.legend(loc='lower right')
    plt.grid(True, linestyle='--', alpha=0.6)
    
    # 2. Loss Plot
    plt.subplot(1, 2, 2)
    plt.plot(epochs_range, history.history['loss'], label='Training Loss', color='#d62728', linewidth=2)
    plt.plot(epochs_range, history.history['val_loss'], label='Validation Loss', color='#2ca02c', linewidth=2)
    plt.title('Training and Validation Loss', fontsize=12, fontweight='bold')
    plt.xlabel('Epochs', fontsize=10)
    plt.ylabel('Loss', fontsize=10)
    plt.legend(loc='upper right')
    plt.grid(True, linestyle='--', alpha=0.6)
    
    plt.tight_layout()
    plt.savefig(save_path, dpi=300)
    plt.close()
    print(f"Training curves saved to: {save_path}")

def main():
    # 1. Load and preprocess dataset
    X_train, y_train, X_val, y_val, X_test, y_test, scaler = get_preprocessed_dataset()
    
    # 2. Save scaler for FastAPI server integration
    scaler_path = os.path.join(OUTPUT_DIR, "scaler.pkl")
    joblib.dump(scaler, scaler_path)
    print(f"StandardScaler saved successfully to: {scaler_path}")
    
    # 3. Build model
    model = build_lstm_model(input_shape=(X_train.shape[1], X_train.shape[2]))
    model.summary()
    
    # 4. Compile model
    optimizer = Adam(learning_rate=LEARNING_RATE)
    model.compile(
        optimizer=optimizer,
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy']
    )
    
    # 5. Callbacks
    # Early stopping to halt training if val_loss doesn't improve for 8 epochs
    early_stopping = EarlyStopping(
        monitor='val_loss',
        patience=8,
        restore_best_weights=True,
        verbose=1
    )
    
    # ModelCheckpoint saves only the model weights with lowest val_loss
    model_checkpoint_path = os.path.join(OUTPUT_DIR, "best_model.keras")
    checkpoint = ModelCheckpoint(
        filepath=model_checkpoint_path,
        monitor='val_loss',
        save_best_only=True,
        verbose=1
    )
    
    # 6. Model Training
    print("\n--- INITIATING MODEL TRAINING ---")
    history = model.fit(
        X_train, y_train,
        batch_size=BATCH_SIZE,
        epochs=EPOCHS,
        validation_data=(X_val, y_val),
        callbacks=[early_stopping, checkpoint],
        verbose=1
    )
    
    # 7. Plot history
    curves_path = os.path.join(OUTPUT_DIR, "training_curves.png")
    plot_training_history(history, curves_path)
    
    # 8. Save Final Model (TensorFlow SavedModel format & Keras format)
    # The checkpoint already saved the best model in .keras. Let's explicitly save the final one too.
    final_keras_path = os.path.join(OUTPUT_DIR, "final_model.keras")
    model.save(final_keras_path)
    print(f"Final Model saved in .keras format to: {final_keras_path}")
    
    saved_model_dir = os.path.join(OUTPUT_DIR, "saved_model")
    # For exporting/saving TensorFlow SavedModel directory
    try:
        model.export(saved_model_dir)
        print(f"Final Model exported in TensorFlow SavedModel format to: {saved_model_dir}")
    except Exception as e:
        print(f"model.export failed: {e}. Attempting tf.saved_model.save...")
        try:
            import tensorflow as tf
            tf.saved_model.save(model, saved_model_dir)
            print(f"Final Model saved in TensorFlow SavedModel format to: {saved_model_dir}")
        except Exception as e2:
            print(f"tf.saved_model.save failed: {e2}. Continuing...")
    
    # Export test dataset as numpy binary files for evaluation script convenience
    np.save(os.path.join(OUTPUT_DIR, "X_test_scaled.npy"), X_test)
    np.save(os.path.join(OUTPUT_DIR, "y_test.npy"), y_test)
    
    print("\n--- TRAINING WORKFLOW COMPLETED ---")

if __name__ == "__main__":
    main()
