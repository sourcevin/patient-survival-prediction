import gradio as gr
import xgboost as xgb
import numpy as np
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, filename='/var/log/app.log', filemode='a', format='%(asctime)s - %(levelname)s - %(message)s')

# Load pre-trained model
model = xgb.Booster()
model.load_model('model/xgboost_model.json')

def validate_inputs(age, ejection_fraction, serum_creatinine):
    if not (0 < age < 120):
        return False, "Age must be between 1 and 120."
    if not (0 < ejection_fraction <= 100):
        return False, "Ejection Fraction must be between 1 and 100."
    if not (0 < serum_creatinine < 20):
        return False, "Serum Creatinine should be realistic (typically below 20)."
    return True, None

def predict_survival(age, ejection_fraction, serum_creatinine):
    is_valid, error_message = validate_inputs(age, ejection_fraction, serum_creatinine)
    if not is_valid:
        logging.error(f"Invalid input: {error_message}")
        return error_message

    logging.info(f"Received inputs - Age: {age}, EF: {ejection_fraction}, Serum Creatinine: {serum_creatinine}")
    features = np.array([[age, ejection_fraction, serum_creatinine]])
    dmatrix = xgb.DMatrix(features)
    prediction = model.predict(dmatrix)
    result = "Survived" if prediction[0] > 0.5 else "Did not survive"
    logging.info(f"Prediction result: {result}")
    return result

iface = gr.Interface(
    fn=predict_survival,
    inputs=["number", "number", "number"],
    outputs="text",
    title="Patient Survival Prediction",
    description="Predicts the survival of a patient based on clinical parameters."
)

iface.launch()