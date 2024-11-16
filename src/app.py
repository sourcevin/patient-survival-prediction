# src/app.py
import gradio as gr
import pickle
import numpy as np
#from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
#from flask import Flask, Response
import threading
import joblib

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
    prediction = loaded_model.predict(input_data)
    return "Survived" if prediction[0] == 0 else "Did not survive"

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


    # Start Gradio app
iface.launch(server_name="0.0.0.0", server_port=7860)  # Ensure different port for Gradio
