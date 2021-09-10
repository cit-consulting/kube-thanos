#!/usr/bin/env bash

# This script uses arg $1 (name of *.jsonnet file to use) to generate the manifests/*.yaml files.

set -e
set -x
# only exit with zero if all commands of the pipeline exit successfully
set -o pipefail

JSONNET=${JSONNET:-jsonnet}
GOJSONTOYAML=${GOJSONTOYAML:-gojsontoyaml}
# Make sure to start with a clean 'manifests' dir
rm -rf manifests-citc
mkdir -p manifests-citc/thanos-bucket/deploy
mkdir -p manifests-citc/thanos-bucket/prometheus
mkdir -p manifests-citc/thanos-compact/deploy
mkdir -p manifests-citc/thanos-compact/prometheus
mkdir -p manifests-citc/thanos-query/deploy
mkdir -p manifests-citc/thanos-query/prometheus
mkdir -p manifests-citc/thanos-queryfront/deploy
mkdir -p manifests-citc/thanos-queryfront/prometheus
mkdir -p manifests-citc/thanos-store/deploy
mkdir -p manifests-citc/thanos-store/prometheus
mkdir -p manifests-citc/thanos-receive/deploy
mkdir -p manifests-citc/thanos-receive/prometheus

# optional, but we would like to generate yaml, not json
${JSONNET} -J vendor -m manifests-citc "${1-example.jsonnet}" | xargs -I{} sh -c "cat {} | ${GOJSONTOYAML} > {}.yaml; rm -f {}" -- {}
find manifests-citc -type f ! -name '*.yaml' -delete
