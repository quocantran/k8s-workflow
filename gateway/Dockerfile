# Stage 1: Build
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json tsconfig.json ./
RUN npm install --quiet
COPY src ./src
RUN npm run build

# Stage 2: Production Runner
FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
RUN npm install --omit=dev --quiet && npm cache clean --force
COPY --from=builder /app/dist ./dist

USER node
EXPOSE 8080
CMD ["node", "dist/main.js"]
