# syntax=docker/dockerfile:1

FROM alpine:3.21@sha256:bc21487101ae47172509130ee1092cc273a831968d64b617776d1f69c81e42ab AS source

RUN apk add --no-cache ca-certificates git

WORKDIR /src

RUN git clone https://github.com/pwaller/pyfiglet.git . \
    && git checkout 255827efbc09d662875dad50fa0edc1e1263bf45 \
    && rm -rf .git \
              pyfiglet/fonts-contrib \
              test-fonts \
    && mkdir -p pyfiglet/fonts \
    && cp pyfiglet/fonts-standard/* pyfiglet/fonts/

FROM golang:1.23-alpine@sha256:383395b794dffa5b53012a212365d40c8e37109a626ca30d6151c8348d380b5f

RUN apk add --no-cache bash \
    && addgroup -g 1000 player \
    && adduser -D -u 1000 -G player -h /home/player -s /bin/bash player

ENV CGO_ENABLED=0 \
    GOTOOLCHAIN=local

COPY --from=source --chown=player:player /src /workspace/repo

USER player
WORKDIR /workspace/repo
