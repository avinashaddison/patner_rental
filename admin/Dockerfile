# ---- Build stage ----
FROM node:20-alpine AS builder
WORKDIR /app

# Install dependencies based on lockfile when present
COPY package.json package-lock.json* ./
RUN npm install

COPY . .

# NEXT_PUBLIC_* must be present at build time to be inlined into the bundle.
ARG NEXT_PUBLIC_API_BASE_URL=http://localhost:4000
ENV NEXT_PUBLIC_API_BASE_URL=$NEXT_PUBLIC_API_BASE_URL

RUN npm run build

# ---- Runtime stage ----
FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
# Do NOT hardcode PORT — the host (Render) injects it and `next start` honours it.

RUN addgroup -g 1001 -S nodejs && adduser -S nextjs -u 1001

COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/public ./public
COPY --from=builder /app/next.config.mjs ./next.config.mjs

USER nextjs
EXPOSE 3000
CMD ["npm", "run", "start"]
