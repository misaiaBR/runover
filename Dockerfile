FROM debian:bookworm-slim AS frontend

ARG FLUTTER_VERSION=3.47.2
ARG FLUTTER_SDK_SHA256=447878859d01ca9bfdb99a85f245af07ed8a15fedcd9d189c4749e8e92d1f185
ENV FLUTTER_HOME=/opt/flutter \
    PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:$PATH \
    CI=true

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl git libglu1-mesa unzip xz-utils zip \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o /tmp/flutter.tar.xz \
  && echo "${FLUTTER_SDK_SHA256}  /tmp/flutter.tar.xz" | sha256sum -c - \
  && tar -xJf /tmp/flutter.tar.xz -C /opt \
  && rm /tmp/flutter.tar.xz \
  && git config --global --add safe.directory /opt/flutter \
  && flutter config --no-analytics

WORKDIR /workspace/app
COPY app/pubspec.yaml app/pubspec.lock ./
RUN flutter pub get --enforce-lockfile
COPY app/ ./
# IDs públicos do OAuth Google (vão embutidos no JS; sem segredo).
RUN flutter build web --release \
  --dart-define=API_BASE=https://runover.onrender.com \
  --dart-define=GOOGLE_WEB_CLIENT_ID=346362177621-g8li6h47ic6sot55p68700a0lgpqo01v.apps.googleusercontent.com \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=346362177621-g8li6h47ic6sot55p68700a0lgpqo01v.apps.googleusercontent.com

FROM python:3.15-slim

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
# Atrás do proxy do Render (Cloudflare + balanceadores), o IP do socket é
# sempre o do proxy: sem --proxy-headers o throttle por IP do auth
# (register/login/reset) enxergaria um usuário só e um azarado esgotaria o
# budget do outro. Só confia no X-Forwarded-For vindo da infra listada em
# FORWARDED_ALLOW_IPS (ver render.yaml); fora dela, nada muda.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-10000} --proxy-headers --forwarded-allow-ips \"${FORWARDED_ALLOW_IPS:-127.0.0.1}\""]
