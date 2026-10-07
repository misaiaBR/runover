FROM ghcr.io/cirruslabs/flutter:stable AS frontend

WORKDIR /workspace/app
COPY app/pubspec.yaml app/pubspec.lock ./
RUN flutter pub get
COPY app/ ./
# ID público do OAuth Google (vai embutido no JS; sem segredo).
RUN flutter build web --release \
  --dart-define=API_BASE=https://runover.onrender.com \
  --dart-define=GOOGLE_WEB_CLIENT_ID=346362177621-g8li6h47ic6sot55p68700a0lgpqo01v.apps.googleusercontent.com

FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /srv
COPY backend/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY backend/app ./app
COPY backend/alembic.ini ./alembic.ini
COPY backend/alembic ./alembic
COPY --from=frontend /workspace/app/build/web ./static

EXPOSE 10000
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-10000}"]
