# TDengine IDMP Docker Project

English | [简体中文](README-CN.md)

This project provides a Dockerized version of the TDengine IDMP application. It includes all necessary files to build, run, and deploy the TDengine IDMP application using Docker and Docker Compose.

## Project Structure

```
TDengine IDMP docker
│── Dockerfile           # Instructions to build the TDengine IDMP Docker image
│── entrypoint.sh        # Script to initialize the TDengine IDMP application
│── docker-compose.yml   # Configuration for deploying TDengine IDMP with Docker Compose
└── README.md            # Documentation for the project
```

## Prerequisites

- Docker: Ensure that Docker is installed and running on your machine.
- Docker Compose: Ensure that Docker Compose is installed.

## Building the Docker Image

To build the TDengine IDMP Docker image, navigate to the project directory and run the following command:

**Note:** Please replace `<version>` with the actual version number.

```bash
docker build \
  -t tdengine/tdengine-idmp:<version> \
  --build-arg DOWNLOAD_URL="https://downloads.tdengine.com/tdengine-idmp-enterprise/<version>/tdengine-idmp-enterprise-<version>-linux-generic.tar.gz" .
docker tag tdengine/tdengine-idmp:<version> tdengine/tdengine-idmp:latest
```

## Running the Docker Container

After building the image, you can run the TDengine IDMP application using Docker Compose. Execute the following command:

```bash
docker compose -f docker-compose.yml up -d
```

This command will start the TDengine IDMP application along with any defined dependencies.

## Stopping the Application

To stop the running application, you can use:

```bash
docker compose -f docker-compose.yml down
```
