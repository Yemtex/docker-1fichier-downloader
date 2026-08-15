# https://hub.docker.com/r/leplusorg/tor
FROM leplusorg/tor:latest
WORKDIR /opt/Scripts
# https://github.com/Yemtex/1fichier-downloader
USER root
RUN apk update
RUN apk add bash curl jq coreutils grep
RUN wget -q -P /opt/Scripts -O 1fichier.sh https://raw.githubusercontent.com/Yemtex/1fichier-downloader/master/1fichier.sh
RUN chmod +x /opt/Scripts/1fichier.sh
