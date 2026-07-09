import os
import pandas as pd
import numpy as np

DATASET_DIR = r"c:\Users\Vibhish vs\EdgeSense\edge_sense\dataset\UCI HAR Dataset"

def print_section(title):
    print("\n" + "=" * 50)
    print(f" {title} ")
    print("=" * 50)

def main():
    print_section("UCI HAR Dataset - General Info")
    
    # 1. Activity Labels
    activity_file = os.path.join(DATASET_DIR, "activity_labels.txt")
    if os.path.exists(activity_file):
        labels = pd.read_csv(activity_file, sep=" ", header=None, names=["ID", "Activity"])
        print(f"Activity Labels Shape: {labels.shape}")
        print("Classes:\n", labels.to_string(index=False))
    
    # 2. Features
    features_file = os.path.join(DATASET_DIR, "features.txt")
    if os.path.exists(features_file):
        features = pd.read_csv(features_file, sep=r"\s+", header=None, names=["Index", "FeatureName"], engine="python")
        print(f"\nFeatures list Shape: {features.shape}")
        print("First 5 features:")
        print(features.head().to_string(index=False))
        print("Last 5 features:")
        print(features.tail().to_string(index=False))

    # 3. Main Data Files
    print_section("Main Dataset Shapes")
    for set_name in ["train", "test"]:
        x_path = os.path.join(DATASET_DIR, set_name, f"X_{set_name}.txt")
        y_path = os.path.join(DATASET_DIR, set_name, f"y_{set_name}.txt")
        sub_path = os.path.join(DATASET_DIR, set_name, f"subject_{set_name}.txt")
        
        if os.path.exists(x_path) and os.path.exists(y_path) and os.path.exists(sub_path):
            # Load shapes
            x_shape = (sum(1 for _ in open(x_path)), len(open(x_path).readline().split()))
            y_shape = (sum(1 for _ in open(y_path)), 1)
            sub_shape = (sum(1 for _ in open(sub_path)), 1)
            print(f"{set_name.capitalize()} Set:")
            print(f"  X_{set_name}.txt shape      : {x_shape}")
            print(f"  y_{set_name}.txt shape      : {y_shape}")
            print(f"  subject_{set_name}.txt shape: {sub_shape}")

    # 4. Inertial Signals
    print_section("Inertial Signals Shapes")
    inertial_files = [
        "body_acc_x", "body_acc_y", "body_acc_z",
        "body_gyro_x", "body_gyro_y", "body_gyro_z",
        "total_acc_x", "total_acc_y", "total_acc_z"
    ]
    
    for set_name in ["train", "test"]:
        print(f"\n{set_name.capitalize()} Inertial Signals (128 readings per sequence):")
        for f in inertial_files:
            file_path = os.path.join(DATASET_DIR, set_name, "Inertial Signals", f"{f}_{set_name}.txt")
            if os.path.exists(file_path):
                # Count rows and columns
                row_count = sum(1 for _ in open(file_path))
                first_line = open(file_path).readline().split()
                col_count = len(first_line)
                print(f"  {f}_{set_name}.txt shape: ({row_count}, {col_count})")

if __name__ == "__main__":
    main()
