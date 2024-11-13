import os
import numpy as np
import json
from sklearn.cluster import DBSCAN
from sklearn.preprocessing import StandardScaler
import joblib

def generate_training_data(n_samples=100):
    """Generate sample environmental data with clear density patterns"""
    np.random.seed(42)

    # Generate multiple gaussian clusters
    clusters = []

    # Dense cluster 1
    c1 = np.random.normal(loc=[100, 25, 1013, 45], scale=[5, 0.5, 1, 2], size=(n_samples//3, 4))
    clusters.append(c1)

    # Dense cluster 2
    c2 = np.random.normal(loc=[200, 28, 1018, 55], scale=[5, 0.5, 1, 2], size=(n_samples//3, 4))
    clusters.append(c2)

    # Scattered points
    noise = np.random.uniform(
        low=[50, 20, 1000, 30],
        high=[250, 30, 1025, 70],
        size=(n_samples//3, 4)
    )
    clusters.append(noise)

    # Combine all points
    X = np.vstack(clusters)

    # Ensure values are within realistic ranges
    X[:, 0] = np.clip(X[:, 0], 50, 300)    # VOC
    X[:, 1] = np.clip(X[:, 1], 20, 30)     # Temperature
    X[:, 2] = np.clip(X[:, 2], 1000, 1025) # Pressure
    X[:, 3] = np.clip(X[:, 3], 30, 70)     # Humidity

    return X.astype(np.float32)

def save_model_and_scaler(output_dir, eps=0.5, min_samples=5):
    """Create and save the model and scaler"""
    try:
        # Generate data
        print("Generating training data...")
        X_train = generate_training_data(200)

        # Scale the data
        print("Scaling data...")
        scaler = StandardScaler()
        X_scaled = scaler.fit_transform(X_train)

        # Save scaler parameters
        scaler_params = {
            'mean': scaler.mean_.tolist(),
            'scale': scaler.scale_.tolist()
        }

        scaler_path = os.path.join(output_dir, 'scaler_params.json')
        with open(scaler_path, 'w') as f:
            json.dump(scaler_params, f)
            print(f"Saved scaler parameters to {scaler_path}")

        # Create and save DBSCAN model
        print("Creating and fitting DBSCAN model...")
        dbscan = DBSCAN(eps=eps, min_samples=min_samples)
        dbscan.fit(X_scaled)

        # Save the model using joblib
        model_path = os.path.join(output_dir, 'dbscan_model.joblib')
        joblib.dump(dbscan, model_path)
        print(f"Saved model to {model_path}")

        # Test the saved model
        print("\nTesting saved model...")
        loaded_model = joblib.load(model_path)
        test_prediction = loaded_model.fit_predict(X_scaled[:1])
        print(f"Test successful! Model output: {test_prediction}")

        # Save sample predictions for verification
        sample_predictions = {
            'input_scaled': X_scaled[:5].tolist(),
            'predictions': loaded_model.fit_predict(X_scaled[:5]).tolist()
        }

        predictions_path = os.path.join(output_dir, 'sample_predictions.json')
        with open(predictions_path, 'w') as f:
            json.dump(sample_predictions, f)
            print(f"Saved sample predictions to {predictions_path}")

        return True

    except Exception as e:
        print(f"Error: {str(e)}")
        return False


def print(param):
    pass


def main():
    # Setup paths
    current_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(current_dir)
    assets_dir = os.path.join(project_root, 'assets')

    # Create assets directory if it doesn't exist
    if not os.path.exists(assets_dir):
        os.makedirs(assets_dir)
        print(f"Created assets directory: {assets_dir}")

    # Save model and scaler
    success = save_model_and_scaler(assets_dir)

    if success:
        print("\nModel creation completed successfully!")
    else:
        print("\nModel creation failed!")

if __name__ == "__main__":
    main()