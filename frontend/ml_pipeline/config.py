import os

# Paths
BASE_DIR = r"c:\Users\Vibhish vs\EdgeSense\edge_sense"
DATASET_DIR = os.path.join(BASE_DIR, "dataset", "UCI HAR Dataset")
OUTPUT_DIR = os.path.join(BASE_DIR, "ml_pipeline", "output")

# Create output dir if it doesn't exist
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Model configuration
SEQ_LEN = 128
NUM_CHANNELS = 6  # 3 total_acc (raw accelerometer) + 3 body_gyro (gyroscope)
NUM_CLASSES = 6

# Training Hyperparameters
BATCH_SIZE = 64
EPOCHS = 30
LEARNING_RATE = 0.001
VALIDATION_SPLIT = 0.2  # 20% of train set will be used for validation

# Activity labels mapping (0-indexed to match label encoding)
ACTIVITY_LABELS = {
    0: "WALKING",
    1: "WALKING_UPSTAIRS",
    2: "WALKING_DOWNSTAIRS",
    3: "SITTING",
    4: "STANDING",
    5: "LAYING"
}

# Gravity constant for unit conversion (Flutter sends m/s², UCI uses 'g')
GRAVITY = 9.80665
