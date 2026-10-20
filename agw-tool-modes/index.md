Solo Enterprise for agentgateway provides a feature known as "Tool Modes", where MCP server backends can be configured with either Standard, Search, or Code mode (there's also a fourth "CodeSearch" mode which is a combination of the last two).

In this lab, you will learn about these tool modes and how they can reduce of the size of the context window, or the number of agentic turns, both of which directly affect costs.

As tool modes are an enterprise feature, begin by installing Solo Enterprise for Agentgateway.
Agentgateway can run in either of two deployment modes:  Standalone or Kubernetes;
this lab uses the Kubernetes version.

## [Install Solo Enterprise for agentgateway](https://docs.solo.io/agentgateway/latest/install/helm/):

A local Kubernetes cluster is running.

Apply the Kubernetes Gateway API CRDs:

```shell
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml
```

Next, use [Helm](https://helm.sh/) to apply the agentgateway CRDs:

```shell
helm upgrade --install enterprise-agentgateway-crds \
  oci://us-docker.pkg.dev/solo-public/enterprise-agentgateway/charts/enterprise-agentgateway-crds \
  --namespace agentgateway-system --create-namespace \
  --version v2026.9.3
```

Finally, deploy Helm chart for the agentgateway controller and other components:

```shell
helm upgrade --install enterprise-agentgateway \
  oci://us-docker.pkg.dev/solo-public/enterprise-agentgateway/charts/enterprise-agentgateway \
  --namespace agentgateway-system \
  --version v2026.9.3  \
  --set-string licensing.licenseKey=$AGENTGATEWAY_LICENSE_KEY
```

Verify installation:

```shell
kubectl get pods -n agentgateway-system
```

## Provision a gateway

Review the manifest for a simple HTTP gateway in the `default` namespace:

[View gtw.yaml](bat:gtw.yaml)

Apply it to the cluster:

```shell
kubectl apply -f gtw.yaml
```

Wait for the gateway to be ready:

```shell
kubectl wait --for condition=Programmed gtw agentgateway-proxy
```

## Deploy an MCP server

Next, deploy the canonical [`server-everything`](https://github.com/modelcontextprotocol/servers/tree/main/src/everything) MCP server.

Review the deployment manifest:

[View server-everything.yaml](bat:server-everything.yaml)

Apply it to the cluster:

```shell
kubectl apply -f server-everything.yaml
```

Wait for the deployment to finish rolling out:

```shell
kubectl rollout status deploy mcp-everything
```

## Define the backends

Define alternative [EnterpriseAgentgatewayBackend](https://docs.solo.io/agentgateway/latest/reference/api/solo/#enterpriseagentgatewaybackend) resources to the MCP server, configured for each [`toolMode`](https://docs.solo.io/agentgateway/latest/reference/api/solo/#entmcptoolmode):

Here is the first backend, which specifies _Standard_ mode:

[View std-backend.yaml](bat:std-backend.yaml)

The other backends alter only the `toolMode` field to "Search" or "Code".

Apply the backend definitions:

```shell
kubectl apply -f std-backend.yaml
kubectl apply -f search-backend.yaml
kubectl apply -f code-backend.yaml
```

Visually verify that the backends were accepted:

```shell
kubectl get enterpriseagentgatewaybackends
```

## Define routes on the gateway to the backends 

Below, we use a path-based convention to target each MCP server:

[View std-route.yaml](bat:std-route.yaml)

The other two routes are similarly configured with their respective path.

Apply the routes for each agentgateway backend:

```shell
kubectl apply -f std-route.yaml
kubectl apply -f search-route.yaml
kubectl apply -f code-route.yaml
```

In the gateway status, confirm three attached routes:

```shell
kubectl get gtw agentgateway-proxy \
  -o jsonpath='{.status}' | jq | grep attachedRoutes
```

## Test with the MCP Inspector CLI

Capture the gateway IP address:

```shell
export GW_IP=$(kubectl get gtw agentgateway-proxy -o jsonpath='{.status.addresses[0].value}')
```

### List tools

Below, call `tools/list` and see what you get for each of:

- _Standard_ mode
- _Search_ mode
- _Code_ mode

_Standard_ mode:

```shell
mcp-inspector --cli http://$GW_IP/mcp/standard --transport http \
  --method tools/list | jq '.tools[].name'
```

We get back the usual list of tools from the MCP server.

_Search_ mode:

```shell
mcp-inspector --cli http://$GW_IP/mcp/search --transport http \
  --method tools/list | jq '.tools[].name'
```

Here, the list consists only of `get_tool` and `invoke_tool`.

_Code_ mode:

```shell
mcp-inspector --cli http://$GW_IP/mcp/code --transport http \
  --method tools/list | jq '.tools[].name'
```

The list consists only of `run_code`.

In this last instance, it's worthwhile taking a closer look at the `description` field for `run_code`:

```shell
mcp-inspector --cli http://$GW_IP/mcp/code --transport http \
  --method tools/list | jq -r '.tools[].description' | bat -l md
```

To understand code mode, take a moment to read the above `run_code` tool description handed to the LLM as instructions for how to call the MCP server in this mode.

Next, let us compare the size of each response payload.

### Compare `tools/list` payloads

Capture the tools/list response for each "server":

```shell
mcp-inspector --cli http://$GW_IP/mcp/standard --transport http \
  --method tools/list > out/standard-list.json
mcp-inspector --cli http://$GW_IP/mcp/search --transport http \
  --method tools/list > out/search-list.json
mcp-inspector --cli http://$GW_IP/mcp/code --transport http \
  --method tools/list > out/code-list.json
```

Compare the file sizes for the tools/list responses from each mode:

```shell
ls -lF out/*-list.json
```

_Search_ mode is ~ 30% the size of the standard list, and that's for a single example MCP server.

For _Standard_ mode, the payload grows linearly with the number of tools.  For _Search_ mode it stays the same.

### How tool calls work

For _Standard_ mode, we communicate with the gateway in the same way as with the MCP server directly.

For example:

```shell
mcp-inspector --cli http://$GW_IP/mcp/standard --transport http \
  --method tools/call --tool-name echo --tool-arg message="hello world" \
  | jq
```

With _Search_ mode, the process becomes a two-step operation.

First, obtain the contract for a given tool:

```shell
mcp-inspector --cli http://$GW_IP/mcp/search --transport http \
  --method tools/call \
  --tool-name get_tool \
  --tool-arg name=echo | jq
```

Next, invoke the tool:

```shell
mcp-inspector --cli http://$GW_IP/mcp/search --transport http \
  --method tools/call \
  --tool-name invoke_tool \
  --tool-arg name=echo \
  --tool-arg 'arguments={"message":"hello"}' | jq
```

For _Code_ mode, the context is a user prompt that requires a combination of tool calls, that we wish to accomplish with a single trip to the gateway.
The gateway in turn interacts with potentially multiple backend tools.

A trivial example for the "server-everything" MCP server would be to echo the result of an addition.

Inspect the code you're about to run:

[View code.ts](bat:code.ts)

Send the code to the `run_code` tool for execution on the gateway:

```shell
mcp-inspector --cli http://$GW_IP/mcp/code --transport http \
  --method tools/call \
  --tool-name run_code \
  --tool-args-json "$(jq -n --rawfile code code.ts '{code: $code}')" | jq
```

## The wider context

When we build agents, we configure them with tools pointing to agentgateway as the MCP server.
The agent becomes the client to the MCP server.

Agentgateway backends are not restricted to representing a single backend MCP server: a backend can federate multiple MCP servers.

When the list of tools is long, instead of paying up-front for a huge `tools/list` payload that gets inserted into the LLM's context with every turn, we can switch to _Search_ mode.
We get a tiny `tools/list` payload and defer the cost of getting the description, input and output schema _per tool_ to the moment when the LLM actually needs to invoke it.
It calls `get_tool` followed by `invoke_tool`.

When using code mode, the "smarts" that write the TypeScript that is submitted to the `run_code` tool call come from the LLM.

## Summary

To provide a deeper understanding and appreciation of the economics of using agentic solutions, Solo.io has written a series of blog posts, the main one being [Unit Economics of Agentic AI](https://www.solo.io/blog/unit-economics-of-agentic-ai-context-turns-model).

The following "sub-blogs" (underneath that umbrella topic) discuss search mode (also known as progressive discovery) and code mode:

- [Keeping Context and Tokens Low with Progressive Disclosure in agentgateway](https://www.solo.io/blog/keeping-context-and-tokens-low-with-progressive-disclosure-in-agentgateway)
- [APIs For Your Agents With Code Mode](https://www.solo.io/blog/apis-for-your-agents-with-code-mode)