#!/bin/bash
set -e # Exit with nonzero exit code if anything fails

bikeshed spec

if [ -d out ]; then
  echo Copy the generated spec into out/index.html
  cp index.html out/index.html
fi
