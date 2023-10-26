# Web Server Apache2 with Envoy as a Sidecar Proxy and Daemontools

### [Screenshots:](https://drive.google.com/drive/folders/1hVJwRDy-7wuawmoHm_CpJeHNsXLh3NAR?usp=sharing)
[docker build](https://drive.google.com/file/d/1NsjGsZD7w9WmiMET98VOUtH1vPw5M4Kr/view?usp=sharing)

[docker run](https://drive.google.com/file/d/1tlk9FLfzyiZF82GncubeIrHpyc3U8X6N/view?usp=sharing)

[run scripts for apache2, envoy and their logs with daemontools](https://drive.google.com/file/d/1cPSpTePuj4VYpqOjONGbkyri-VVGGrLl/view?usp=sharing)

[working Web Server Apache2 through Envoy Proxy](https://drive.google.com/file/d/11VrIg_3tKxPCuKDNdfuKkkCboX3taDQ9/view?usp=sharing)

## Envoy

### Install Envoy on Ubuntu Linux
```bash
sudo apt update
sudo apt install apt-transport-https gnupg2 curl lsb-release
curl -sL 'https://deb.dl.getenvoy.io/public/gpg.8115BA8E629CC074.key' | sudo gpg --dearmor -o /usr/share/keyrings/getenvoy-keyring.gpg
Verify the keyring - this should yield "OK"
echo a077cb587a1b622e03aa4bf2f3689de14658a9497a9af2c427bba5f4cc3c4723 /usr/share/keyrings/getenvoy-keyring.gpg | sha256sum --check
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/getenvoy-keyring.gpg] https://deb.dl.getenvoy.io/public/deb/ubuntu $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/getenvoy.list
sudo apt update
sudo apt install -y getenvoy-envoy
```
```bash
envoy --version
envoy --help
```
### To Run Envoy 

The `-c` or `--config-path` flag tells Envoy the path to its initial configuration.

Envoy will parse the config file according to the file extension.

To start Envoy as a system daemon with the configuration, and start as follows:
```bash
envoy -c envoy.yaml
```
### Check Envoy is proxying on http://localhost:10000.
```bash
curl -v localhost:10000
```
You can exit the server with `Ctrl-c`.

**If you run Envoy inside a Docker container you may wish to use 0.0.0.0. Exposing the admin interface in this way may give unintended control of your Envoy server.**

### Validating  Envoy configuration

You can start Envoy in `validate mode`.

This allows you to check that Envoy is able to start with your configuration, without actually starting or restarting the service, or making any network connections.

If the configuration is valid the process will print `OK` and exit with a return code of `0`.

For invalid configuration the process will print the errors and exit with `1`.

```bash
envoy --mode validate -c my-envoy-config.yaml
```

### Envoy logging
By default Envoy system logs are sent to `/dev/stderr`.

This can be overridden using `--log-path`.

SystemDocker (Linux Image)Docker (Windows Image)
```bash
mkdir logs
envoy -c envoy-demo.yaml --log-path logs/custom.log
```
Access log paths can be set for the admin interface, and for configured listeners.

```bash
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_http
          access_log:
          - name: envoy.access_loggers.stdout
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
```
The default configuration in the Envoy Docker container also logs access in this way.

Logging to `/dev/stderr` and `/dev/stdout` for system and access logs respectively can be useful when running Envoy inside a container as the streams can be separated, and logging requires no additional files or directories to be mounted.

Some Envoy filters and extensions may also have additional logging capabilities.

Envoy can be configured to log to different formats, and to different outputs in addition to files and `stdout/err`.

### Debugging Envoy
The log level for Envoy system logs can be set using the `-l` or `--log-level` option.

The available log levels are:
- trace
- debug
- info
- warning/warn
- error
- critical
- off

The default is `info`.

You can also set the log level for specific components using the `--component-log-level` option.

The following example inhibits all logging except for the `upstream` and `connection` components, which are set to `debug` and `trace` respectively.
```bash
envoy -c envoy.yaml -l off --component-log-level upstream:debug,connection:trace
```

### Configuration: Static

To start Envoy with static configuration, you will need to specify listeners and clusters as static_resources.

You can also add an admin section if you wish to monitor Envoy or retrieve stats.

The following sections walk through the static configuration provided in the demo configuration file used as the default in the Envoy Docker container.

#### `static_resources`

The static_resources contain everything that is configured statically when Envoy starts, as opposed to dynamically at runtime.

`envoy-demo.yaml:`
```bash
static_resources:

  listeners:
```

#### `listeners`

The example configures a listener on port `10000`.

All paths are matched and routed to the `service_envoyproxy_io` cluster.

`envoy-demo.yaml:`
```bash
static_resources:

  listeners:
  - name: listener_0
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 10000
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_http
          access_log:
          - name: envoy.access_loggers.stdout
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
          route_config:
            name: local_route
            virtual_hosts:
            - name: local_service
              domains: ["*"]
              routes:
              - match:
                  prefix: "/"
                route:
                  host_rewrite_literal: www.envoyproxy.io
                  cluster: service_envoyproxy_io

  clusters:
  - name: service_envoyproxy_io
```

#### `clusters`

The `service_envoyproxy_io` cluster proxies over `TLS` to https://www.envoyproxy.io.

`envoy-demo.yaml`
```bash
                route:
                  host_rewrite_literal: www.envoyproxy.io
                  cluster: service_envoyproxy_io

  clusters:
  - name: service_envoyproxy_io
    type: LOGICAL_DNS
    # Comment out the following line to test on v6 networks
    dns_lookup_family: V4_ONLY
    load_assignment:
      cluster_name: service_envoyproxy_io
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: www.envoyproxy.io
                port_value: 443
    transport_socket:
      name: envoy.transport_sockets.tls
      typed_config:
        "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext
        sni: www.envoyproxy.io
```

### Envoy admin interface
The optional admin interface provided by Envoy allows you to view configuration and statistics, change the behaviour of the server, and tap traffic according to specific filter rules.

#### `admin`
The admin message is required to enable and configure the administration server.

The `address` key specifies the listening address which in the demo configuration is `0.0.0.0:9901`.

In this example, the logs are simply discarded.
```bash
admin:
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 9901
```

The Envoy admin endpoint can expose private information about the running service, allows modification of runtime settings and can also be used to shut the server down.

As the endpoint is not authenticated it is essential that you limit access to it.

You may wish to restrict the network address the admin server listens to in your own deployment as part of your strategy to limit access to this endpoint.

#### `stat_prefix`
The Envoy HttpConnectionManager must be configured with stat_prefix.

This provides a key that can be filtered when querying the stats interface as shown below

In the envoy-demo.yaml the listener is configured with the stat_prefix of `ingress_http`.

```bash
static_resources:

  listeners:
  - name: listener_0
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 10000
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_http
          access_log:
          - name: envoy.access_loggers.stdout
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
          route_config:
            name: local_route
            virtual_hosts:
            - name: local_service
              domains: ["*"]
              routes:
              - match:
```
