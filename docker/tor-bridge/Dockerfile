FROM debian:bookworm-slim

LABEL org.opencontainers.image.description="Vany Tor Bridge (obfs4)"

RUN apt-get update && apt-get install -y --no-install-recommends \
    tor obfs4proxy ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/lib/tor && chown -R debian-tor:debian-tor /var/lib/tor

VOLUME ["/etc/tor", "/var/lib/tor"]

EXPOSE 9001/tcp

HEALTHCHECK --interval=60s --timeout=10s --retries=3 \
    CMD pgrep tor >/dev/null || exit 1

USER debian-tor

ENTRYPOINT ["tor", "-f", "/etc/tor/torrc"]
