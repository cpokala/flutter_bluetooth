import os
import numpy as np
import json
from sklearn.cluster import DBSCAN
from sklearn.preprocessing import StandardScaler
import joblib

def generate_training_data(n_samples=100):
    """Generate sample environmental data"""
    np.random.seed(42)

    # Generate realistic ranges
    voc_values = np.random.uniform(50, 300, n_samples)
    temp_values = np.random.uniform(20, 30, n_samples)
    pressure_values = np.random.uniform(1000, 1025, n_samples)
    humidity_values = np.random.uniform(30, 70, n_samples)

    # Create patterns
    for i in range(n_samples):
        if i % 3 == 0:
            voc_values[i] += 50
            temp_values[i] += 2
            humidity_values[i] += 10

    X = np.column_stack([
        voc_values,
        temp_values,
        pressure_values,
        humidity_values
    ]).astype(np.float32)

    return X

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