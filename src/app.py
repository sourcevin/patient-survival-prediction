# src/app.py
import gradio as gr
import pickle
import numpy as np
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from flask import Flask, Response
import threading

# Initialize Flask app for Prometheus metrics
app = Flask(__name__)

# Load the trained model
with open("/app/models/survival_model.pkl", "rb") as f:
    model = pickle.load(f)

# Define Prometheus metrics
REQUEST_COUNT = Counter("prediction_requests_total", "Total number of prediction requests")
REQUEST_LATENCY = Histogram("prediction_request_latency_seconds", "Latency of prediction requests")

# Define prediction function with Prometheus metrics
def predict_survival(input_data):
    REQUEST_COUNT.inc()  # Increment request count

    with REQUEST_LATENCY.time():  # Measure request latency
        # Assuming input_data is a comma-separated string of numbers
        input_features = np.array([float(i) for i in input_data.split(",")]).reshape(1, -1)
        prediction = model.predict(input_features)
        return "Survived" if prediction[0] == 1 else "Not Survived"

# Define Gradio Interface
iface = gr.Interface(fn=predict_survival, inputs="text", outputs="text")

# Prometheus metrics endpoint
@app.route("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

# Function to run Flask app in a separate thread
def run_flask():
    app.run(host="0.0.0.0", port=8000)

# Run Gradio and Flask together
if __name__ == "__main__":
    # Start Flask app in a new thread
    flask_thread = threading.Thread(target=run_flask)
    flask_thread.start()

    # Start Gradio app
    iface.launch(server_name="0.0.0.0", server_port=7860)  # Ensure different port for Gradio