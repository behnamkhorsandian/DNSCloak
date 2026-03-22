FROM golang:1.21-alpine AS builder

RUN apk add --no-cache git && \
    git clone https://github.com/nickolasburr/noizdns.git /build/noizdns && \
    cd /build/noizdns && \
    go build -ldflags="-s -w" -o /build/noizdns-server .

FROM alpine:3.19

LABEL org.opencontainers.image.description="Vany NoizDNS tunnel (DPI-resistant DNSTT fork)"

RUN apk add --no-cache ca-certificates

COPY --from=builder /build/noizdns-server /usr/local/bin/noizdns-server
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/etc/noizdns"]

EXPOSE 53/udp

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD pgrep noizdns-server >/dev/null || exit 1

ENTRYPOINT ["/entrypoint.sh"]
