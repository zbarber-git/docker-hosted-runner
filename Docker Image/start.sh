#!/bin/bash
set -euo pipefail

ORG=${ORG:-}
REPO=${REPO:-}
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

  # If runner already appears configured, skip registration regardless of REG_TOKEN
  if [ -f "$RUNNER_DIR/.credentials" ] || [ -f "$RUNNER_DIR/.runner" ]; then
    echo "Runner already configured; skipping registration."
    return 0
  fi

  if [ -z "$REG_TOKEN" ]; then
    echo "REG_TOKEN not set and runner not configured. Provide REG_TOKEN to register the runner." >&2
    exit 1
  fi

  # Prefer REPO if set, otherwise use ORG
  if [ -n "$REPO" ]; then
    REG_URL="https://github.com/${REPO}"
    echo "Configuring runner for repo: $REPO"
  elif [ -n "$ORG" ]; then
    REG_URL="https://github.com/${ORG}"
    echo "Configuring runner for org: $ORG"
  else
    echo "Either REPO or ORG must be set to register the runner. Exiting." >&2
    exit 1
  fi

  # allow LABELS to be set externally; default includes docker so workflows requesting 'docker' will match
  LABELS=${LABELS:-"self-hosted,macos,arm64,docker"}
  echo "Using labels: $LABELS"
  ./config.sh --url "$REG_URL" --token "$REG_TOKEN" --name "$NAME" --labels "$LABELS" --unattended
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