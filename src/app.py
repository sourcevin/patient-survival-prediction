import gradio as gr
import numpy as np
import joblib
from prometheus_client import Gauge, generate_latest
from fastapi import FastAPI
from starlette.responses import Response

# FastAPI app for Prometheus metrics
app = FastAPI()

################################# Prometheus related code START ######################################################
# Prometheus metrics
prediction_count = Gauge("heart_failure_prediction_count", "Number of predictions made")
last_prediction_result = Gauge("last_prediction_result", "Last prediction result (1=Did not survive, 0=Survived)")

# Function for updating metrics
def update_metrics(prediction):
    prediction_count.inc()  # Increment prediction count
    last_prediction_result.set(prediction)

@app.get("/metrics")
async def get_metrics():
    return Response(content=generate_latest(), media_type="text/plain")
################################# Prometheus related code END ########################################################

# Load the trained model
save_file_name = "xgboost-model.pkl"
loaded_model = joblib.load(save_file_name)

# Prediction function
def predict_death_event(age, anaemia, creatinine_phosphokinase, diabetes, ejection_fraction, 
                        high_blood_pressure, platelets, serum_creatinine, serum_sodium, 
                        sex, smoking, time):
    input_data = np.array([[age, int(anaemia), creatinine_phosphokinase, int(diabetes), ejection_fraction,
                            int(high_blood_pressure), platelets, serum_creatinine, serum_sodium, 
                            int(sex), int(smoking), time]])
    prediction = loaded_model.predict(input_data)[0]  # 0 or 1
    update_metrics(prediction)  # Update Prometheus metrics
    return "Survived" if prediction == 0 else "Did not survive"

# Gradio interface
inputs = [
    gr.Number(label="Age"),
    gr.Radio(choices=[0, 1], label="Anaemia (0=No, 1=Yes)"),
    gr.Number(label="Creatinine Phosphokinase"),
    gr.Radio(choices=[0, 1], label="Diabetes (0=No, 1=Yes)"),
    gr.Number(label="Ejection Fraction"),
    gr.Radio(choices=[0, 1], label="High Blood Pressure (0=No, 1=Yes)"),
    gr.Number(label="Platelets"),
    gr.Number(label="Serum Creatinine"),
    gr.Number(label="Serum Sodium"),
    gr.Radio(choices=[0, 1], label="Sex (0=Female, 1=Male)"),
    gr.Radio(choices=[0, 1], label="Smoking (0=No, 1=Yes)"),
    gr.Number(label="Time"),
]

outputs = gr.Textbox(label="Prediction")

title = "Patient Survival Prediction"
description = "Predict survival of patients with heart failure based on clinical records."

iface = gr.Interface(fn=predict_death_event, inputs=inputs, outputs=outputs, 
                     title=title, description=description, allow_flagging='never')

if __name__ == "__main__":
    import uvicorn
    # Start Gradio in a thread and FastAPI for metrics
    import threading

    def run_gradio():
        iface.launch(server_name="0.0.0.0", server_port=7860)

    threading.Thread(target=run_gradio, daemon=True).start()

    # Start FastAPI app
    uvicorn.run(app, host="0.0.0.0", port=9000)
