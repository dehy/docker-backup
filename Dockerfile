FROM ubuntu:14.04
MAINTAINER Arnaud de Mouhy <arnaud.demouhy@akerbis.com>

RUN apt-get update
RUN apt-get -y upgrade
RUN apt-get -y install npm python-pip git wget lftp
RUN update-alternatives --install /usr/bin/node nodejs /usr/bin/nodejs 100
RUN npm install -g underscore-cli
RUN pip install boto
RUN wget -qO- https://get.docker.com/ | sh


ADD /rootfs /
RUN apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 8F571BB27A86F4A2
RUN apt-get update
RUN apt-get -y install duplicity

ADD https://storage.googleapis.com/golang/go1.5.1.linux-amd64.tar.gz /root/
RUN tar -C /usr/local -xzf /root/go1.5.1.linux-amd64.tar.gz
ENV GOPATH /root/gocode
ENV PATH $PATH:/usr/local/go/bin:$GOPATH/bin
RUN mkdir $GOPATH
RUN go get github.com/Soulou/curl-unix-socket
RUN chmod +x /run.sh

ENV BACKUP_METHOD ftp
ENV BACKUP_URL defineme
ENV FTP_PASSWORD defineme
ENV BACKUP_S3_ACCESS_KEY defineme
ENV BACKUP_S3_SECRET_ACCESS_KEY defineme
ENV ON_TUTUM false

ENTRYPOINT [ "/run.sh" ]
