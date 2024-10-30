# Patient Survival Prediction

This project predicts the survival of patients with heart failure using an XGBoost model. The application is deployed on AWS ECS and can be accessed via a public endpoint.

## Project Setup

1. Install Python dependencies:
    ```bash
    pip install -r requirements.txt
    ```

2. Train the model and save it in `app/model/xgboost_model.json`.

3. Deploy using GitHub Actions workflow.