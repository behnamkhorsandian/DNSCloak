FROM golang:1.21-alpine AS builder

RUN apk add --no-cache git && \
    git clone https://github.com/nickolasburr/slipstream.git /build/slipstream && \
    cd /build/slipstream && \
    go build -ldflags="-s -w" -o /build/slipstream-server .

FROM alpine:3.19

LABEL org.opencontainers.image.description="Vany Slipstream DNS tunnel"

RUN apk add --no-cache ca-certificates

COPY --from=builder /build/slipstream-server /usr/local/bin/slipstream-server
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/etc/slipstream"]

EXPOSE 53/udp

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD pgrep slipstream-server >/dev/null || exit 1

ENTRYPOINT ["/entrypoint.sh"]
