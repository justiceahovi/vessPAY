# Multi-stage Dockerfile for VessPay Backend API
# Stage 1: Dependencies & Build
FROM node:20-alpine AS builder

WORKDIR /app

# Install openssl for Prisma
RUN apk add --no-cache openssl

# Copy package files
COPY package*.json ./
COPY prisma ./prisma/

# Install dependencies (runs prisma:generate via postinstall)
RUN npm ci

# Copy source code and tsconfig
COPY tsconfig.json ./
COPY src ./src

# Build TypeScript to dist
RUN npm run build

# Stage 2: Production Runtime
FROM node:20-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000

# Install openssl for Prisma engine runtime
RUN apk add --no-cache openssl dumb-init

# Copy package files & install production dependencies only
COPY package*.json ./
COPY prisma ./prisma/

RUN npm ci --only=production && npx prisma generate

# Copy compiled JavaScript output from builder
COPY --from=builder /app/dist ./dist

# Create non-root user for security
USER node

EXPOSE 3000

# Use dumb-init to handle PID 1 signal forwarding properly
CMD ["dumb-init", "node", "dist/index.js"]
