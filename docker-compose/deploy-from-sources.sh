#!/usr/bin/env bash

# Set default build context if not set as environment variable.
if [ -z "$BUILD_CONTEXT_DIR" ]; then
  BUILD_CONTEXT_DIR="$HOME/myskills"
fi

# Prepare variables for build context directories.
MYSKILLS_SERVER_DIR="$BUILD_CONTEXT_DIR/myskills-server"
MYSKILLS_WEBAPP_DIR="$BUILD_CONTEXT_DIR/myskills-webapp"
MAVEN_CONFIG_DIR="$BUILD_CONTEXT_DIR/.m2"
echo "Server repository directory: $MYSKILLS_SERVER_DIR"
echo "WebApp repository directory: $MYSKILLS_WEBAPP_DIR"
echo "Maven config directory: $MAVEN_CONFIG_DIR"

if [[ ! -r "$MAVEN_CONFIG_DIR/settings.xml" ]]; then
  echo "WARNING: No Maven settings found. Using default configuration."
  echo "Create the file $MAVEN_CONFIG_DIR/settings.xml to customize settings."
fi

# ----

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
  -v "$MAVEN_CONFIG_DIR":/root/.m2 \
  -w /usr/src/myskills-server \
  -e "MAVEN_OPTS=$MAVEN_OPTS" \
  -e "HTTP_PROXY=$HTTP_PROXY" \
  -e "HTTPS_PROXY=$HTTPS_PROXY" \
  -e "NO_PROXY=$NO_PROXY" \
  openjdk:11 \
  ./mvnw clean package

if [ "$?" -ne "0" ]; then
  echo "ERROR: Sources of MySkills Server could not be compiled!"
  popd
  exit 1
fi

# Build Docker image for MySkills Server using compiled JAR file.
JAR_FILE=$(find ./target -type f -iname "myskills-server-*.jar")
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

# docker-compose -p myskills up -d
docker stack deploy --compose-file docker-compose.yml myskills
