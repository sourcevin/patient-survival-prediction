# src/app.py
import gradio as gr
import pickle
import numpy as np

# Load the trained model
with open("/app/models/survival_model.pkl", "rb") as f:
    model = pickle.load(f)

# Define prediction function
def predict_survival(input_data):
    # Assuming input_data is a comma-separated string of numbers
    input_features = np.array([float(i) for i in input_data.split(",")]).reshape(1, -1)
    prediction = model.predict(input_features)
    return "Survived" if prediction[0] == 1 else "Not Survived"

# Define Gradio Interface
iface = gr.Interface(fn=predict_survival, inputs="text", outputs="text")
iface.launch(server_name="0.0.0.0")