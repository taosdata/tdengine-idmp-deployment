# TDengine IDP Docker Project

English | [简体中文](README-CN.md)

This project provides a Dockerized version of the TDengine IDP application. It includes all necessary files to build, run, and deploy the TDengine IDP application using Docker and Docker Compose.

## Project Structure

```
TDengine IDP docker
│── Dockerfile           # Instructions to build the TDengine IDP Docker image
│── entrypoint.sh        # Script to initialize the TDengine IDP application
│── docker-compose.yml   # Configuration for deploying TDengine IDP with Docker Compose
└── README.md            # Documentation for the project
```

## Prerequisites

- Docker: Ensure that Docker is installed and running on your machine.
- Docker Compose: Ensure that Docker Compose is installed.

## Building the Docker Image

To build the TDengine IDP Docker image, navigate to the project directory and run the following command, take version 0.9.6 for example:

```bash
docker build \
  -t tdengine/tdengine-idp:0.9.6 \
  --build-arg DOWNLOAD_URL="https://downloads.taosdata.com/tdengine-idp/enterprise/0.9.6/tdengine-idp-enterprise-0.9.6-linux.tar.gz" .
docker tag tdengine/tdengine-idp:0.9.6 tdengine/tdengine-idp:latest
```

## Running the Docker Container

After building the image, you can run the TDengine IDP application using Docker Compose. Execute the following command:

```bash
docker compose -f docker-compose.yml up -d
```

This command will start the TDengine IDP application along with any defined dependencies.

## Stopping the Application

To stop the running application, you can use:

```bash
docker compose -f docker-compose.yml down
```
