# See here for image contents: https://github.com/microsoft/vscode-dev-containers/tree/v0.202.5/containers/python-3/.devcontainer/base.Dockerfile
FROM mcr.microsoft.com/vscode/devcontainers/python:0-3.7-bullseye

# [Optional] Uncomment this section to install additional OS packages.
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    libgmp3-dev \
    software-properties-common && \
   rm -rf /var/lib/apt/lists/*

RUN pip install poetry

COPY poetry.lock .
COPY poetry.toml .
COPY pyproject.toml .

RUN poetry install
