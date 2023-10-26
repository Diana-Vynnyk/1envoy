# Web Server Apache2 with Envoy as a Sidecar Proxy and Daemontools

1. [Screenshots](#paragraph1)
2. [How services talk to each other?](#paragraph2)
3. [What is a sidecar proxy?](#paragraph3)
4. [Envoy](#paragraph4)



## [Screenshots:](https://drive.google.com/drive/folders/1hVJwRDy-7wuawmoHm_CpJeHNsXLh3NAR?usp=sharing) <a name="paragraph1"></a>
[docker build](https://drive.google.com/file/d/1NsjGsZD7w9WmiMET98VOUtH1vPw5M4Kr/view?usp=sharing)

[docker run](https://drive.google.com/file/d/1tlk9FLfzyiZF82GncubeIrHpyc3U8X6N/view?usp=sharing)

[run scripts for apache2, envoy and their logs with daemontools](https://drive.google.com/file/d/1cPSpTePuj4VYpqOjONGbkyri-VVGGrLl/view?usp=sharing)

[working Web Server Apache2 through Envoy Proxy](https://drive.google.com/file/d/11VrIg_3tKxPCuKDNdfuKkkCboX3taDQ9/view?usp=sharing)



## How services talk to each other? <a name="paragraph2"></a>

Imagine you're developing a service... For certainty, let's call it A. It's going to provide some public HTTP API to its clients. However, to serve requests it needs to call another service. Let's call this upstream service - B.

![How services talk to each other?](https://iximiuz.com/service-proxy-pod-sidecar-oh-my/10-service-a-service-b.png)

Obviously, neither network nor service B is ideal. If service A wants to decrease the impact of the failing upstream requests on its public API success rate, it has to do something about errors. For instance, it could start retrying failed requests.

![Sidecar](https://iximiuz.com/service-proxy-pod-sidecar-oh-my/20-service-a-service-b-with-retries.png)

Implementation of the retry mechanism requires some code changes in the service A, but the codebase is fresh, there are tons of advanced HTTP libraries, so you just need to grab one... Easy-peasy, right?

Unfortunately, this simplicity is not always the case. Replace service A with service Z that was written 10 years ago in some esoteric language by a developer that already retired. Or add to the equitation services Q, U, and X written by different teams in three different languages. As a result, the cumulative cost of the company-wide retry mechanism implementation in the code gets really high...

![Sidecar](https://iximiuz.com/service-proxy-pod-sidecar-oh-my/30-service-qux-service-b.png)

But what if retries are not the only thing you need? Proper request timeouts have to be ensured as well. And how about distributed tracing? It'd be nice to correlate the whole request tree with the original customer transaction by propagating some additional HTTP headers. However, every such capability would make the HTTP libraries even more bloated...

## What is a sidecar proxy? <a name="paragraph3"></a>

![Sidecar](https://iximiuz.com/service-proxy-pod-sidecar-oh-my/40-service-a-sidecar-service-b.png)

In our original setup, service A has been communicating with service B directly. 
But what if we put an intermediary infrastructure component in between those services? 
Thanks to containerization, orchestration, devops ..., nowadays, it became so simple to configure infrastructure,
that the cost of adding another infra component is often lower than the cost of writing application code...

For the sake of simplicity, let's call the box enclosing the service A and the secret intermediary component a server (bare metal or virtual, doesn't really matter). And now it's about time to introduce one of the fancy words from the article's title. Any piece of software running on the server alongside the primary service and helping it do its job is called a sidecar. I hope, the idea behind the name is more or less straightforward here.

But getting back to the service-to-service communication problem, what sidecar should we use to keep the service code free of the low-level details such as retries or request tracing? Well, the needed piece of software is called a service proxy. Probably, the most widely used implementation of the service proxy in the real world is **envoy**.

The idea of the service proxy is the following: instead of accessing the service B directly, code in the service A now will be sending requests to the service proxy sidecar. Since both of the processes run on the same server, the loopback network interface (i.e. `127.0.0.1` aka `localhost`) is perfectly suitable for this part of the communication. On every received HTTP request, the service proxy sidecar will make a request to the upstream service using the external network interface of the server. The response from the upstream will be eventually forwarded back by the sidecar to the service A.

I think, at this time, it's already obvious where the retry, timeouts, tracing, etc. logic should reside. Having this kind of functionality provided by a separate sidecar process makes enhancing any service written in any language with such capabilities rather trivial.

Interestingly enough, that service proxy could be used not only for outgoing traffic (egress) but also for the incoming traffic (ingress) of the service A. Usually, there is plenty of cross-cutting things that can be tackled on the ingress stage. For instance, proxy sidecars can do SSL termination, request authentication, and more. A detailed diagram of a single server setup could look something like that:

![2sidecar](https://iximiuz.com/service-proxy-pod-sidecar-oh-my/50-single-host-sidecar.png)

Probably, the last fancy term we are going to cover here is a pod. People have been deploying code using virtual machines or bare metal servers for a long time... A server itself is already a good abstraction and a unit of encapsulation. For instance, every server has at least one external network interface, a network loopback interface for the internal IPC needs, and it can run a bunch of processes sharing access to these communication means. Servers are usually addressable within the private network of the company by their IPs. Last but not least, it's pretty common to use a whole server for a single purpose (otherwise, maintenance quickly becomes a nightmare). I.e. you may have a group of identical servers running instances of service A, another group of servers each running an instance of service B, etc. So, why on earth would anybody want something better than a server?

Despite being a good abstraction, the orchestration overhead servers introduce is often too high. So people started thinking about how to package applications more efficiently and that's how we got containers. Well, probably you know that Docker and container had been kind of a synonym for a long time and folks from Docker have been actively advocating for "a one process per container" model. Obviously, this model is pretty different from the widely used server abstraction where multiple processes are allowed to work side by side. And that's how we got the concept of pods. A pod is just a group of containers sharing a bunch of namespaces. If we now run a single process per container all of the processes in the pod will still share the common execution environment. In particular, the network namespace. Thus, all the containers in the pod will have a shared loopback interface and a shared external interface with an IP address assigned to it. Then it's up to the orchestration layer (say hi to Kubernetes) how to make all the pods reachable within the network by their IPs. And that's how people reinvented servers...

So, getting back to all those blue boxes enclosing the service process and the sidecar on the diagrams above - we can think of them as being either a virtual machine, a bare metal server, or a pod. All three of them are more or less interchangeable abstractions.

To summarize, let's try to visualize how the service to service communication could look like with the proxy sidecars:

![Sidecar](https://iximiuz.com/service-proxy-pod-sidecar-oh-my/60-service-to-service-topology.png)
`Example of service to service communication topology, a.k.a. service mesh.`

From a very high-level overview, Envoy could be seen as a bunch of pipelines. A pipeline starts from the listener and then connected through a set of filters to some number of clusters, where a cluster is just a logical group of network endpoints. Trying to be less abstract:
```bash
# Ingress
listener 0.0.0.0:80
       |
http_connection_manager (filter)
       |
http_router (filter)
       |
local_service (cluster) [127.0.0.1:8000]

# Egress
listener 127.0.0.1:9001
       |
http_connection_manager (filter)
       |
http_router (filter)
       |
remote_service_b (cluster) [b.service:80]
```
Envoy is famous for its observability capabilities. It exposes various statistic information and luckily for us, it supports the prometheus metrics format out of the box. We can extend the prometheus scrape configs adding the following section:
```bash
# prometheus/prometheus.yml

  - job_name: service-a-envoy
    scrape_interval: 1s
    metrics_path: /stats/prometheus
    static_configs:
      - targets: ['a.service:9901']
```



# Envoy <a name="paragraph4"></a>

### Install Envoy on Ubuntu Linux <a name="paragraph5"></a>
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
### To Run Envoy <a name="paragraph6"></a>

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
### Admin endpoints: `config_dump`
The config_dump endpoint returns Envoy’s runtime configuration in `json` format.

The following command allows you to see the types of configuration available:
```bash
curl -s http://localhost:9901/config_dump | jq -r '.configs[] | .["@type"]'
type.googleapis.com/envoy.admin.v3.BootstrapConfigDump
type.googleapis.com/envoy.admin.v3.ClustersConfigDump
type.googleapis.com/envoy.admin.v3.ListenersConfigDump
type.googleapis.com/envoy.admin.v3.ScopedRoutesConfigDump
type.googleapis.com/envoy.admin.v3.RoutesConfigDump
type.googleapis.com/envoy.admin.v3.SecretsConfigDump
```
To view the socket_address of the first dynamic_listener currently configured, you could:
```bash
curl -s http://localhost:9901/config_dump?resource=dynamic_listeners | jq '.configs[0].active_state.listener.address'
{
  "socket_address": {
    "address": "0.0.0.0",
    "port_value": 10000
  }
}
```
**Enabling the admin interface with dynamic configuration can be particularly useful as it allows you to use the config_dump endpoint to see how Envoy is configured at a particular point in time.**

### Admin endpoints: `stats`
The admin stats endpoint allows you to retrieve runtime information about Envoy.

The stats are provided as `key: value` pairs, where the keys use a hierarchical dotted notation, and the values are one of `counter`, `histogram` or `gauge` types.

To see the top-level categories of stats available, you can:
```bash
curl -s http://localhost:9901/stats | cut -d. -f1 | sort | uniq
cluster
cluster_manager
filesystem
http
http1
listener
listener_manager
main_thread
runtime
server
vhost
workers
```
The stats endpoint accepts a filter argument, which is evaluated as a regular expression:
```bash
curl -s http://localhost:9901/stats?filter='^http\.ingress_http'
http.ingress_http.downstream_cx_active: 0
http.ingress_http.downstream_cx_delayed_close_timeout: 0
http.ingress_http.downstream_cx_destroy: 3
http.ingress_http.downstream_cx_destroy_active_rq: 0
http.ingress_http.downstream_cx_destroy_local: 0
http.ingress_http.downstream_cx_destroy_local_active_rq: 0
http.ingress_http.downstream_cx_destroy_remote: 3
```
You can also pass a format argument, for example to return `json`:

```bash 
curl -s "http://localhost:9901/stats?filter=http.ingress_http.rq&format=json" | jq '.stats'
```
```bash
[
  {
    "value": 0,
    "name": "http.ingress_http.rq_direct_response"
  },
  {
    "value": 0,
    "name": "http.ingress_http.rq_redirect"
  },
  {
    "value": 0,
    "name": "http.ingress_http.rq_reset_after_downstream_response_started"
  },
  {
    "value": 3,
    "name": "http.ingress_http.rq_total"
  }
]
```
### Envoy admin web UI
Envoy also has a web user interface that allows you to view and modify settings and statistics.

Point your browser to http://localhost:9901.



## Sources
[Sidecar Proxy Pattern - The Basis Of Service Mesh](https://iximiuz.com/en/posts/service-proxy-pod-sidecar-oh-my/)

[Envoy documentation](https://www.envoyproxy.io/docs/envoy/latest/)

[Configuration generator](https://www.envoyproxy.io/docs/envoy/latest/operations/tools/config_generator#start-tools-configuration-generator)

[How to Deploy Envoy as a Sidecar Proxy on Kubernetes](https://medium.com/@viggnah/how-to-deploy-envoy-as-a-sidecar-proxy-on-kubernetes-c3a3ad3935ee)

[Double proxy (with mTLS encryption)](https://www.envoyproxy.io/docs/envoy/v1.28.0/start/sandboxes/double-proxy.html)
