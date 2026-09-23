# Stage 1: Build stage to leverage uv
FROM python:3.14.7-slim-trixie AS builder

# Copy uv binary from the official image
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

#UV_COMPILE_BYTECODE environment variable to ensure that all commands within the Dockerfile compile bytecode
ENV UV_COMPILE_BYTECODE=1
#UV_LINK_MODE silences warnings about not being able to link files since the cache and sync target are on separate file systems.
ENV UV_LINK_MODE=copy
# Use the system Python across both stages
ENV UV_PYTHON_DOWNLOADS=0


# Set working directory
WORKDIR /app


# Install dependencies into a virtual environment
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-install-project --no-dev


COPY . /app

RUN  uv sync --locked --no-dev

# Stage 2: Final lightweight runtime image
FROM python:3.14.7-slim-trixie

WORKDIR /app

# Create non-root user
RUN useradd --create-home --shell /bin/bash appuserasif
# Give ownership to appuse
#RUN chown -R appuserasif:appuserasif /app #  /app is empty at that point — WORKDIR just created it, and the real files arrive on line 43 with their own --chown. Safe to delete.
# Run as non-root user
USER appuserasif

# Copy the virtual environment from the builder stage
COPY --from=builder  --chown=appuserasif:appuserasif /app  /app

# This ensure docker use your install python in /app/.venv/bin, without it you may run like this /app/.venv/bin/fastapi run main.py
# add this /app/.venv/bin before every system commands such as:/bin/sh , /usr/bin/..., 
# SO new PATH look like this
#PATH
#/app/.venv/bin <- this path is listed above, So app will run by this python
#/bin/sh
#/usr/local/bin/python <- this path is listed later, So app dont run by this python
ENV PATH="/app/.venv/bin:$PATH"

ENV PORT=8000

#This makes Python output appear immediately rather than being buffered and it is useful for Docker logs
ENV PYTHONUNBUFFERED=1

# Command to run FastAPI using the synced environment
# /bin/sh : Start the Linux shell /bin/sh and ask it to execute the following string.
# wihout exec The shell is the main process, and FastAPI is its child. docker > sh (PID 1)> fastapi
# with exec The shell is replaced. docker > fastapi (PID 1)
#Depending on the shell/process behavior, signal handling can be less predictable. That's why production containers commonly use exec.
# For example: Docker sends signals to the main process when the container needs to stop. docker stop > SIGTERM > PID 1
CMD ["/bin/sh", "-c", "exec fastapi run --host 0.0.0.0 --port \"$PORT\" "]

