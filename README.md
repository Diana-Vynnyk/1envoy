# Web Server Apache2 with Envoy as a Sidecar Proxy and Daemontools

1. [Screenshots](#paragraph1)
2. [How services talk to each other?](#paragraph2)
3. [What is a sidecar proxy?](#paragraph3)
4. [Envoy](#paragraph4)
   1. [What is Envoy proxy?](#subparagraph1)
   2. [What are Envoy’s building blocks?](#subparagraph2)
   3. [Clusters](#subparagraph3)
   4. [What are Envoy proxy filters?](#subparagraph4)
   5. [What are HTTP filters?](#subparagraph5)
   6. [Envoy proxy and dynamic configuration](#subparagraph6)
6. [Install Envoy on Ubuntu Linux](#paragraph5)
7. [To Run Envoy](#paragraph6)
8. [Check Envoy is proxying on http://localhost:10000.](#paragraph7)
9. [Validating  Envoy configuration](#paragraph8)
10. [Envoy logging](#paragraph9)
11. [Debugging Envoy](#paragraph10)
12. [Configuration: Static](#paragraph11)
13. [`static_resources`](#paragraph12)
14. [`listeners`](#paragraph13)
15. [`clusters`](#paragraph14)
16. [Envoy admin interface](#paragraph15)
17. [`admin`](#paragraph16)
18. [`stat_prefix`](#paragraph17)
19. [`config_dump`](#paragraph18)
20. [Admin endpoints: `stats`](#paragraph19)
21. [Envoy admin web UI](#paragraph20)
22. [Sources](#paragraph21)



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

Envoy is the engine that keeps Istio running. If you’re familiar with Istio, you know that the collection of all Envoys in the Istio service mesh is also referred to as the **data plane**. 

## What is Envoy proxy? <a name="subparagraph1"></a>

Envoy Proxy is an open-source edge and service proxy designed for cloud-native applications. The proxy was originally built at Lyft. It’s written in C++ and designed for services and applications, and it serves as a universal data plane for large-scale microservice service mesh architectures.

The idea is to have Envoy sidecars run next to each service in your application, abstracting the network and providing features like load balancing, resiliency features such as timeouts and retries, observability and metrics, and so on. 

One of the cool features of Envoy is that we can configure it through network APIs without restarting! These APIs are called **discovery services** or **xDS** for short.

In addition to the traditional load balancing between different instances, Envoy also allows you to implement retries, circuit breakers, rate limiting, and so on. 

Also, while doing all that, Envoy collects rich metrics about the traffic it passes through and exposes the metrics for consumption and use in tools such as Grafana, for example.

## What are Envoy’s building blocks? <a name="subparagraph2"></a>

Let’s explain Envoy’s building blocks using an example. Let’s say we have the Envoy proxy running, and it’s sending requests through to a couple of services. We are trying to send a request to the proxy, so it ends up on one of the backend services.

![image](https://tetrate.io/wp-content/uploads/2021/07/envoy-1.png)

**Figure 1:** Envoy Proxy building blocks

To send a request, we need an IP address and a port the proxy is listening on (e.g., 1.0.0.0:9999 from the image above). 

The address and port Envoy proxy listens on is called a **listener**. Listeners are the way Envoy receives connections or requests. There can be more than one listener as Envoy can listen on more than one IP and port combination.

Attached to these listeners are **routes** – routes are a set of rules that map virtual hosts to clusters. We could look at the request metadata– things like headers and URI path — and then route the traffic to clusters.

![image](https://tetrate.io/wp-content/uploads/2021/07/Envoy-5-mins-100-1-1536x685.jpg)

**Figure 2:** Envoy Proxy listener and routes

For example, if the Host header contains the value hello.com, we want to route the traffic to one service, or if the path starts with /api we wish to route to the API back-end services. Based on the matching rules in the route, Envoy selects a **cluster**.

![image](https://tetrate.io/wp-content/uploads/2021/07/Envoy-5-mins-copy-100-1536x685.jpg)

**Figure 3:** Envoy listener, routes, and clusters

### Clusters <a name="subparagraph3"></a>

A cluster is a group of similar upstream hosts that accept traffic. We could have a cluster representing our API services or a cluster representing a specific version of back-end services. This is all configurable, and we can decide which hosts to include in which clusters. Clusters are also where we can configure things like outlier detection, circuit breakers, connection timeouts, and load balancing policies.

Once we have received the request, we know where to route it (using the routes) and how to send it (using the cluster and load balancing policies). We can select an **endpoint** to send the traffic to. This is where we go from a logical entity of a cluster to a physical IP and port. We can structure the endpoints to prioritize certain instances over other instances based on the metadata. For example, we could set up the locality of endpoints to keep the traffic local, to send it to the closest endpoint.

## What are Envoy proxy filters? <a name="subparagraph4"></a>

When a request hits one of the listeners in Envoy, that request goes through a set of filters. There are three types of filters that Envoy currently provides, and they form a hierarchical filter chain:

**1. Listener filters**
Listener filters access **raw data** and can manipulate metadata of L4 connections during the initial connection phase. For example, a TLS inspector filter can identify whether the connection is TLS encrypted and extract relevant TLS information from it.

**2. Network filters**
Network filters work with raw data as well: the TCP packages. An example of a network filter is the TCP proxy filter that routes client connection data to upstream hosts and generates connection statistics.

**3. HTTP filters**
HTTP filters operate at layer 7 and work with HTTP data. The last network filter in the chain, HCM or HTTP connection manager filter, optionally creates these filters. The HCM filter translates from raw data to HTTP data, and the HTTP filters can manipulate HTTP requests and responses.

![image](https://tetrate.io/wp-content/uploads/2021/07/envoy-filters-1536x515.png)

**Figure 4:** Envoy filters
Listeners have a set of **TCP filters** that can interact with the TCP data. There can be more than one TCP filter in the chain, and the **last filter** in the chain is a special one called the HTTP connection manager (HCM). The HCM filter turns Envoy into an **L7 proxy**; it converts the bytes from the requests into an HTTP request.

Within the HTTP connection manager filter, another set of HTTP filters can work with the HTTP requests. This is where we can do things on the HTTP level– we can work with headers, interact with the HTTP body, etc. Within the HTTP filter is where we define the routes, and the cluster selection happens. 

The last filter in the HTTP filter chain is called a **router filter**. The router filter sends the requests to the selected cluster.

## What are HTTP filters? <a name="subparagraph5"></a>

We can think of HTTP filters as pieces of code that can interact with requests and responses. Envoy ships with numerous HTTP filters, but we can also write our filters and have Envoy dynamically load and run them. 

The HTTP filters are chained together, so we can control where the filter gets placed in the chain. The fact that filters are chained means that they need to decide whether to continue executing the next filter or stop running the chain and close the connection. 

There’s no need to have the filters compiled together with the Envoy proxy; we could do that, but it’s impractical.

By default, the filters are written in C++. However, there’s a way to write the filters in Lua script, or we can use WebAssembly (Wasm) to develop them in other languages.

## Envoy proxy and dynamic configuration <a name="subparagraph6"></a>

A significant feature of Envoy is the ability to use dynamic configuration. So instead of hardcoding information about the clusters or endpoints, we could implement a gRPC or REST service that dynamically provides information about the clusters and endpoints. 

Then in the Envoy configuration, we can reference these gRPC/REST endpoints instead of explicitly providing the configuration for clusters or endpoints.

Istio’s pilot uses the dynamic configuration to discover the services in Kubernetes. For example, it reads the Kubernetes services and Endpoints, gets the IP addresses and ports, converts the data into Envoy readable configuration, and sends it to the Envoy proxies– the data plane– through these discovery services. Effectively, this allows us to create our control plane and integrate it with Envoy.

## Install Envoy on Ubuntu Linux <a name="paragraph5"></a>
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
### Check Envoy is proxying on http://localhost:10000. <a name="paragraph7"></a>
```bash
curl -v localhost:10000
```
You can exit the server with `Ctrl-c`.

**If you run Envoy inside a Docker container you may wish to use 0.0.0.0. Exposing the admin interface in this way may give unintended control of your Envoy server.**

### Validating  Envoy configuration <a name="paragraph8"></a>

You can start Envoy in `validate mode`.

This allows you to check that Envoy is able to start with your configuration, without actually starting or restarting the service, or making any network connections.

If the configuration is valid the process will print `OK` and exit with a return code of `0`.

For invalid configuration the process will print the errors and exit with `1`.

```bash
envoy --mode validate -c my-envoy-config.yaml
```

### Envoy logging <a name="paragraph9"></a>
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

### Debugging Envoy <a name="paragraph10"></a>
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

### Configuration: Static <a name="paragraph11"></a>

To start Envoy with static configuration, you will need to specify listeners and clusters as static_resources.

You can also add an admin section if you wish to monitor Envoy or retrieve stats.

The following sections walk through the static configuration provided in the demo configuration file used as the default in the Envoy Docker container.

#### `static_resources` <a name="paragraph12"></a>

The static_resources contain everything that is configured statically when Envoy starts, as opposed to dynamically at runtime.

`envoy-demo.yaml:`
```bash
static_resources:

  listeners:
```

#### `listeners` <a name="paragraph13"></a>

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

#### `clusters` <a name="paragraph14"></a>

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

### Envoy admin interface <a name="paragraph15"></a>

The optional admin interface provided by Envoy allows you to view configuration and statistics, change the behaviour of the server, and tap traffic according to specific filter rules.

#### `admin` <a name="paragraph16"></a>

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

#### `stat_prefix` <a name="paragraph17"></a>

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
### Admin endpoints: `config_dump` <a name="paragraph18"></a>

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

### Admin endpoints: `stats` <a name="paragraph19"></a>

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
### Envoy admin web UI <a name="paragraph20"></a>

Envoy also has a web user interface that allows you to view and modify settings and statistics.

Point your browser to http://localhost:9901.



## Sources <a name="paragraph21"></a>

[Sidecar Proxy Pattern - The Basis Of Service Mesh](https://iximiuz.com/en/posts/service-proxy-pod-sidecar-oh-my/)

[Get started with Envoy Proxy in 5 minutes](https://tetrate.io/blog/get-started-with-envoy-in-5-minutes/)

[Envoy documentation](https://www.envoyproxy.io/docs/envoy/latest/)

[Configuration generator](https://www.envoyproxy.io/docs/envoy/latest/operations/tools/config_generator#start-tools-configuration-generator)

[How to Deploy Envoy as a Sidecar Proxy on Kubernetes](https://medium.com/@viggnah/how-to-deploy-envoy-as-a-sidecar-proxy-on-kubernetes-c3a3ad3935ee)

[Double proxy (with mTLS encryption)](https://www.envoyproxy.io/docs/envoy/v1.28.0/start/sandboxes/double-proxy.html)
