#!/bin/bash
set -e # Exit with nonzero exit code if anything fails

bikeshed spec

if [ -d out ]; then
  echo Copy the generated spec into out/index.html
  cp index.html out/index.html

  echo Copying the polyfill into out/
  cp polyfill/intersection-observer-test.html polyfill/intersection-observer-test.js polyfill/intersection-observer.js out/polyfill/
fi
