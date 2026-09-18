FROM python:3.12-slim

# Prevent python from writing pyc files and buffering stdout/stderr
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Install dependencies
COPY producer/requirements.txt /app/producer-requirements.txt
RUN pip install --no-cache-dir -r /app/producer-requirements.txt

# Copy schemas package and app code
COPY schemas/ /app/schemas/
COPY producer/ /app/producer/

# Create a non-root user and group
RUN groupadd -g 1000 appgroup && \
    useradd -u 1000 -g appgroup -m -s /bin/bash appuser

# Set ownership
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER 1000

# Expose port
EXPOSE 8080

CMD ["python", "producer/app.py"]
