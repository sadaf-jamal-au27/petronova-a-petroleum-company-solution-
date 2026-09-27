FROM gcr.io/dataflow-templates-base/python311-template-launcher-base:latest
WORKDIR /template
COPY requirements.txt transforms.py pipeline.py ./
RUN pip install --no-cache-dir -r requirements.txt
ENV FLEX_TEMPLATE_PYTHON_PY_FILE=/template/pipeline.py \
    FLEX_TEMPLATE_PYTHON_REQUIREMENTS_FILE=/template/requirements.txt
