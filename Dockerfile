# syntax=docker/dockerfile:1.7

FROM cgr.dev/chainguard/node:latest-dev AS build

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build

FROM cgr.dev/chainguard/nginx:latest

COPY docker/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 8080
