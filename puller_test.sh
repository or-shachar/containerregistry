#!/bin/bash -e

# Copyright 2017 Google Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Unit tests for puller.par

# remove puller2.par to avoid Permission denied errors on Mac OS
rm -f puller2.par

# Trick to chase the symlink before the docker build.
cp puller.par puller2.par

timing=-1

# Test pulling an image by just invoking the puller
function test_puller() {
  local image=$1

  # Test it in our current environment.
  puller.par --name="${image}" --directory=/tmp/
}

# Test pulling an image from inside a docker container with a
# certain base / entrypoint
function test_base() {
  local image=$1
  local entrypoint=$2
  local base_image=$3

  echo Testing puller env: ${base_image} entrypoint: ${entrypoint}
  # TODO(user): use a temp dir
  cat > Dockerfile <<EOF
FROM ${base_image}
ADD puller2.par /puller.par
EOF

  docker build -t puller_test .

  docker run -i --rm --entrypoint="${entrypoint}" puller_test \
    /puller.par --name="${image}" --directory=/tmp/

  docker rmi puller_test
}

function test_image() {
  local image=$1

  echo "TESTING: ${image}"

  test_puller "${image}"

  test_base "${image}" python2.7 python:2.7
  test_base "${image}" python2.7 gcr.io/cloud-builders/bazel
}

function test_puller_with_cache() {
  local image=$1

  # Test it in our current environment.
  puller.par --name="${image}" --directory=/tmp/ --cache=/tmp/containerregistery_docker_cache_dir
}

function test_image_with_cache() {
  local image=$1

  test_image_with_timing "${image}"
  local first_pull_timing=$timing
  echo "TIMING: ${image} - First pull took ${first_pull_timing} seconds"

  test_image_with_timing "${image}"
  local second_pull_timing=$timing
  echo "TIMING: ${image} - Second pull took ${second_pull_timing} seconds"

  # TODO - is there a better way to test that the cache was used beside asserting the first_pull > second_pull???
}

function test_image_with_timing() {
  local image=$1

  echo "TESTING: ${image}"

  local pull_start=$(date +%s)
  test_puller_with_cache "${image}"

  local pull_end=$(date +%s)
  timing=$(($pull_end-$pull_start))

  test_base "${image}" python2.7 python:2.7
  test_base "${image}" python2.7 gcr.io/cloud-builders/bazel
}

function clear_cache_directory() {
  rm -fr /tmp/containerregistery_docker_cache_dir
}

function create_cache_directory() {
  mkdir -p /tmp/containerregistery_docker_cache_dir
}

clear_cache_directory
create_cache_directory

# Test pulling with cache
test_image_with_cache gcr.io/google-appengine/python:latest

# Test pulling a trivial image.
test_image gcr.io/google-containers/pause:2.0

# Test pulling a non-trivial image.
test_image gcr.io/google-appengine/python:latest

# Test pulling from DockerHub
test_image index.docker.io/library/busybox:latest

# Test pulling from Quay.io
test_image quay.io/coreos/etcd:latest

# Test pulling from Bintray.io
# TODO: "Server presented certificate that does not match host jfrog-int-docker-devops-registry.bintray.io"
# test_image jfrog-int-docker-devops-registry.bintray.io/alpine:latest

# Gitlab only works with Python 2.7.9+ because it uses SNI for HTTP.
# As of this CL, the official python:2.7 image uses 2.7.13.
# We cannot test this with the gcr.io/cloud-builders/bazel image because
# it is based on the latest Ubuntu LTS release (14.04) which uses 2.7.6
test_base registry.gitlab.com/mattmoor/test-project/image:latest python2.7 python:2.7

# Test pulling by digest
test_image gcr.io/google-containers/pause@sha256:9ce5316f9752b8347484ab0f6778573af15524124d52b93230b9a0dcc987e73e

# Test pulling manifest list by digest, this should resolve to amd64/linux
test_image index.docker.io/library/busybox@sha256:1669a6aa7350e1cdd28f972ddad5aceba2912f589f19a090ac75b7083da748db

# TODO(user): Add an authenticated pull test.

clear_cache_directory