import tensorflow as tf
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import LSTM, Dense, Dropout, Input
from ml_pipeline.config import SEQ_LEN, NUM_CHANNELS, NUM_CLASSES

def build_lstm_model(input_shape=(SEQ_LEN, NUM_CHANNELS), num_classes=NUM_CLASSES):
    """
    Builds and returns a stacked LSTM network for Human Activity Recognition.
    
    Architecture:
    Input Layer: Shape (128, 9)
    LSTM (64 units, return_sequences=True) -> keeps sequence shape for the next LSTM
    Dropout (rate=0.5) -> prevents overfitting by randomly setting inputs to 0
    LSTM (64 units, return_sequences=False) -> collapses temporal steps into a single state
    Dropout (rate=0.5) -> regularizes final feature representation
    Dense (6 units, softmax activation) -> outputs probability distribution over 6 classes
    """
    model = Sequential([
        # Explicit input layer to define the tensor dimensions
        Input(shape=input_shape),
        
        # First LSTM layer: returns sequence (N, 128, 64) to be processed by second LSTM
        LSTM(64, return_sequences=True, name="lstm_layer_1"),
        Dropout(0.5, name="dropout_1"),
        
        # Second LSTM layer: returns final state (N, 64) for classification
        LSTM(64, return_sequences=False, name="lstm_layer_2"),
        Dropout(0.5, name="dropout_2"),
        
        # Output classification layer: maps 64 features to 6 activity classes
        Dense(num_classes, activation="softmax", name="output_layer")
    ])
    
    return model

if __name__ == "__main__":
    model = build_lstm_model()
    model.summary()
