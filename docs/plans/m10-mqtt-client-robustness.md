# M10. MQTT client robustness (backlog item 3)

Applies to: see the problem description. Status: snapshot from the September 2026 platform review. Verify against the code before starting work.
Index and dependencies: [plans/README.md](README.md). Backlog: [open-issues.md](../backlog/open-issues.md).

## Problem (verified in `Core/Utils/MqttClient.cs`)

- `Publish` calls `_client.EnqueueAsync` without a null check, so publishing before `Start` throws
  a `NullReferenceException`.
- Every publish is QoS 2, but subscriptions use `MqttTopicFilterBuilder` defaults (QoS 0), so
  delivery is effectively QoS 0 (see [7.1](../design/reliable-delivery.md)).
- The port is fixed at 1883 unless the second constructor is used, and no configuration variable
  sets it. There is no TLS.
- The managed client's pending queue is unbounded (`MaxPendingMessages` not set), so a long broker
  outage grows memory without limit while reports keep coming.
- Application handlers are awaited inline in `handleMqttMessageReceived`, so one slow or throwing
  handler delays or breaks every later message.
- `Dispose()` blocks with `Stop().GetAwaiter().GetResult()`, and there is no `CancellationToken`
  anywhere.
- The Node `/health` endpoint is liveness-only because `INodeMqttService` doesn't expose connection
  state.

In `DeviceSchedulerService`, `_deviceService_DevicesUpdated` blocks the event thread with
`_lifecycle.Wait()` and `GetAwaiter().GetResult()` while reconfiguring Quartz. That can deadlock if a
running refresh job is waiting on the device service's lifecycle lock during
`ReconfigureDevicesAsync`. `SchedulerEvent` is also a `static` event.

## Steps

1. **Options.** `MqttOptions` ([M4](m04-typed-configuration.md)): `Host` (`RIOT2_MQTT_IP`, unchanged), `Port`
   (`RIOT2_MQTT_PORT`, new, default 1883), `UseTls`/`CaFile` (the [7.5](../design/security-mode.md) seam), `ClientId`, credentials,
   `KeepAlive`, `MaxPendingMessages` (default 10,000). `MqttClient` gets a constructor that takes the
   options, and the existing constructors stay.
2. **QoS.** Add a RIoT2-owned `MqttQos` enum (`AtMostOnce`, `AtLeastOnce`, `ExactlyOnce`) so callers
   never see MQTTnet types. The default is **QoS 1** for publishing and subscribing (decision in
   7.1). Add `Start(params MqttSubscription[])` with a QoS per topic; `Start(params string[])` uses
   QoS 1.
3. **Guarded async publish.** Add `PublishAsync(topic, payload, qos = AtLeastOnce, retain = false,
   CancellationToken)`. It throws `InvalidOperationException("MQTT client not started")` before
   `Start`. The existing `Publish` becomes an `[Obsolete]` wrapper.
4. **Bounded pending queue.** Set `MaxPendingMessages` and
   `PendingMessagesOverflowStrategy.DropOldestQueuedMessage`. Log dropped messages with a
   rate-limited warning and count them (`riot2.mqtt.dropped`, [7.4](../design/operations.md)).
5. **Handler isolation.** Received messages go into a bounded channel with one worker loop per
   client. Each handler is invoked in its own `try/catch` with logging, so a failing handler no
   longer affects the others or MQTTnet's receive loop. When the channel is full the worker applies
   backpressure: MQTTnet's receive waits, and QoS 1 redelivers.
6. **Lifecycle and state.** Add `StopAsync(CancellationToken)` and `IAsyncDisposable`, and make
   `Dispose()` a bounded best effort (5 s). Add a `ConnectionStateChanged` event and
   `IsConnected`. `INodeMqttService` gets `bool IsConnected { get; }`, so the Node `/health` can
   report MQTT like the orchestrator's does.
7. **Scheduler.** `DevicesUpdated` only writes the event into a channel. A background loop owned by
   `DeviceSchedulerService` reconfigures Quartz asynchronously, with no `Wait()` or
   `GetAwaiter().GetResult()`. `SchedulerEvent` becomes an instance event; the static event stays as
   an `[Obsolete]` forwarder for one release.
8. **MQTTnet version.** Stay on MQTTnet 4.3.x. Version 5 removes `ManagedMqttClient`. After this plan
   all MQTTnet types are internal to `MqttClient`, so a later v5 migration only touches this one
   class.

**Tests** (in-process MQTTnet server):

- Publishing before start throws the clear exception.
- A QoS 1 message published during a broker restart arrives after reconnect.
- Queue overflow drops the oldest message and counts it.
- A throwing handler doesn't stop the next message.
- TLS connects with a test CA.
- Reconfiguring the scheduler while a refresh job runs doesn't deadlock (regression test).

**Done when.** No MQTTnet type appears in the public API, all clients use QoS 1, pending messages are
bounded, and the Node health check reports MQTT state.
