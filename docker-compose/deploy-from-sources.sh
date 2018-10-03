#!/usr/bin/env bash

# Set default build context if not given in environment.
if [ -z "$BUILD_CONTEXT_DIR" ]; then
  BUILD_CONTEXT_DIR="$HOME/myskills"
fi

# Prepare proxy settings given in environment.
if [[ $HTTP_PROXY =~ (.+)://(.+):(.+) ]]; then
  HTTP_PROXY_SCHEMA=${BASH_REMATCH[1]}
  HTTP_PROXY_HOST=${BASH_REMATCH[2]}
  HTTP_PROXY_PORT=${BASH_REMATCH[3]}
  echo "HTTP proxy settings: Schema=$HTTP_PROXY_SCHEMA , Host=$HTTP_PROXY_HOST , Port=$HTTP_PROXY_PORT"
fi
if [[ $HTTPS_PROXY =~ (.+)://(.+):(.+) ]]; then
  HTTPS_PROXY_SCHEMA=${BASH_REMATCH[1]}
  HTTPS_PROXY_HOST=${BASH_REMATCH[2]}
  HTTPS_PROXY_PORT=${BASH_REMATCH[3]}
  echo "HTTPS proxy settings: Schema=$HTTPS_PROXY_SCHEMA , Host=$HTTPS_PROXY_HOST , Port=$HTTPS_PROXY_PORT"
fi
NO_PROXY_JAVA=$(echo $NO_PROXY | tr , '|')

# Prepare variables for build context directories.
MYSKILLS_SERVER_DIR="$BUILD_CONTEXT_DIR/myskills-server"
MYSKILLS_WEBAPP_DIR="$BUILD_CONTEXT_DIR/myskills-webapp"
GRADLE_HOME="$BUILD_CONTEXT_DIR/.gradle"
M2_HOME="$BUILD_CONTEXT_DIR/.m2"
echo "Server repository directory: $MYSKILLS_SERVER_DIR"
echo "WebApp repository directory: $MYSKILLS_WEBAPP_DIR"
echo "Gradle home directory: $GRADLE_HOME"
echo "Maven home directory: $M2_HOME"

# Clone or update the MySkills Server sources from GitHub.
if [ -d "$MYSKILLS_SERVER_DIR" ]; then
  echo "Server repository already exists."
  echo "Updating server sources from GitHub..."
  pushd "$MYSKILLS_SERVER_DIR"
  git reset --hard
  git checkout -B master
  git pull origin master
else
  echo "Server repository not found."
  echo "Cloning server sources from GitHub..."
  git clone -b master https://github.com/KnowledgeAssets/myskills-server.git "$MYSKILLS_SERVER_DIR"
  pushd "$MYSKILLS_SERVER_DIR"
fi

# Build MySkills Server from sources.
echo "Building MySkills Server..."
docker run \
  --rm \
  -v "$PWD":/usr/src/myskills-server \
  -v "$GRADLE_HOME":/root/.gradle \
  -v "$M2_HOME":/root/.m2 \
  -w /usr/src/myskills-server \
  -e "HTTP_PROXY=$HTTP_PROXY" \
  -e "HTTPS_PROXY=$HTTPS_PROXY" \
  -e "NO_PROXY=$NO_PROXY" \
  openjdk:10 \
  ./gradlew \
  -Dhttp.proxyHost=$HTTP_PROXY_HOST \
  -Dhttp.proxyPort=$HTTP_PROXY_PORT \
  -Dhttp.nonProxyHosts=$NO_PROXY_JAVA \
  -Dhttps.proxyHost=$HTTPS_PROXY_HOST \
  -Dhttps.proxyPort=$HTTPS_PROXY_PORT \
  -Dhttps.nonProxyHosts=$NO_PROXY_JAVA \
  clean build

if [ "$?" -ne "0" ]; then
  echo "ERROR: Sources of MySkills Server could not be compiled!"
  popd
  exit 1
fi

# Build Docker image for MySkills Server using compiled JAR file.
JAR_FILE=$(find ./build/libs -type f -iname "myskills-server-*.jar")
docker build \
  -t myskills/server:latest \
  --build-arg JAR_FILE=$JAR_FILE \
  .

if [ "$?" -ne "0" ]; then
  echo "ERROR: Docker image of MySkills Server could not be created!"
  popd
  exit 1
fi

echo "MySkills Server built successfully."
popd

# ----

# Clone or update the MySkills WebApp sources from GitHub.
if [ -d "$MYSKILLS_WEBAPP_DIR" ]; then
  echo "WebApp repository already exists."
  echo "Updating webapp sources from GitHub..."
  pushd "$MYSKILLS_WEBAPP_DIR"
  git reset --hard
  git checkout -B master
  git pull origin master
else
  echo "WebApp repository not found."
  echo "Cloning webapp sources from GitHub..."
  git clone -b master https://github.com/KnowledgeAssets/myskills-webapp.git "$MYSKILLS_WEBAPP_DIR"
  pushd "$MYSKILLS_WEBAPP_DIR"
fi

# Build MySkills WebApp from sources.
echo "Building MySkills WebApp..."
docker run \
  --rm \
  -v "$PWD":/usr/src/myskills-webapp \
  -w /usr/src/myskills-webapp \
  -e "HTTP_PROXY=$HTTP_PROXY" \
  -e "HTTPS_PROXY=$HTTPS_PROXY" \
  -e "NO_PROXY=$NO_PROXY" \
  node:10 \
  /bin/bash -c "npm install && npm run build"

if [ "$?" -ne "0" ]; then
  echo "ERROR: Sources of MySkills WebApp could not be compiled!"
  popd
  exit 1
fi

# Build Docker image for MySkills WebApp using compiled distribution.
docker build \
  -t myskills/webapp:latest \
  .

if [ "$?" -ne "0" ]; then
  echo "ERROR: Docker image of MySkills WebApp could not be created!"
  popd
  exit 1
fi

echo "MySkills WebApp built successfully."
popd

# Create or update MySkills deployment.

if [ -z "$SERVER_DOMAIN" ]; then
  echo "WARNING: Environment variable SERVER_DOMAIN is not defined. Default domain 'localhost' will be used."
fi

docker-compose -p myskills up -d
