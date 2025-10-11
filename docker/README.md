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
│── idmp.sh                   # Interactive startup/stop script
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
  --build-arg DOWNLOAD_URL="https://downloads.tdengine.com/tdengine-idmp-enterprise/<version>/tdengine-idmp-enterprise-<version>-linux-generic.tar.gz" .
docker tag tdengine/idmp-ee:<version> tdengine/idmp-ee:latest
```

## Quick Start (Recommended)

### Using the Interactive Startup Script

The easiest way to start the TDengine IDMP services is using the interactive startup script:

```bash
# Make the script executable
chmod +x idmp.sh

# Start services (interactive mode)
./idmp.sh start

# Stop services (auto-detect running services)
./idmp.sh stop

# Show help
./idmp.sh -h
```

The script will:

#### Starting Services (`./idmp.sh start`)
1. **Check Docker Compose**: Automatically detect whether `docker-compose` or `docker compose` command is available
2. **Select Deployment Mode**: Interactive prompt to choose between:
   - Standard deployment (TSDB Enterprise + IDMP)
   - Full deployment (TSDB Enterprise + IDMP + TDgpt)
3. **Configure IDMP URL**: Automatically detect your host IP and set the IDMP_URL environment variable
4. **Start Services**: Launch the selected services with proper configuration

#### Stopping Services (`./idmp.sh stop`)
- **Smart Detection**: Automatically detects which deployment mode is currently running by checking container names
- **Intelligent Stopping**: Uses the correct docker-compose file based on detected containers:
  - If `tdengine-tdgpt` containers are found → uses `docker-compose-tdgpt.yml`
  - If standard `tdengine-idmp` or `tdengine-tsdb` containers are found → uses `docker-compose.yml`
- **Volume Management**: Interactive prompt to choose whether to clean volumes:
  - **Default behavior**: Preserves data volumes for safety
  - **Optional cleanup**: Choose to remove volumes if data persistence is not needed
- **Safe Operation**: Prevents errors by detecting the correct configuration automatically

## Manual Deployment Options

This project provides two deployment options:

### Environment Variable Configuration

Before starting services manually, you need to set the `IDMP_URL` environment variable. This variable is used by the IDMP service to configure the web console access URL.

```bash
# Set the IDMP_URL environment variable (replace with your actual IP)
export IDMP_URL="http://your-host-ip:6042"
```

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
- **6035**: TDgpt main service port
- **6036**: Model service port
- **6037**: Extended model service port

**Service Startup Order:**
1. **TDgpt Service**: Starts first, providing AI analysis capabilities
2. **TDengine TSDB Enterprise**: Starts after TDgpt health check passes, automatically creates anode connection
3. **IDMP Service**: Starts last, depends on TSDB Enterprise service running normally

## Health Checks

All services are configured with health check mechanisms to ensure services start in the correct order:
- **TDgpt**: Checks port 6035 availability
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