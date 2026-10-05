# Expose a service over HTTP

This lab walks you through the basics of the Kubernetes Gateway API with kgateway.

You will:

- Provision a gateway
- Configure a routing rule to a backend workload, and
- Verify that requests are routed as expected.

The cluster is already running, and kgateway is already installed. The gateway and route manifests are in `data/` in this home directory.

## Deploy httpbin

```shell
kubectl apply -f https://raw.githubusercontent.com/istio/istio/refs/heads/master/samples/httpbin/httpbin.yaml
```

Wait for the `httpbin` pod to be ready:

```shell
kubectl wait --for=condition=Ready=True pod -l app=httpbin
```

## Create a gateway

The team in charge of the gateway can create a Gateway resource and configure an HTTP listener.

Inspect the gateway resource:

```shell
bat data/gtw.yaml
```

Apply the Gateway resource:

```shell
kubectl apply -f data/gtw.yaml
```

Wait for the Gateway to be programmed (ready).

```shell
kubectl wait --for=condition=Programmed=True gtw/my-gateway
```

Inspect the `status` section of the Gateway resource you just created:

```shell
kubectl get gtw my-gateway -o yaml | bat -l yaml
```

Inspect the deployed gateway artifacts:

```shell
kubectl get deploy,svc,pod
```

The deployment and service names match the name of the Gateway resource.

Application teams can create and attach their HTTPRoute to this gateway.

## Configure routing

An application team can create an HTTPRoute resource to expose the `httpbin` app on the gateway.

Inspect the HTTPRoute resource:

```shell
bat data/route.yaml
```

Above, we associate the route with the host name `httpbin.example.com`.

Apply the HTTPRoute resource:

```shell
kubectl apply -f data/route.yaml
```

Wait for the route to be attached to the gateway:

```shell
kubectl wait --for=jsonpath='{.status.listeners[0].attachedRoutes}'=1 gtw my-gateway
```

Inspect the status of the route and confirm that it has a condition "Accepted" set to "True":

```shell
kubectl get httproute httpbin -o yaml | bat -l yaml
```

## Test

Capture the gateway external IP address to the environment variable `GW_IP`:

```shell
export GW_IP=$(kubectl get gtw my-gateway -o jsonpath='{.status.addresses[0].value}')
```

Send a test request to `httpbin` through the gateway:

```shell
curl -s http://httpbin.example.com/headers --resolve httpbin.example.com:80:$GW_IP | jq
```

The response should resemble the following json output:

```json
{
  "headers": {
    "Accept": [
      "*/*"
    ],
    "Host": [
      "httpbin.example.com"
    ],
    "User-Agent": [
      "curl/8.11.1"
    ],
    "X-Forwarded-Proto": [
      "http"
    ]
  }
}
```

## Summary

The general steps for working with the Kubernetes Gateway API are:

- Creating gateways on-demand by applying the `Gateway` resource, and
- Attaching routes that direct traffic to designated backends.
