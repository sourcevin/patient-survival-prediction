import numpy as np
import pandas as pd
import joblib
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, f1_score
from xgboost import XGBClassifier
import gradio as gr

# Load data
df = pd.read_csv('data/heart_failure_clinical_records_dataset.csv')

# Handle outliers
outlier_columns = ['creatinine_phosphokinase', 'ejection_fraction', 'platelets', 'serum_creatinine', 'serum_sodium']
df1 = df.copy()

def handle_outliers(df, colm):
    '''Change the values of outliers to upper and lower whisker values.'''
    df[colm] = df[colm].astype(float)  # Ensure float dtype
    q1 = df[colm].quantile(0.25)
    q3 = df[colm].quantile(0.75)
    iqr = q3 - q1
    lower_bound = q1 - (1.5 * iqr)
    upper_bound = q3 + (1.5 * iqr)
    df[colm] = np.where(df[colm] > upper_bound, upper_bound, df[colm])
    df[colm] = np.where(df[colm] < lower_bound, lower_bound, df[colm])
    return df

for colm in outlier_columns:
    df1 = handle_outliers(df1, colm)

# Split data into features and target
X = df1.drop('DEATH_EVENT', axis=1).values
y = df1['DEATH_EVENT'].values

# Train-test split
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.3, stratify=y, random_state=123)

# Train the model
xgb_clf = XGBClassifier(n_estimators=200, max_depth=4, max_leaves=5, random_state=42)
xgb_clf.fit(X_train, y_train)

# Evaluate the model
train_acc = accuracy_score(y_train, xgb_clf.predict(X_train))
test_acc = accuracy_score(y_test, xgb_clf.predict(X_test))
print("Training accuracy: ", train_acc)
print("Testing accuracy: ", test_acc)

train_f1 = f1_score(y_train, xgb_clf.predict(X_train))
test_f1 = f1_score(y_test, xgb_clf.predict(X_test))
print("Training F1 score: ", train_f1)
print("Testing F1 score: ", test_f1)

# Save the model
save_file_name = "xgboost-model.pkl"
joblib.dump(xgb_clf, save_file_name)
