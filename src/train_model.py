# src/train_model.py
import pickle
from xgboost import XGBClassifier
from sklearn.model_selection import train_test_split
from sklearn.datasets import load_iris

# Load sample data (replace with actual dataset if available)
data = load_iris()
X, y = data.data, data.target
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# Train the model
model = XGBClassifier()
model.fit(X_train, y_train)

# Save the trained model to /app/models/survival_model.pkl
with open("/app/models/survival_model.pkl", "wb") as f:
    pickle.dump(model, f)