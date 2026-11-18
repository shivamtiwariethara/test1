#!/bin/bash

set -u

export GOCACHE=/tmp/go-cache
mkdir -p /tmp/go-cache /logs/verifier

cd /tests && go run grade.go
