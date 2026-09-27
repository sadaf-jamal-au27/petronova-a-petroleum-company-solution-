# Build stage
FROM python:3.12-slim AS build
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --target=/deps -r requirements.txt

# Runtime: distroless, non-root (uid 65532), read-only root filesystem friendly
FROM gcr.io/distroless/python3-debian12:nonroot
WORKDIR /srv
COPY --from=build /deps /deps
COPY app ./app
ENV PYTHONPATH=/deps PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
EXPOSE 8080
USER 65532:65532
ENTRYPOINT ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--no-access-log"]
