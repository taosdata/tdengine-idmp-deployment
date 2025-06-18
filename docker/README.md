# TDengine AI Docker Project

English | [简体中文](README-CN.md)

This project provides a Dockerized version of the TDengine AI application. It includes all necessary files to build, run, and deploy the TDengine AI application using Docker and Docker Compose.

## Project Structure

```
TDengine AI docker
│── Dockerfile           # Instructions to build the TDengine AI Docker image
│── entrypoint.sh        # Script to initialize the TDengine AI application
│── docker-compose.yml   # Configuration for deploying TDengine AI with Docker Compose
└── README.md            # Documentation for the project
```

## Prerequisites

- Docker: Ensure that Docker is installed and running on your machine.
- Docker Compose: Ensure that Docker Compose is installed.

## Building the Docker Image

To build the TDengine AI Docker image, navigate to the project directory and run the following command, take version 0.9.6 for example:

```bash
docker build \
  -t tdengine-ai:0.9.6 \
  --build-arg DOWNLOAD_URL="https://downloads.taosdata.com/tdengine-ai/enterprise/0.9.6/tdengine-ai-enterprise-0.9.6-linux.tar.gz" .
```

## Running the Docker Container

After building the image, you can run the TDengine AI application using Docker Compose. Execute the following command:

```bash
docker compose -f docker-compose.yml up -d
```

This command will start the TDengine AI application along with any defined dependencies.

## Stopping the Application

To stop the running application, you can use:

```bash
docker compose -f docker-compose.yml down
```
