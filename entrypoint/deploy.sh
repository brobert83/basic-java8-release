#!/bin/bash

function checkRequiredEnv(){

  local missing=0

  for required_var in "GITHUB_EMAIL" "GITHUB_USERNAME" "GITHUB_REPO"; do
    [[ ! ${!required_var} ]] && error "Required environement variable missing: ${required_var}" && missing=1
  done

  [[ ${missing} == 1 ]] && exit 1
}

function checkSecrets(){

  local missing=0

  for required_secret in \
        "SONATYPE_USERNAME_FILE"\
        "SONATYPE_PASSWORD_FILE"\
        "GITHUB_TOKEN_FILE"\
        "SIGNING_KEY_FILE"\
        "GPG_KEY_NAME_FILE"\
        "GPG_KEY_PASSPHRASE_FILE"; do
    [[ ! -f ${!required_secret} ]] && error "Required secret file missing : ${!required_secret}" && missing=1
  done

  [[ ${missing} == 1 ]] && exit 1
}

release_type=$(echo ${RELEASE_TYPE} | tr '[:lower:]' '[:upper:]')

checkRequiredEnv

github_repo=${GITHUB_REPO}
github_branch=${GITHUB_BRANCH}
github_username=${GITHUB_USERNAME}
github_email=${GITHUB_EMAIL}

# set default values
GITHUB_TOKEN_FILE=${GITHUB_TOKEN_FILE:-/work/secrets/github_token}
SIGNING_KEY_FILE=${SIGNING_KEY_FILE:-/work/secrets/signingkey.asc}
GPG_KEY_NAME_FILE=${GPG_KEY_NAME_FILE:-/work/secrets/gpg_keyname}
GPG_KEY_PASSPHRASE_FILE=${GPG_KEY_PASSPHRASE_FILE:-/work/secrets/gpg_key_passphrase}
SONATYPE_USERNAME_FILE=${SONATYPE_USERNAME_FILE:-/work/secrets/sonatype_username}
SONATYPE_PASSWORD_FILE=${SONATYPE_PASSWORD_FILE:-/work/secrets/sonatype_password}

checkSecrets

github_token=$(cat ${GITHUB_TOKEN_FILE})
signing_key_file=${SIGNING_KEY_FILE}
gpg_keyname=$(cat ${GPG_KEY_NAME_FILE})
gpg_key_passphrase=$(cat ${GPG_KEY_PASSPHRASE_FILE})
SONATYPE_USERNAME=$(cat ${SONATYPE_USERNAME_FILE})
SONATYPE_PASSWORD=$(cat ${SONATYPE_PASSWORD_FILE})

deploy=${DEPLOY}

# ======================================================================================================================
RED="31m"
GREEN="32m"

function out(){

  local text=$1
  local color=$2

  echo -e "\n\e[${color}${text}\e[0m"
}

function info(){
  out "$1" ${GREEN}
}

function error(){
  out "$1" ${RED}
}

function nextVersion(){

  local type=$1
  local major_version=$2
  local minor_version=$3
  local patch_version=$4

  [[ "${type}" == "MAJOR" ]] && echo "$(($major_version + 1)).0.0"
  [[ "${type}" == "MINOR" ]] && echo "${major_version}.$(($minor_version + 1)).0"
  [[ "${type}" == "PATCH" ]] && echo "${major_version}.${minor_version}.$(($patch_version + 1))"
}

function deploy(){

  info "Importing keys to keyring"

  gpg2 --allow-secret-key-import --no-default-keyring --import --batch ${signing_key_file}

  info "Deploying to Maven Central"

  mvn clean deploy \
    -DskipTests=true \
    -Prelease \
    --settings /work/settings.xml \
    -Dgpg.executable=gpg2 \
    -Dgpg.keyname=${gpg_keyname} \
    -Dgpg.passphrase=${gpg_key_passphrase}
}

# ======================================================================================================================

info "Starting release:"
info "    type:   ${release_type}"
info "    repo:   ${github_repo}"
info "    branch: ${github_branch}"

{
  info "1. Clone repository"

  git config --global user.name "Release Robot"
  git config --global user.email "${github_email}"

  git clone -b ${github_branch} https://${github_username}:${github_token}@${github_repo} repo
  cd repo

} &&

{
  info "2. identifying version"

  VERSION_REGEX="^([0-9]+)\.([0-9]+)\.([0-9]+)\-SNAPSHOT$"

  # fail if the currentVersion does not match the regex
  currentVersion=$(cat pom.xml | xq -r '.project.version')
  if [[ ! "${currentVersion}" =~ ${VERSION_REGEX} ]]; then
    info "Version declared in pom.xml does not match the regular expression: ${VERSION_REGEX}"
    exit 1
  fi

  major_version="${BASH_REMATCH[1]}"
  minor_version="${BASH_REMATCH[2]}"
  patch_version="${BASH_REMATCH[3]}"

  release_version="${major_version}.${minor_version}.${patch_version}"
  next_version="$(nextVersion ${release_type} ${major_version} ${minor_version} ${patch_version})-SNAPSHOT"

  info "Release type '${release_type}': ${release_version}"
  info "New version: ${next_version}"

  release_branch=RELEASE_${release_type}_${release_version}
  release_tag=v${release_version}
} &&

{
  info "3. Switching to branch release_${release_type}_${release_version}"
  git checkout -b ${release_branch}
} &&

{
  info "4. Changing version to ${release_version}"
  mvn versions:set -DnewVersion=${release_version}
} &&

{
  info "5. Running build"
  mvn clean package -DskipTests=true
} &&

{
  if [[ ${deploy} == "yes" ]]; then
    info "6. Deploying"
    deploy
  else
    info "[SKIPPED] 6. Deploying"
  fi
} &&

{
  info "7. Commiting version change"
  git add pom.xml
  git commit -m "Release: ${release_type} ${release_version}"
} &&

{
  info "8. Tagging with v${release_version}"
  git tag ${release_tag}
} &&

{
  info "9. Updating RELEASE_LOG.md"
  echo "# ${release_tag} ($(date))" >> RELEASE_LOG.md
  previous_tag=$(git tag --sort=committerdate | tail -n 2 | head -n 1)
  echo "\`\`\`" >> RELEASE_LOG.md
  git log --reverse --pretty=format:"%ci; %cn \"%s\"" ${previous_tag}...${release_tag} >> RELEASE_LOG.md
  echo -e "\n\`\`\`" >> RELEASE_LOG.md
  git add RELEASE_LOG.md
  git commit -m "Updated RELEASE_LOG.md"
} &&

{
  info "10. Increasing version to ${next_version}"
  mvn versions:set -DnewVersion=${next_version}
  git add pom.xml
  git commit -m "Updated RELEASE_LOG.md"
} &&

{
  info "11. Pushing release branch"
  git push -u origin ${release_branch}
} &&

{
  info "12. Pushing tag"
  git push origin ${release_tag}
} &&

{
  info "Release complete: ${release_tag}"
}
