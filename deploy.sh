#!/bin/bash
set -e # Exit with nonzero exit code if anything fails

# From https://gist.github.com/domenic/ec8b0fc8ab45f39403dd

SOURCE_BRANCH=("master" "v2")
TARGET_BRANCH="gh-pages"

function doCompile {
  chmod 755 ./compile.sh
  ./compile.sh $*
}

# Pull requests and commits to other branches shouldn't try to deploy, just build to verify
if [ "$TRAVIS_PULL_REQUEST" != "false" ] || [[ ! "${SOURCE_BRANCH[*]}" =~ "$TRAVIS_BRANCH" ]]; then
    echo "Skipping deploy; just doing a build."
    doCompile
    exit 0
fi

# Save some useful information
REPO=`git config remote.origin.url`
SSH_REPO=${REPO/https:\/\/github.com\//git@github.com:}
SHA=`git rev-parse --verify HEAD`

# Clone the existing gh-pages for this repo into a temporary dir
# Create a new empty branch if gh-pages doesn't exist yet (should only happen on first deply)
gh_pages_dir="$(mktemp -d)"
git clone $REPO $gh_pages_dir
( cd $gh_pages_dir &&
  git checkout $TARGET_BRANCH || git checkout --orphan $TARGET_BRANCH )

# Run our compile script
case "$TRAVIS_BRANCH" in
  master)
    outdir="${gh_pages_dir}"
    ;;
  *)
    outdir="${gh_pages_dir}/${TRAVIS_BRANCH}"
    ;;
esac
mkdir -p "${outdir}"
doCompile "${outdir}"

# Now let's go have some fun with the cloned repo
cd "${gh_pages_dir}"
git config user.name "Travis CI"
git config user.email "$COMMIT_AUTHOR_EMAIL"

# If there are no changes to the compiled out (e.g. this is a README update) then just bail.
if [ -z "$(git status -s -u)" ]; then
    echo "No changes to the output on this push; exiting."
    exit 0
fi

# Commit the "changes", i.e. the new version.
# The delta will show diffs between new and old versions.
git add -A .
git commit -m "Deploy to GitHub Pages: ${SHA}"

# Get the deploy key by using Travis's stored variables to decrypt deploy_key.enc
ENCRYPTED_KEY_VAR="encrypted_${ENCRYPTION_LABEL}_key"
ENCRYPTED_IV_VAR="encrypted_${ENCRYPTION_LABEL}_iv"
ENCRYPTED_KEY=${!ENCRYPTED_KEY_VAR}
ENCRYPTED_IV=${!ENCRYPTED_IV_VAR}
openssl aes-256-cbc -K $encrypted_781c04ca6946_key -iv $encrypted_781c04ca6946_iv -in ../deploy_key.enc -out ../deploy_key -d
chmod 600 ../deploy_key
eval `ssh-agent -s`
ssh-add ../deploy_key

# Now that we're all set up, we can push.
git push $SSH_REPO $TARGET_BRANCH
