#!/bin/bash
set -e # Exit with nonzero exit code if anything fails

bikeshed spec

outdir=out
if [ -n "$1" ]; then
  outdir="$1"
fi

if [ -d "${outdir}" ]; then
  echo Copy the generated spec into "${outdir}/index.html"
  cp index.html "${outdir}/index.html"
fi
