# TumorTwin demo runner image
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1

WORKDIR /app

# System deps required for scientific Python wheels that compile extensions
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        git \
    && rm -rf /var/lib/apt/lists/*

# Preinstall CPU-only PyTorch to avoid pulling CUDA toolkits by default
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu

# Copy project files and install
COPY . /app

RUN pip install --no-cache-dir .

ENTRYPOINT ["python", "/app/docker/run_demo.py"]
CMD ["--task", "HGG"]
