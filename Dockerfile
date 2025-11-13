# Stage 1: Build the Go binary
FROM golang:1.24 AS builder

WORKDIR                                                                                     /app
COPY . .

# Install dependencies
RUN go mod tidy
# Build a statically linked binary suitable for Alpine
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o prufwerk .

# Stage 2: Create a minimal runtime image
FROM alpine:latest

RUN apk --no-cache add ca-certificates

WORKDIR /root/

# Copy the compiled binary from the builder stage
COPY --from=builder /app/prufwerk .

# Expose the application port
EXPOSE 8080

# Run the binary
CMD ["./prufwerk"]