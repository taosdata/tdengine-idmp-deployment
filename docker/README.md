# TDengine IDMP Docker Project

English | [简体中文](README-CN.md)

This project provides a Dockerized version of the TDengine IDMP application. It includes all necessary files to build, run, and deploy the TDengine IDMP application using Docker and Docker Compose.

## Project Structure

```
TDengine IDMP docker
│── Dockerfile                # Instructions to build the TDengine IDMP Docker image
│── entrypoint.sh             # Script to initialize the TDengine IDMP application
│── docker-compose.yml        # Standard deployment configuration (TSDB Enterprise + IDMP)
│── docker-compose-tdgpt.yml  # Full deployment configuration (TSDB Enterprise + IDMP + TDgpt)
│── init-anode.sql            # TDengine anode initialization script
│── README.md                 # English project documentation
└── README-CN.md              # Chinese project documentation
```

## Prerequisites

- Docker: Ensure that Docker is installed and running on your machine.
- Docker Compose: Ensure that Docker Compose is installed.

## Building the Docker Image

To build the TDengine IDMP Docker image, navigate to the project directory and run the following command:

**Note:** Please replace `<version>` with the actual version number.

```bash
docker build \
  -t tdengine/idmp-ee:<version> \
  --build-arg DOWNLOAD_URL="https://downloads.taosdata.com/tdengine-idmp-enterprise/<version>/tdengine-idmp-enterprise-<version>-linux-generic.tar.gz" .
docker tag tdengine/idmp-ee:<version> tdengine/idmp-ee:latest
```

## Deployment Options

This project provides two deployment options:

### Option 1: Standard Deployment (Recommended for Development)

Includes only TDengine TSDB Enterprise and IDMP services, without AI functionality:

```bash
# Start standard services
docker compose up -d

# Stop services
docker compose down
```

**Service Ports:**
- **6030**: TDengine TSDB Enterprise client connection port
- **6041**: TDengine TSDB Enterprise REST API port
- **6060**: TDengine TSDB Enterprise management system frontend port
- **6042**: IDMP Web frontend port
- **8082**: IDMP h2 service port

### Option 2: Full Deployment (With AI Features)

Includes the complete TDengine ecosystem and AI analysis capabilities:

```bash
# Start complete services
docker compose -f docker-compose-tdgpt.yml up -d

# Stop services
docker compose -f docker-compose-tdgpt.yml down
```

**Additional Ports:**
- **6090**: TDgpt main service port
- **5000**: Model service port
- **5001**: Extended model service port

**Service Startup Order:**
1. **TDgpt Service**: Starts first, providing AI analysis capabilities
2. **TDengine TSDB Enterprise**: Starts after TDgpt health check passes, automatically creates anode connection
3. **IDMP Service**: Starts last, depends on TSDB Enterprise service running normally

## Health Checks

All services are configured with health check mechanisms to ensure services start in the correct order:
- **TDgpt**: Checks port 6090 availability
- **TSDB Enterprise**: Checks database connection status
- **IDMP**: Checks port 6042 availability

## Image Configuration

### TDgpt Image Versions

To use the full version TDgpt image, modify the image configuration in `docker-compose-tdgpt.yml`:

```yaml
services:
  tdengine-tdgpt:
    image: tdengine/tdgpt-full:latest  # Full version image
    # or
    image: tdengine/tdgpt:latest       # Standard version image
```

## Usage Recommendations

- **Development Environment**: Use the standard `docker-compose.yml` for basic requirements
- **AI Features Needed**: Use `docker-compose-tdgpt.yml` for complete functionality
- **Production Environment**: Choose the appropriate configuration file based on actual business needs