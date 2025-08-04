# syntax=docker/dockerfile:1
#### 1) Frontend bauen ####
FROM node:22-alpine3.20 AS build-frontend
WORKDIR /app/frontend

# 1.1 Nur package.json & lock für npm-Cache
COPY package.json package-lock.json ./
RUN npm ci

# 1.2 Nur Quellcode kopieren (src + static + config)
COPY src ./src
COPY static ./static
COPY svelte.config.js vite.config.ts postcss.config.js tailwind.config.js ./

# 1.3 Build
RUN npm run build

#### 2) Backend vorbereiten ####
FROM python:3.11-slim-bookworm AS build-backend
WORKDIR /app/backend

# Minimal benötigte Systempakete
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       build-essential curl git jq netcat-openbsd \
       ffmpeg libsm6 libxext6 pandoc gcc python3-dev \
  && rm -rf /var/lib/apt/lists/*

# 2.1 Requirements
COPY backend/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

#### 3) Finales, schlankes Runtime-Image ####
FROM python:3.11-slim-bookworm AS runtime
ARG USE_CUDA=false
ARG USE_OLLAMA=false
ARG USE_CUDA_VER=cu128
ENV ENV=prod \
    PORT=8080 \
    USE_CUDA_DOCKER=${USE_CUDA} \
    USE_CUDA_DOCKER_VER=${USE_CUDA_VER} \
    USE_OLLAMA_DOCKER=${USE_OLLAMA}

# Nur die minimalen Laufzeit-Abhängigkeiten
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       netcat-openbsd curl jq \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 3.1 Das fertige Frontend
COPY --from=build-frontend /app/frontend/build /app/build

# 3.2 Das fertig installierte Backend
COPY --from=build-backend /app/backend /app/backend

# 3.3 Starter-Script
COPY start.sh ./
RUN chmod +x start.sh

EXPOSE 8080
HEALTHCHECK CMD curl --silent --fail http://localhost:${PORT}/health || exit 1

CMD ["bash", "./start.sh"]
