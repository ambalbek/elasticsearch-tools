FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY classes/ ./classes/
COPY functions/ ./functions/
COPY scripts/ ./scripts/

ENV ES_HOST=""
ENV ES_API_KEY=""
ENV ES_VERIFY_CERTS=true

CMD ["python", "scripts/update_index_templates.py"]
