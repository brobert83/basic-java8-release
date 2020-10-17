FROM alpine:3.11.6

RUN apk update && \
    apk add openjdk8 maven jq python3 bash bash-doc bash-completion git gnupg htop && \
    pip3 install yq

RUN mkdir -p /work/secrets

WORKDIR work

ADD files/.bashrc /root

ADD entrypoint/deploy.sh /work
ADD files/settings.xml /work

RUN chmod +x /work/deploy.sh

ENV RELEASE_TYPE=PATCH
ENV GITHUB_BRANCH=master
ENV DEPLOY=yes

ENV GITHUB_TOKEN_FILE=/work/secrets/github_token
ENV SIGNING_KEY_FILE=/work/secrets/signingkey.asc
ENV GPG_KEYNAME_FILE=/work/secrets/gpg_keyname
ENV GPG_KEY_PASSPHRASE=/work/secrets/gpg_key_passphrase
ENV SONATYPE_USERNAME=/work/secrets/sonatype_username
ENV SONATYPE_PASSWORD=/work/secrets/sonatype_password

ENTRYPOINT ["/work/deploy.sh"]
