# Stage 1: Build the Go binary
FROM golang:1.24 AS builder

WORKDIR /app
# This copies the entire repo (including cmd/heimdall) into /app
COPY . .

# Install CA certs now so we can copy them into the scratch image later
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Install dependencies
RUN go mod tidy

# Build a statically linked binary from the NEW location
# UPDATED: Pointing to ./cmd/heimdall instead of .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o prufwerk ./cmd/heimdall

# Stage 2: copy only what we need into a distroless scratch image
FROM scratch

WORKDIR /root/

# Copy the compiled binary from the builder stage
# Include CA certificates for outbound TLS
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /app/prufwerk ./prufwerk

# Expose the application port
EXPOSE 8080

# Run the binary
ENTRYPOINT ["/root/prufwerk"]