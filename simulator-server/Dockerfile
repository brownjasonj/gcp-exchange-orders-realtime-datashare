FROM node:20-slim

WORKDIR /app

COPY package*.json ./
COPY tsconfig.json ./

RUN npm ci

COPY src ./src
COPY config.json ./

RUN npm run build

ENV PORT=8080
EXPOSE 8080

CMD ["npm", "start"]
