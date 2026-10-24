kagent integrates with [agent-substrate](https://github.com/agent-substrate/substrate/), an exciting new project that promises to dramatically improve resource consumption for agentic systems running on Kubernetes.

In this lab, you will explore an [example scenario from the kagent project documentation](https://kagent.dev/docs/kagent/examples/agent-substrate/).

You will:

- Install agent-substrate on a local Kubernetes cluster
- Install kagent configured with integration for agent-substrate
- Deploy and interact with a SandboxAgent, running as an agent-substrate Actor

## Concepts

- The kagent and kmcp projects traditionally deploy agents and MCP servers as Kubernetes deployments.
- Agent substrate is an extension to Kubernetes that allows running agents efficiently on Kubernetes not as deployments but as logical Actors that get multiplexed onto "Worker" pods from configurable worker pools.

The kagent project is being retooled to take advantage of these capabilities.
In this lab you will deploy a "SandboxAgent" resource, designed to deploy your agent as an Actor in agent-substrate.

## Install agent-substrate

Install agent-substrate using Helm.

First the CRDs:

```shell
helm upgrade --install substrate-crds \
  oci://ghcr.io/kagent-dev/substrate/helm/substrate-crds \
  --version 0.0.10 \
  --namespace ate-system --create-namespace --wait
```

Next, install the Helm chart for the agent-substrate system components:

```shell
helm upgrade --install substrate \
  oci://ghcr.io/kagent-dev/substrate/helm/substrate \
  --version 0.0.10 \
  --namespace ate-system --wait
```

## Confirm installation

Inspect the agent-substrate CRDs:

```shell
kubectl api-resources --api-group ate.dev
```

Inspect the agent-substrate system components:

```shell
kubectl get pod -n ate-system
```

## Install kagent with agent-substrate integration

Install the kagent CRDs.

```shell
helm upgrade --install kagent-crds \
  oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds \
  --version 0.10.0-rc1 \
  --namespace kagent --create-namespace --wait
```

Install kagent:

```shell
helm upgrade --install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --version 0.10.0-rc1 \
  --values minimal.yaml \
  --namespace kagent --timeout 10m --wait \
  --set providers.openAI.apiKey="$OPENAI_API_KEY" \
  --set providers.default=openAI \
  --set controller.substrate.enabled=true \
  --set controller.substrate.ateApiEndpoint=dns:///api.ate-system.svc:443 \
  --set controller.substrate.ateApiInsecure=true \
  --set substrateWorkerPool.create=true \
  --set substrateWorkerPool.replicas=1 \
  --set substrateWorkerPool.ateomImage=ghcr.io/kagent-dev/substrate/ateom-gvisor:v0.0.10
```

Note the configuration values that enable integration with agent-substrate and that configure the location of the agent-substrate API server.
Other configuration fields set the default number of replicas for WorkerPools and to use gVisor for the sandbox configuration.

```service kagent-dashboard
```

> [!NOTE]
> Ignore the stock instructions from the console about "accessing the UI."
> On the first page you encounter in the UI, click "skip wizard."

Once installation is complete, inspect the worker pool:

```shell
kubectl get workerpool -n kagent
```

## Create a Sandbox Agent

The kagent CRD `SandboxAgent` designates an agent that is to be run on agent-substrate: as an actor, associated with a worker pool.

Inspect the specification for a simple declarative SandboxAgent:

```view
sandbox-agent.yaml
```

The `workerPoolRef` instructs kagent to map the agent onto the WorkerPool `kagent-default`.

Apply the sandbox agent manifest to the cluster:

```shell
kubectl apply -f sandbox-agent.yaml
```

For standard Agent resources, the workload is visible as a pod in the namespace where it is defined.
However, for a resource of type SandboxAgent, an agent-substrate actor is defined instead.

Inspect the deployments in the `kagent` namespace:

```shell
kubectl get deploy -n kagent
```

Confirm that:

- The deployment `kagent-default` is present, which corresponds to the worker pool.
- No deployment is present for the sandbox agent `hello-substrate`.

## Inspect the state of agent substrate

Review the Substrate dashboard:

```service kagent-dashboard subpath="/substrate" subpath-caption="Substrate" tab="substrate"
```

It lists:

- Worker pools: you should see the `kagent-default` worker pool.
- Actor templates: an actor template is created per sandbox agent; there should be one present for `hello-substrate`.
- Actors: a gold snapshot for the actor is created when the actor template was reconciled.
  The actor for `hello-substrate` is lazily created upon initial interaction with the agent.
- Worker: since the worker pool was configured with a single replica, only one worker is listed.

Keep the page open.

## Interact with the agent

The `hello-substrate` agent listed as a card on the kagent home page.

Begin a chat session with the `hello-substrate` agent:

```service kagent-dashboard subpath="/agents/kagent/hello-substrate/chat" subpath-caption="Chat" tab="chat"
```

Each time you send the agent a message, the substrate dashboard will show the `hello-substrate` actor's status change from SUSPENDED to RUNNING.
As soon as the request is handled, kagent puts the actor back into SUSPENDED state.

The best way to see this in action is to switch to the Substrate dashboard tab you left open, immediately each time after sending the agent a message.

## Summary

In this lab, you quickly and easily deployed kagent and agent-substrate, and then deployed a declarative agent that runs efficiently in a WorkerPool.