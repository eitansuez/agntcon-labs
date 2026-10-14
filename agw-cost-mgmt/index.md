In this hands-on lab, you will explore the agentgateway open-source project's standalone distribution (there's also a Kubernetes version), and specifically the features designed to help manage and control LLM costs.

You will:

- Learn to proxy calls to LLMs with agentgateway.
- See how agentgateway tracks token usage.
- Learn to track usage in monetary terms instead of tokens.
- Attribute usage by team and by user.
- Limit usage by team and by user.

## Setup

[Configure a two-panel layout](zellij:two-pane) for the terminal.

Verify that the agentgateway binary is installed by running it with the `--version` flag:

```shell panel="gateway"
agentgateway --version
```

The simplest way to start with agentgateway is to just run it:

```shell panel="gateway"
agentgateway
```

Inspect the console logs.  Here are some relevant pieces of information:

```console
state_manager   Watching .. ~/.config/agentgateway/config.yaml
app     serving UI at http://localhost:4000/ui
proxy::gateway  started bind    bind="bind/4000"
```

Agentgateway detects that no configuration file was supplied, and writes a default configuration to the folder `~/.config/agentgateway`.

Print a directory listing to review the files contained therein:

```shell panel="client"
ls -1 ~/.config/agentgateway
```

- `config.yaml` is the gateway configuration.
- `data.db` is a local sqlite database where agentgateway stores its data.

### The configuration file

Display the contents of `config.yaml`:

```shell panel="client"
bat ~/.config/agentgateway/config.yaml
```

By default, you get a starting configuration that specifies:

- The location of the sqlite database on the filesystem.
- A default gateway listening on port 4000.
- The UI's association to the gateway implies that it is served by that gateway, on port 4000 at the `/ui` path.

Agentgateway is designed to proxy agentic services, such as MCP servers and models (none are configured yet) as well as traditional microservices.

### The UI

[Explore the UI](service:agentgateway-ui). It opens in a new browser tab.

- If presented with a dialog, click Continue.
- LLMs, MCP Servers or traditional services can be configured directly from the UI, but in this lab you will directly modify the configuration file.
- In the navigation panel, there is a section dedicated to each of these three types of workloads: LLM, MCP, and Traffic.

> [!IMPORTANT]
> Come back to this lab page.

## Proxy LLMs

Agentgateway supports a [long list of LLM providers](https://agentgateway.dev/docs/standalone/latest/llm/about/#native-providers).

Inspect the following configuration:

```shell panel="client"
bat config-llm.yaml
```

The configuration adds a entry to call out to OpenAI models.
The API key is passed via an environment variable.
This is an important point: in enterprise environments, the platform team manages agentgateway, and end-users never see the API key.

The client specifies the model they wish to use and the gateway will forward the request to the model in question.

### Test it

Make the new configuration active:

```shell panel="client"
cp config-llm.yaml ~/.config/agentgateway/config.yaml
```

Make a call to the gateway listening on port 4000, specifying `gpt-5-nano` for the model:

```shell panel="client"
curl -s http://localhost:4000/v1/chat/completions \
   --header "Content-Type: application/json" \
   --data '{
     "model": "openai/gpt-5-nano",
     "messages": [ {
        "role": "user",
        "content": "Tell me a one-sentence story"
     } ]
   }' | jq
```

Try a different model, say, `gpt-5-mini`:

```shell panel="client"
curl -s http://localhost:4000/v1/chat/completions \
   --header "Content-Type: application/json" \
   --data '{
     "model": "openai/gpt-5-mini",
     "messages": [ {
        "role": "user",
        "content": "Tell me a one-sentence story"
     } ]
   }' | jq
```

Review the agentgateway logs and note the presence of `gen_ai` prefixed fields including the request model, response model, input and output tokens.

Token consumption is captured in the logs!

### Review the UI

[Switch to the agentgateway UI](service:agentgateway-ui), and **click the "Refresh" icon in the top-right corner of the page**.

- Under "Models", note that the OpenAI model is configured.
- Under "Logs", you should see the recent calls, and the model and provider information.
- Expand the top log entry, and note the timing and token usage information is captured as well.

Using the selectors in the top panel, try to filter the list of log entries by model.

Under "Analytics" try to group LLM traffic by model.

> [!IMPORTANT]
> Come back to this lab page.

## The agentgateway CLI

Agentgateway provides a convenient command line interface, `agctl`.

Verify that `agctl` is installed:

```shell panel="client"
agctl --help
```

## From tokens to money

The `agctl` CLI provides a subcommand to import a cost catalog from a variety of sources, the default source being [models.dev](https://models.dev/).

Pull down costs from [models.dev](https://models.dev/) into the file `cost-catalog.json`:

```shell panel="client"
agctl costs import --out ~/.config/agentgateway/cost-catalog.json
```

Review the following updated configuration file, which adds the `modelCatalog` configuration pointing to the file just produced:

```shell panel="client"
bat config-costs.yaml
```

Update agentgateway with the new configuration:

```shell panel="client"
cp config-costs.yaml ~/.config/agentgateway/config.yaml
```

The same process can be alternatively performed directly [from the UI](service:agentgateway-ui)'s "Costs" page, by clicking on "Refresh base costs."

> [!IMPORTANT]
> [Stop agentgateway](key:Ctrl+C){panel="gateway"}

Restart agentgateway to highlight the cost information in the logs:

```shell panel="gateway"
agentgateway | grep --line-buffered --color=always -E 'agw.ai.usage.cost.total=[0-9.]+|$'
```

### Test it

Send a couple of new requests to OpenAI:

```shell panel="client"
curl -s http://localhost:4000/v1/chat/completions \
   --header "Content-Type: application/json" \
   --data '{
     "model": "openai/gpt-5-nano",
     "messages": [ {
        "role": "user",
        "content": "Tell me a one-sentence story"
     } ]
   }' | jq
```

The log entry contains cost information!

And:

```shell panel="client"
curl -s http://localhost:4000/v1/chat/completions \
   --header "Content-Type: application/json" \
   --data '{
     "model": "openai/gpt-5-mini",
     "messages": [ {
        "role": "user",
        "content": "Tell me a one-sentence story"
     } ]
   }' | jq
```

> [!IMPORTANT]
> Each time you switch to the agentgateway UI after modifying the configuration, **click the "Reload" icon in the top-right corner of the page**.

Visit the "Logs" page again, and note that the log entries now report cost information in addition to token usage.

> [!IMPORTANT]
> Come back to this lab page.

## Virtual API keys for group and user attribution

So far, you can monitor token usage and cost, and even attribute costs by provider and model.
Another important attribution dimension is by team and user.

Agentgateway's "Virtual API keys" feature let you do just that.
We can define and give teams and users their own virtual API keys that they use when configuring their clients.

The API Key is supplied by default in the request Authorization header, and a request without a key is denied with an HTTP 401 (Unauthorized).

Review the following Virtual API key configuration, under `llm.policies`, which configure an API key for two teams: Engineering and Marketing.

```shell panel="client"
bat config-apikeys.yaml
```

Apply the updated configuration:

```shell panel="client"
cp config-apikeys.yaml ~/.config/agentgateway/config.yaml
```

Send a request without an API Key:

```shell panel="client"
curl -s http://localhost:4000/v1/chat/completions \
   --header "Content-Type: application/json" \
   --data '{
     "model": "openai/gpt-5-mini",
     "messages": [ {
        "role": "user",
        "content": "Tell me a one-sentence story"
     } ]
   }'
```

That request produces an error: `api key authentication failure.`

Send a request using the Engineering team's API key:

```shell panel="client"
curl -s http://localhost:4000/v1/chat/completions \
   --header "Content-Type: application/json" \
   --header "Authorization: Bearer agw_sk_mZPNQa88c7xI5FL1ALauytmqXWdafhUs" \
   --data '{
     "model": "openai/gpt-5-mini",
     "messages": [ {
        "role": "user",
        "content": "Tell me a one-sentence story"
     } ]
   }' | jq
```

Send another request, this time using the Marketing team's API key:

```shell panel="client"
curl -s http://localhost:4000/v1/chat/completions \
   --header "Content-Type: application/json" \
   --header "Authorization: Bearer agw_sk_6KNTk5qnp4xstJnusgfcsUkTTCdI0cih" \
   --data '{
     "model": "openai/gpt-5-mini",
     "messages": [ {
        "role": "user",
        "content": "Tell me a one-sentence story"
     } ]
   }' | jq
```

Navigate to the "Logs" page and note that the latest log entries have a group attribution.
Visit the "Analytics" page and under "Group by", select "Group" and see the token or cost breakdown by group.

> [!IMPORTANT]
> Come back to this lab page.

## Apply usage limits

With group attribution in place, the natural next step is to configure limits per group (or any other dimension we choose).

Review the following rate limit server configuration (configured with artificially low limits to demonstrate rate limiting) that limits the engineering team to 200 tokens per minute and marketing to 50 tokens per minute:

```shell panel="client"
bat ratelimit-config/config.yaml
```

The rate limit server and its backing redis server are already running in Docker Compose.

Review the following agentgateway configuration adds a `remoteRateLimit` section that maps each request's group attribution to the rate limit server's bucket key.

```shell panel="client"
bat config-ratelimit.yaml
```

Update agentgateway's configuration:

```shell panel="client"
cp config-ratelimit.yaml ~/.config/agentgateway/config.yaml
```

Send a few requests using the Marketing team's API key and note the HTTP response code, after a couple of requests starts returning 429 (Rate limited) responses:

```shell panel="client"
for i in {1..5}; do
   curl -o /dev/null -s -w "%{http_code}\n" http://localhost:4000/v1/chat/completions \
      --header "Content-Type: application/json" \
      --header "Authorization: Bearer agw_sk_6KNTk5qnp4xstJnusgfcsUkTTCdI0cih" \
      --data '{
      "model": "openai/gpt-5-mini",
      "messages": [ {
         "role": "user",
         "content": "Tell me a one-sentence story"
      } ]
      }'
done
```

The engineering team's budget is distinct, and so has not been exhausted:

```shell panel="client"
curl -o /dev/null -s -w "%{http_code}\n" http://localhost:4000/v1/chat/completions \
   --header "Content-Type: application/json" \
   --header "Authorization: Bearer agw_sk_mZPNQa88c7xI5FL1ALauytmqXWdafhUs" \
   --data '{
     "model": "openai/gpt-5-mini",
     "messages": [ {
        "role": "user",
        "content": "Tell me a one-sentence story"
     } ]
   }'
```

## Agentgateway 1.5 and token budgets!

If the above cost control features weren't enough, version 1.5 of agentgateway introduces [per API key token budgets](https://agentgateway.dev/docs/standalone/latest/llm/cost-controls/budget-limits/per-key/) that can be expressed in monetary terms, with configurable actions (Audit or Block), providing even more control and flexibility for controlling LLM consumption costs.

## Summary

This was a quick tour of the main cost control features in agentgateway that pertain to LLM consumption.
Agentgateway also supports ways of reducing the size of the context window relating to communications with MCP servers, covered in a separate lab: MCP standard mode vs search and code modes.