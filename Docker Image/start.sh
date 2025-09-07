#!/bin/bash
set -euo pipefail

ORG=${ORG:-}
REG_TOKEN=${REG_TOKEN:-}
NAME=${NAME:-github-runner}
RUNNER_DIR=/home/runner/actions-runner
RUNNER_VERSION=${RUNNER_VERSION:-2.317.0}

download_runner() {
  if [ ! -d "$RUNNER_DIR" ] || [ ! -f "$RUNNER_DIR/config.sh" ]; then
    mkdir -p "$RUNNER_DIR"
    echo "Downloading actions runner v${RUNNER_VERSION}..."
    curl -fsSL -o /tmp/runner.tar.gz \
      "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-arm64-${RUNNER_VERSION}.tar.gz"
    # extract as root to avoid permission issues in mounted volumes
    sudo tar -xzf /tmp/runner.tar.gz -C "$RUNNER_DIR"
    rm -f /tmp/runner.tar.gz
    # install dependencies (as root as Dockerfile did not run installdependencies)
    sudo bash -c "cd $RUNNER_DIR && ./bin/installdependencies.sh"
    chown -R runner:runner "$RUNNER_DIR"
  fi
}

register_runner() {
  cd "$RUNNER_DIR" || exit 1
  if [ -z "$REG_TOKEN" ] || [ -z "$ORG" ]; then
    echo "REG_TOKEN and ORG must be set to register the runner. Exiting." >&2
    exit 1
  fi
  echo "Configuring runner for org: $ORG"
  ./config.sh --url "https://github.com/${ORG}" --token "$REG_TOKEN" --name "$NAME" --labels "self-hosted,macos,arm64" --unattended
}

cleanup() {
  echo "Removing runner..."
  cd "$RUNNER_DIR" || exit 1
  ./config.sh remove --unattended --token "$REG_TOKEN" || true
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

download_runner
register_runner

cd "$RUNNER_DIR"
./run.sh & wait $!