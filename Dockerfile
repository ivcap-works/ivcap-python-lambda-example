FROM python:3.9-slim-bullseye AS builder

WORKDIR /app
RUN pip install -U pip poetry
RUN poetry install

# Get service files
ADD lambda.py eliza ./
RUN mv lambda.py service.py

# VERSION INFORMATION
ARG GIT_TAG ???
ARG GIT_COMMIT ???
ARG BUILD_DATE ???

ENV IVCAP_SERVICE_VERSION $GIT_TAG

ENV IVCAP_SERVICE_COMMIT $GIT_COMMIT
ENV IVCAP_SERVICE_BUILD $BUILD_DATE

# Command to run
ENTRYPOINT ["fastapi", "run", "/app/service.py"]