FROM node:22-bookworm-slim

WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*
ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=8787 \
    DATA_DIRECTORY=/data \
    APPLE_BUNDLE_ID=com.gregadams.myfurbaby \
    APPLE_ENVIRONMENT=Sandbox \
    APPLE_APP_ID=6820522244 \
    APPLE_ROOT_CA_PATHS=/app/certificates/AppleIncRootCertificate.cer,/app/certificates/AppleRootCA-G2.cer,/app/certificates/AppleRootCA-G3.cer

COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY *.js ./
COPY certificates/*.cer ./certificates/
COPY tests/ ./tests/
RUN APPLE_ROOT_CA_PATHS='' npm test

# A host-mounted volume must be attached at /data before using the public service.
# Railway volumes are mounted as root; the single container owns this private disk.
RUN mkdir -p /data && chmod 700 /data
EXPOSE 8787
CMD ["node", "server.js"]
