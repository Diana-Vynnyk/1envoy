FROM debian:11
RUN apt-get update && apt-get -y upgrade
#RUN apt -y install daemontools 
#RUN echo "8. Europe" | apt-get -y install apache2
#RUN curl -OL https://raw.githubusercontent.com/Diana-Vynnyk/project-envoy/master/envoy.yaml
# override the existing default envoy.yaml 

RUN apt -y install daemontools apache2 debian-keyring debian-archive-keyring apt-transport-https curl lsb-release
RUN curl -sL 'https://deb.dl.getenvoy.io/public/gpg.8115BA8E629CC074.key' | gpg --dearmor -o /usr/share/keyrings/getenvoy-keyring.gpg
RUN echo a077cb587a1b622e03aa4bf2f3689de14658a9497a9af2c427bba5f4cc3c4723 /usr/share/keyrings/getenvoy-keyring.gpg | sha256sum --check
RUN echo "deb [arch=amd64 signed-by=/usr/share/keyrings/getenvoy-keyring.gpg] https://deb.dl.getenvoy.io/public/deb/debian $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/getenvoy.list
RUN apt update
RUN apt install getenvoy-envoy

COPY envoy.yaml etc/envoy/envoy.yaml

RUN chmod go+r /etc/envoy/envoy.yaml

RUN echo 'Service with Sidecar Proxy (Envoy)<br>'   > /var/www/html/index.html
RUN echo '<b><font color="magenta">Version 1.1</font></b>' >> /var/www/html/index.html


CMD ["/usr/local/bin/envoy", "-c", "/etc/envoy/envoy.yaml"]
