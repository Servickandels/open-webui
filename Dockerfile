# syntax=docker/dockerfile:1

# 1) ##### Build-Stage: WebUI Frontend #####
FROM node:22-alpine3.20 AS build-frontend

WORKDIR /app/frontend

# Nur package.json und lock für Layer-Cache
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts

# Quellcode kopieren
COPY public ./public
COPY src    ./src

# Git-Hash ins Build einbetten (optional)
ARG BUILD_HASH=dev
ENV APP_BUILD_HASH=${BUILD_HASH}

# Frontend bauen
RUN npm run build


# 2) ##### Base-Image für Backend #####
FROM python:3.11-slim-bookworm AS base

# Build-Args für CUDA / OLLAMA / Modelle
ARG USE_CUDA=false
ARG USE_OLLAMA=false
ARG USE_CUDA_VER=cu128
ARG USE_EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2
ARG USE_RERANKING_MODEL=

# Standard-Umgebungsvariablen – werden zur Laufzeit von Coolify per .env/Secrets überschrieben
ENV \
    PORT=8080 \
    USE_CUDA_KEEP=${USE_CUDA} \
    USE_CUDA_VER_KEEP=${USE_CUDA_VER} \
    USE_OLLAMA_KEEP=${USE_OLLAMA} \
    USE_EMBEDDING_KEEP=${USE_EMBEDDING_MODEL} \
    USE_RERANK_KEEP=${USE_RERANKING_MODEL} \
    # weitere variablen wie OPENAI_API_KEY, WEBUI_SECRET_KEY etc.
    PYTHONUNBUFFERED=1

# System-Deps installieren (dazu nur einmal UPDATE/CLEANUP)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential curl git jq netcat-openbsd ffmpeg libsm6 libxext6 \
      pandoc gcc python3-dev && \
    rm -rf /var/lib/apt/lists/*

# Arbeitsverzeichnis Backend
WORKDIR /app/backend

# Nur requirements.txt für Layer-Cache
COPY backend/requirements.txt ./

RUN pip install --no-cache-dir -r requirements.txt

# 3) ##### Final-Stage #####
FROM base AS final

# Erstelle User (UID/GID per Build-Arg oder Default 1000)
ARG UID=1000
ARG GID=1000
RUN groupadd -g ${GID} app && \
    useradd -r -u ${UID} -g ${GID} app

# Quellcode kopieren
COPY --chown=app:app backend    ./backend
COPY --chown=app:app start.sh   ./start.sh

# Frontend-Build ins Image holen
COPY --from=build-frontend /app/frontend/build /app/build

# Rechte setzen
RUN chown -R app:app /app

# Laufzeit-User
USER app

# Port und EntryPoint
EXPOSE 8080
CMD ["bash", "start.sh"]
