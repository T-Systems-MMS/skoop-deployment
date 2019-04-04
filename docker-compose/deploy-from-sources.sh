#!/usr/bin/env bash

# Set default build context if not set as environment variable.
if [ -z "$BUILD_CONTEXT_DIR" ]; then
  BUILD_CONTEXT_DIR="$HOME/skoop"
fi

# Prepare variables for build context directories.
SKOOP_SERVER_DIR="$BUILD_CONTEXT_DIR/skoop-server"
SKOOP_WEBAPP_DIR="$BUILD_CONTEXT_DIR/skoop-webapp"
MAVEN_CONFIG_DIR="$BUILD_CONTEXT_DIR/.m2"
echo "Server repository directory: $SKOOP_SERVER_DIR"
echo "WebApp repository directory: $SKOOP_WEBAPP_DIR"
echo "Maven config directory: $MAVEN_CONFIG_DIR"

if [[ ! -r "$MAVEN_CONFIG_DIR/settings.xml" ]]; then
  echo "WARNING: No Maven settings found. Using default configuration."
  echo "Create the file $MAVEN_CONFIG_DIR/settings.xml to customize settings."
fi

# ----

# Clone or update the SKOOP Server sources from GitHub.
if [ -d "$SKOOP_SERVER_DIR" ]; then
  echo "Server repository already exists."
  echo "Updating server sources from GitHub..."
  pushd "$SKOOP_SERVER_DIR"
  git reset --hard
  git checkout -B master
  git pull origin master
else
  echo "Server repository not found."
  echo "Cloning server sources from GitHub..."
  git clone -b master https://github.com/T-Systems-MMS/skoop-server.git "$SKOOP_SERVER_DIR"
  pushd "$SKOOP_SERVER_DIR"
fi

# Build SKOOP Server from sources.
echo "Building SKOOP Server..."
docker run \
  --rm \
  -v "$PWD":/usr/src/skoop-server \
  -v "$MAVEN_CONFIG_DIR":/root/.m2 \
  -w /usr/src/skoop-server \
  -e "MAVEN_OPTS=$MAVEN_OPTS" \
  -e "HTTP_PROXY=$HTTP_PROXY" \
  -e "HTTPS_PROXY=$HTTPS_PROXY" \
  -e "NO_PROXY=$NO_PROXY" \
  openjdk:11 \
  ./mvnw clean package

if [ "$?" -ne "0" ]; then
  echo "ERROR: Sources of SKOOP Server could not be compiled!"
  popd
  exit 1
fi

# Build Docker image for SKOOP Server using compiled JAR file.
JAR_FILE=$(find ./target -type f -iname "skoop-server-*.jar")
docker build \
  -t skoop/server:latest \
  --build-arg JAR_FILE=$JAR_FILE \
  .

if [ "$?" -ne "0" ]; then
  echo "ERROR: Docker image of SKOOP Server could not be created!"
  popd
  exit 1
fi

echo "SKOOP Server built successfully."
popd

# ----

# Clone or update the SKOOP WebApp sources from GitHub.
if [ -d "$SKOOP_WEBAPP_DIR" ]; then
  echo "WebApp repository already exists."
  echo "Updating webapp sources from GitHub..."
  pushd "$SKOOP_WEBAPP_DIR"
  git reset --hard
  git checkout -B master
  git pull origin master
else
  echo "WebApp repository not found."
  echo "Cloning webapp sources from GitHub..."
  git clone -b master https://github.com/T-Systems-MMS/skoop-webapp.git "$SKOOP_WEBAPP_DIR"
  pushd "$SKOOP_WEBAPP_DIR"
fi

# Build SKOOP WebApp from sources.
echo "Building SKOOP WebApp..."
docker run \
  --rm \
  -v "$PWD":/usr/src/skoop-webapp \
  -w /usr/src/skoop-webapp \
  -e "HTTP_PROXY=$HTTP_PROXY" \
  -e "HTTPS_PROXY=$HTTPS_PROXY" \
  -e "NO_PROXY=$NO_PROXY" \
  node:10 \
  /bin/bash -c "npm install && npm run build"

if [ "$?" -ne "0" ]; then
  echo "ERROR: Sources of SKOOP WebApp could not be compiled!"
  popd
  exit 1
fi

# Build Docker image for SKOOP WebApp using compiled distribution.
docker build \
  -t skoop/webapp:latest \
  .

if [ "$?" -ne "0" ]; then
  echo "ERROR: Docker image of SKOOP WebApp could not be created!"
  popd
  exit 1
fi

echo "SKOOP WebApp built successfully."
popd

# Create or update SKOOP deployment.

if [ -z "$SERVER_DOMAIN" ]; then
  echo "WARNING: Environment variable SERVER_DOMAIN is not defined. Default domain 'localhost' will be used."
fi

# docker-compose -p skoop up -d
docker stack rm skoop
sleep 30
docker stack deploy --compose-file docker-compose.yml skoop
