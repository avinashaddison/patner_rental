# Companion Ranchi backend — production image.
FROM node:20-alpine

# OpenSSL is required by Prisma on Alpine.
RUN apk add --no-cache openssl

WORKDIR /app

# Install dependencies (cache-friendly).
COPY package*.json ./
RUN npm install --omit=dev

# Copy source + Prisma schema, then generate the client.
COPY prisma ./prisma
RUN npx prisma generate

COPY . .

ENV NODE_ENV=production
# Render (and most PaaS) inject PORT at runtime; config reads env.PORT.
EXPOSE 4000

# This project is schema-push managed (no prisma/migrations), and the Supabase
# DB already exists and is owned externally — so we do NOT run migrations on
# boot. Schema changes are applied deliberately with `prisma db push`, never here.
CMD ["node", "src/server.js"]
