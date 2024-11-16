# Dockerfile
FROM python:3.9-slim

# Install gcc and other dependencies
RUN apt-get update && apt-get install -y gcc

# Set working directory
WORKDIR /app

# Copy dependencies and install them
COPY requirements.txt .
RUN pip install -r requirements.txt

# Copy all source and model directories
COPY src/ src/

COPY data/ data/

RUN mkdir models  # Ensure the models directory exists in the container

# Run the training script to generate the model
RUN python src/train_model.py

# Expose port for Gradio
EXPOSE 7860

EXPOSE 9000

# Run the Gradio application
CMD ["python", "src/app.py"]