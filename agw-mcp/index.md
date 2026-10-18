Besides serving as a proxy for LLM consumption, agentgateway is equally capable of proxying traffic to and from MCP servers.

In this lab, you will explore a feature known as [Virtual MCP](https://agentgateway.dev/docs/standalone/latest/mcp/connect/virtual/), that permits presenting multiple MCP servers as a single federated MCP server.

## Proxy an MCP server

Run the ["Everything" MCP server](https://github.com/modelcontextprotocol/servers/blob/main/src/everything/README.md) locally on port 3001:

```shell panel="gateway"
npx --yes @modelcontextprotocol/server-everything streamableHttp &
```

Review the agentgateway proxy configuration:

[View config-mcp.yaml](bat:gateway:config-mcp.yaml)

The above configuration format is a short-hand that agentgateway offers for proxying MCP servers: any MCP servers listed under `targets` are automatically proxied on port 3000 by default.

Start agentgateway:

```shell panel="gateway"
agentgateway -f config-mcp.yaml
```

**List the tools** hosted by the MCP server by calling the agentgateway proxy that listens on port 3000:

```shell panel="client"
mcp-inspector --cli http://localhost:3000/mcp \
  --transport http --method tools/list | jq '.tools[].name'
```

Call the `echo` tool:

```shell panel="client"
mcp-inspector --cli http://localhost:3000/mcp \
  --transport http --method tools/call \
  --tool-name echo --tool-arg message="hello world" | jq
```

## Federate multiple MCP servers

> [!IMPORTANT]
> [Stop agentgateway](key:Ctrl+C){panel="gateway"}

Review a proxy configuration that federates two MCP servers (we add a [second MCP server
](https://search.solo.io/mcp)):

[View config-virtual.yaml](bat:gateway:config-virtual.yaml)

Restart agentgateway with the updated configuration:

```shell panel="gateway"
agentgateway -f config-virtual.yaml
```

List the tools again:

```shell panel="client"
mcp-inspector --cli http://localhost:3000/mcp \
  --transport http --method tools/list | jq '.tools[].name'
```

Note how the response now aggregates the tools across both MCP servers, each prefixed by its name `everything` or `search`.

## Turn off prefixing

> [!IMPORTANT]
> [Stop agentgateway](key:Ctrl+C){panel="gateway"}

Next, we tweak to the configuration and choose to turn off prefixing of the tool names:

[View config-noprefix.yaml](bat:gateway:config-noprefix.yaml)

Restart agentgateway with the updated configuration:

```shell panel="gateway"
agentgateway -f config-noprefix.yaml
```

List the tools again:

```shell panel="client"
mcp-inspector --cli http://localhost:3000/mcp \
  --transport http --method tools/list | jq '.tools[].name'
```

Note how the tool names no longer carry a prefix.

## Expose a subset of the tools, via authorization

Through CEL expressions we can control which tools to expose.

> [!IMPORTANT]
> Stop agentgateway (`Ctrl+C`).

Review the following configuration, which exposes only `echo` and `search`:

[View config-filtered.yaml](bat:gateway:config-filtered.yaml)

A more powerful authorization policy can use identity information to expose a different set of tools to different categories of users, for example, by using a CEL expression that evaluates elements of the user's JWT token.

Restart agentgateway with the updated configuration:

```shell panel="gateway"
agentgateway -f config-filtered.yaml
```

List the tools again:

```shell panel="client"
mcp-inspector --cli http://localhost:3000/mcp \
  --transport http --method tools/list | jq '.tools[].name'
```

A call to `echo` continues to function:

```shell panel="client"
mcp-inspector --cli http://localhost:3000/mcp \
  --transport http --method tools/call \
  --tool-name echo --tool-arg message="hello world" | jq
```

However a call to any of the filtered tools will fail:

```shell panel="client"
mcp-inspector --cli http://localhost:3000/mcp \
  --transport http --method tools/call \
  --tool-name get-sum --tool-arg a=3 --tool-arg b=4 2>&1 | jq .
```

The response should state:

```json
{
  "error": {
    "code": "tool_not_found",
    "message": "Tool 'get-sum' not found on server."
  }
}
```

## Summary

Agentgateway is a powerful, AI-native gateway that handles both LLM consumption and MCP traffic scenarios.
It supports both the latest MCP specification and servers that adhere to older revisions.
Learn more at [https://agentgateway.dev/](https://agentgateway.dev/).