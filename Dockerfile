FROM ubuntu:bionic
RUN apt-get update -y
RUN apt-get install software-properties-common -y
RUN mkdir /opt/container_toolkit/
COPY ./ /opt/container_toolkit/

