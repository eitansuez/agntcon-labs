In this lab, you will gain familiarity with the [agent-substrate project](https://github.com/agent-substrate/substrate/) by working through its "quickstart" instructions.

Agent-substrate is a new project, still in early stages of development, that extends Kubernetes to run agents efficiently by assigning many agents onto a smaller set of worker pods.
The workloads become a logical entity called an actor, and the pods they are assigned to are the workers.
Actor state is resumed after it is assigned to a free worker and suspended when idle, freeing the worker again.
To learn more, aside from the [project repository](https://github.com/agent-substrate/substrate/), see [learn.agentsubstrate.dev](https://learn.agentsubstrate.dev/), a site dedicated to helping you learn and understand agent-substrate.

You will:

- Install agent-substrate on a local kind cluster.
- Deploy the "counter" demo, which demonstrates state persistence.
- Call the actor `counter` and observe it transition from SUSPENDED to RUNNING state.

## Setup

The [agent-substrate GitHub repository](https://github.com/agent-substrate/substrate/) is checked out.

Navigate to the repository folder:

```shell
cd substrate
```

Create a [kind](https://kind.sigs.k8s.io/) cluster:

```shell
./hack/create-kind-cluster.sh
```

## Install agent-substrate

Below, we select [agentgateway](https://agentgateway.dev/) as the implementation of the `atenet-router` component:

```shell
./hack/install-ate-kind.sh \
  --atenet-dataplane=agentgateway \
  --deploy-ate-system \
  --credential-provider='{"name":"k8s.io"}'
```

The installation of the agent-substrate system components takes a little time.

After installation completes, inspect the CRDs that were installed:

```shell
kubectl api-resources --api-group ate.dev
```

Note the CRD named `WorkerPool` which provisions a set of Pods as a pool of workers to which actors are assigned.

Inspect the pods that make up the agent-substrate system:

```shell
kubectl get pod -n ate-system
```

Here is a brief description of the system components:

- `ate-api-server` is the control plane, used to list workers and actors and schedule actors onto free workers.
- `ate-controller` reconciles the WorkerPool CRDs into warm worker pods (see below for more).
- `atelet` DaemonSet helps schedule an actor on a free worker by driving `ateom`, a process that runs inside each worker pod.
- `atenet-router` routes requests to actors.
- `atenet-egress` routes an actor's outbound traffic through the egress gateway.
- `postgres` is the store for the control plane. It lets agent-substrate keep track of actors, workers, and their state (free or assigned).
- `rustfs` is a bucket where state snapshots are stored to support suspending and resuming actors.

For more information, see the project's [architecture documentation page](https://github.com/agent-substrate/substrate/blob/main/docs/architecture.md).

## Explore the "counter" demo

The counter demo illustrates state preservation across suspend and resume cycles.

Deploy the demo:

```shell
./hack/install-ate-kind.sh --deploy-demo-counter
```

Inspect the WorkerPool:

```shell
kubectl get workerpool -n ate-demo-counter
```

`ate-controller` reconciles the WorkerPool into a Kubernetes Deployment with 3 replicas:

```shell
kubectl get pod -n ate-demo-counter
```

List the workers by calling the `ate-api-server`:

```shell
kubectl ate get workers
```

All workers are "FREE", meaning that none are assigned to an actor.

An "atespace" named `ate-demo-counter` was created as part of the deployment.

Inspect the generated ActorTemplate:

```shell
kubectl ate get actor-templates -a ate-demo-counter
```

`ate-api-server` reconciles the ActorTemplate into a "golden" snapshot, which can be viewed as a tag:

```shell
kubectl ate get tags --atespace ate-golden
```

## Create and exercise a "counter" actor

Create the "counter" actor in the same ate-space where the ActorTemplate resides:

```shell
kubectl ate create actor my-counter-1 \
  --atespace ate-demo-counter --template counter
```

The actor is initially in SUSPENDED state.

Deploy a `curl` pod from which to call the actor:

```shell
kubectl apply -f \
  https://github.com/istio/istio/raw/refs/heads/master/samples/curl/curl.yaml
```

```zellij layout="two-pane"
```

The idea is to catch the actor transition from SUSPENDED to RUNNING state.

Watch the actor:

```shell panel="watch"
watch -n 1 kubectl ate get actor my-counter-1 --atespace ate-demo-counter
```

Note its SUSPENDED state.

Next, call the `atenet-router` service, targeting the "counter" actor:

```shell panel="client"
kubectl exec deploy/curl -- \
  curl -s -X POST -H "ate-target-actor: ate-demo-counter/my-counter-1" \
  http://atenet-router.ate-system.svc.cluster.local
```

The actor status transitions from SUSPENDED state to RUNNING state.

In the response, the counter value is 1.

Call the API server to suspend the actor:

```shell panel="client"
kubectl ate suspend actor my-counter-1 --atespace ate-demo-counter
```

Make another call:

```shell panel="client"
kubectl exec deploy/curl -- \
  curl -s -X POST -H "ate-target-actor: ate-demo-counter/my-counter-1" \
  http://atenet-router.ate-system.svc.cluster.local
```

Watch the actor switch back to RUNNING state and increment the counter.

The actor's state moves with it to whichever worker it gets assigned to.

The counter didn't lose state: in the response, the counter value is now 2.

## Summary

We have seen how agent-substrate can suspend and resume an actor onto an available worker, while preserving state, effectively reducing the compute resources required to run workloads.
