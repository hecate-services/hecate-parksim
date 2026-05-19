# Multi-stage Erlang build for hecate-parksim-simulator.
# Pushed to ghcr.io/hecate-services/hecate-parksim-simulator:latest + :semver.
#
# Unlike the sibling parksim CMD apps, the simulator depends on `macula`
# (the SDK), which carries Rust NIFs (Quinn-backed macula_quic). That
# pulls in rustup + a current toolchain, mirroring hecate-daemon's image.

#----------------------------------------------------------------------
# Stage 1 — builder: Erlang + rustup + rebar3 + deps
#----------------------------------------------------------------------
FROM docker.io/erlang:27-alpine AS builder

RUN apk add --no-cache \
    git curl bash \
    build-base cmake \
    perl linux-headers

# Rust via rustup (Alpine's rustc is too old for macula's NIF deps).
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"
# musl-targeted rustup defaults to crt-static; cdylib NIFs need it off.
ENV RUSTFLAGS="-C target-feature=-crt-static"

WORKDIR /build
COPY rebar.config ./
COPY src ./src
COPY apps ./apps
COPY config ./config

RUN rebar3 as prod tar

#----------------------------------------------------------------------
# Stage 2 — runtime: slim image, just the release tarball
#----------------------------------------------------------------------
FROM docker.io/alpine:3.20

RUN apk add --no-cache libstdc++ ncurses-libs openssl ca-certificates

WORKDIR /app
COPY --from=builder /build/_build/prod/rel/hecate_parksim_simulator/*.tar.gz /tmp/release.tar.gz
RUN tar xf /tmp/release.tar.gz && rm /tmp/release.tar.gz

VOLUME ["/etc/hecate/secrets", "/var/lib/hecate-parksim-simulator"]

ENTRYPOINT ["/app/bin/hecate_parksim_simulator"]
CMD ["foreground"]
