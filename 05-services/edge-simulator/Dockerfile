FROM python:3.12-slim
RUN pip install --no-cache-dir paho-mqtt==2.1.0 && useradd -u 65532 edge
COPY edge.py /app/edge.py
USER 65532
ENTRYPOINT ["python", "/app/edge.py"]
