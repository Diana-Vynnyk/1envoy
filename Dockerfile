FROM debian:11
RUN apt-get update && apt-get -y upgrade

RUN apt -y install systemctl make daemontools daemontools-run apache2 debian-keyring debian-archive-keyring apt-transport-https curl lsb-release
RUN curl -sL 'https://deb.dl.getenvoy.io/public/gpg.8115BA8E629CC074.key' | gpg --dearmor -o /usr/share/keyrings/getenvoy-keyring.gpg
RUN echo a077cb587a1b622e03aa4bf2f3689de14658a9497a9af2c427bba5f4cc3c4723 /usr/share/keyrings/getenvoy-keyring.gpg | sha256sum --check
RUN echo "deb [arch=amd64 signed-by=/usr/share/keyrings/getenvoy-keyring.gpg] https://deb.dl.getenvoy.io/public/deb/debian $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/getenvoy.list
RUN apt update
RUN apt install getenvoy-envoy

COPY envoy.yaml etc/envoy/envoy.yaml
RUN chmod go+r /etc/envoy/envoy.yaml

RUN echo 'Service with Sidecar Proxy (Envoy)<br>'   > /var/www/html/index.html
RUN echo '<b><font color="magenta">Version 1.1</font></b>' >> /var/www/html/index.html

RUN mkdir -p /package
RUN chmod 1755 /package
RUN cd /package
RUN curl -OL https://cr.yp.to/daemontools/daemontools-0.76.tar.gz
RUN gunzip daemontools-0.76.tar
RUN tar -xpf daemontools-0.76.tar
RUN rm -f daemontools-0.76.tar
RUN cd admin/daemontools-0.76
#RUN package/install

RUN mkdir /service
RUN chmod 1755 /service

RUN mkdir /service/envoy
RUN chmod 1755 /service/envoy
RUN touch /service/envoy/run
RUN chmod 755 /service/envoy/run
RUN echo '#!/bin/sh' > /service/envoy/run
RUN echo 'exec envoy -c /etc/envoy/envoy.yaml' >> /service/envoy/run

RUN mkdir /service/envoy/log
RUN chmod 1755 /service/envoy/log 
RUN touch /service/envoy/log/run
RUN chmod 755 /service/envoy/log/run
RUN echo '#!/bin/sh' > /service/envoy/log/run
RUN echo 'exec multilog t '-*[info]*' '+*[warning]*' s1048576 n10 ./main' >> /service/envoy/log/run

RUN mkdir /service/apache2
RUN chmod 1755 /service/apache2
RUN touch /service/apache2/run
RUN chmod 755 /service/apache2/run
RUN echo '#!/bin/sh' > /service/apache2/run
#RUN echo 'exec /etc/init.d/apache2 start' >> /service/apache2/run
RUN echo 'exec systemctl start apache2' >> /service/apache2/run

RUN mkdir /service/apache2/log 
RUN chmod 1755 /service/apache2/log
RUN touch /service/apache2/log/run
RUN chmod 755 /service/apache2/log/run
RUN echo '#!/bin/sh' > /service/apache2/log/run
RUN echo 'exec multilog t '+*' s1048576 n10 ./apachelogs' >> /service/apache2/log/run

RUN touch /script.sh
RUN chmod 755 /script.sh
RUN echo '#!/bin/sh' > /script.sh
RUN echo 'cd /service' >> /script.sh
RUN echo 'exec svscan' >> /script.sh
ENTRYPOINT ["/bin/bash", "/script.sh"]


