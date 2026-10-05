Agentgateway provides a number of strategies to [moderate and safeguard LLM content](https://agentgateway.dev/docs/standalone/latest/llm/prompt-guards/), from built-in support via filters, external moderation (cloud-provider guardrails), and custom webhooks.

In this lab you will explore agentgateway's built-in filters, where a match against sensitive content can either be masked, or where the request can be rejected outright.

Configure a two-panel layout for the terminal:

```shell
zellij --layout ~/two-pane-layout.kdl
```

The agentgateway binary is installed.

Click on the top panel, and run agentgateway:

Review the following configuration that proxies calls to OpenAI models:

```shell
bat config-llm.yaml
```

Start agentgateway with the above configuration:

```shell
agentgateway -f config-llm.yaml
```

Click on the bottom panel, and send a test request and observe the response:

```shell
curl -s http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-4o-mini",
    "messages": [{"role": "user", "content": "Hello, model!"}]
  }' | jq
```

## Apply a request filter

Filters can be specified using regex patterns, but agentgateway also provides [built-in patterns](https://agentgateway.dev/docs/standalone/latest/llm/prompt-guards/regex/#built-in-patterns) for email addresses, phone numbers, social security numbers, and credit card numbers.

Add a guardrail, start with a request guardrail on email addresses, where a detection results in the request being rejected:

```shell
bat config-request-guardrail.yaml
```

> [!IMPORTANT]
> Stop the running instance of agentgateway with a `Ctrl+C`.

Start agentgateway with the new configuration:

```shell
agentgateway -f config-request-guardrail.yaml
```

Test the new configuration in the other shell:

```shell
curl -s http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-4o-mini",
    "messages": [{"role": "user", "content": "John'\''s email address is johndoe@example.com"}]
  }'
```

The request should be rejected with the message `The request was rejected due to inappropriate content`.

## Mask PII in responses

Review the following configuration, which filters for phone numbers and masks them in responses, this time using a **regex pattern instead of a built-in**.

```shell
bat config-response-filter.yaml
```

> [!IMPORTANT]
> Stop the running instance of agentgateway with a `Ctrl+C`.

Start agentgateway with the new configuration:

```shell
agentgateway -f config-response-filter.yaml
```

Test the new configuration in the other shell:

```shell
curl -s http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-4o-mini",
    "messages": [{"role": "user", "content": "List five example US telephone numbers"}]
  }' | jq -r '.choices[0].message.content'
```

The telephone numbers cited in the response should all have been replace with the keyword `<masked>`.

## Try the phoneNumber builtin

Review a configuration that substitutes the above phone pattern with the `phoneNumber` builtin, which goes beyond format matching and also checks validity:

```shell
bat config-response-builtin.yaml
```

Press `Ctrl+C` to stop agentgateway and restart it with the updated configuration:

```shell
agentgateway -f config-response-builtin.yaml
```

Test the updated configuration in the other shell:

```shell
curl -s http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-4o-mini",
    "messages": [{"role": "user", "content": "List five example US telephone numbers"}]
  }' | jq -r '.choices[0].message.content'
```

The telephone numbers cited in the response should all have been replace with the keyword `<PHONE_NUMBER>`.

## Summary

We invite you to [explore guardrails](https://agentgateway.dev/docs/standalone/latest/llm/prompt-guards/) further, including some of the cloud-provider specific moderation integrations for OpenAI, AWS Bedrock, Azure AI, and Google.