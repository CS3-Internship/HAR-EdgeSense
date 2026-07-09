import os
import numpy as np
import matplotlib.pyplot as plt
import tensorflow as tf
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score, precision_recall_fscore_support
from ml_pipeline.config import OUTPUT_DIR, ACTIVITY_LABELS

def plot_confusion_matrix(cm, classes, save_path):
    """
    Plots the confusion matrix and saves it as an image.
    """
    plt.figure(figsize=(8, 6))
    plt.imshow(cm, interpolation='nearest', cmap=plt.cm.Blues)
    plt.title('Confusion Matrix', fontsize=14, fontweight='bold')
    plt.colorbar()
    
    tick_marks = np.arange(len(classes))
    plt.xticks(tick_marks, classes, rotation=45, ha="right", fontsize=9)
    plt.yticks(tick_marks, classes, fontsize=9)
    
    # Labeling individual cells
    fmt = 'd'
    thresh = cm.max() / 2.
    for i in range(cm.shape[0]):
        for j in range(cm.shape[1]):
            plt.text(j, i, format(cm[i, j], fmt),
                     horizontalalignment="center",
                     color="white" if cm[i, j] > thresh else "black")
            
    plt.ylabel('True label', fontsize=11, fontweight='bold')
    plt.xlabel('Predicted label', fontsize=11, fontweight='bold')
    plt.tight_layout()
    plt.savefig(save_path, dpi=300)
    plt.close()
    print(f"Confusion matrix plot saved to: {save_path}")

def main():
    print("--- INITIATING EVALUATION PIPELINE ---")
    
    # 1. Load scaled test data and labels
    x_test_path = os.path.join(OUTPUT_DIR, "X_test_scaled.npy")
    y_test_path = os.path.join(OUTPUT_DIR, "y_test.npy")
    
    if not os.path.exists(x_test_path) or not os.path.exists(y_test_path):
        raise FileNotFoundError("Scaled test data or labels not found in output directory. Please run train.py first.")
        
    X_test = np.load(x_test_path)
    y_test = np.load(y_test_path)
    
    # 2. Load the trained model
    model_path = os.path.join(OUTPUT_DIR, "best_model.keras")
    if not os.path.exists(model_path):
        model_path = os.path.join(OUTPUT_DIR, "final_model.keras")
        
    print(f"Loading model from: {model_path}")
    model = tf.keras.models.load_model(model_path)
    
    # 3. Perform prediction
    print("Running predictions on the test dataset...")
    y_pred_probs = model.predict(X_test, batch_size=64, verbose=1)
    y_pred = np.argmax(y_pred_probs, axis=1)
    
    # 4. Calculate overall performance metrics
    accuracy = accuracy_score(y_test, y_pred)
    precision, recall, f1, _ = precision_recall_fscore_support(y_test, y_pred, average='macro')
    
    print("\n" + "=" * 50)
    print(" EVALUATION METRICS (Test Set)")
    print("=" * 50)
    print(f"Accuracy  : {accuracy:.4f} ({accuracy * 100:.2f}%)")
    print(f"Precision : {precision:.4f} ({precision * 100:.2f}%)")
    print(f"Recall    : {recall:.4f} ({recall * 100:.2f}%)")
    print(f"F1-Score  : {f1:.4f} ({f1 * 100:.2f}%)")
    print("=" * 50)
    
    # 5. Generate and print classification report
    target_names = [ACTIVITY_LABELS[i] for i in sorted(ACTIVITY_LABELS.keys())]
    print("\nClassification Report:")
    report = classification_report(y_test, y_pred, target_names=target_names)
    print(report)
    
    # Save classification report as text
    report_path = os.path.join(OUTPUT_DIR, "classification_report.txt")
    with open(report_path, "w") as f:
        f.write(report)
    print(f"Classification report saved to: {report_path}")
    
    # 6. Compute and plot confusion matrix
    cm = confusion_matrix(y_test, y_pred)
    cm_path = os.path.join(OUTPUT_DIR, "confusion_matrix.png")
    plot_confusion_matrix(cm, target_names, cm_path)
    
    print("\n--- EVALUATION COMPLETED ---")

if __name__ == "__main__":
    main()
