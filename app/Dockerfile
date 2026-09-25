FROM python:3.13-alpine

WORKDIR /app

COPY app.py .

RUN addgroup -S appgroup && \
    adduser -S appuser -G appgroup && \
    chown -R appuser:appgroup /app

USER appuser

EXPOSE 8080

CMD ["python", "app.py"]
