#!/bin/bash
set -o pipefail
set -ex
usr=$1
repo=$2

curl -s "https://api.github.com/repos/${usr}/${repo}/releases/latest" |jq -r '.tag_name'

