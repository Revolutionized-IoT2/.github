# M4. Typed, validated configuration

Applies to: see the problem description. Status: steps 1–5 done on 2026-10-13
([I07](../increments/phase-0-1.md#i07-typed-configuration-s), Core 1.2.0); step 6 comes with the
security seams (I34). The problem description is the September 2026 snapshot.

**As built.** Each service has one options type (`OrchestratorOptions`, `NodeOptions`,
`WorkflowOptions`, `InfluxConnectorOptions`) with a static `Load(IConfiguration, …)` that maps
every variable name explicitly, reads it with Core's `SettingsReader` and throws one
`ConfigurationValidationException` that lists every problem. Shared pieces are in
`RIoT2.Core.Configuration` (`SettingsReader`, `MqttOptions`) until [M1](m01-split-core-packages.md) moves them. Two
deviations from the steps below: validation runs eagerly in `Program`, not with
`ValidateOnStart()`, because the Node and the Orchestrator use their settings before the host is
built; and the rules are code in `Load`, not data annotations, so each message names the variable.
Index and dependencies: [plans/README.md](README.md). Backlog: [open-issues.md](../backlog/open-issues.md).

**Problem.** Configuration is read with `Environment.GetEnvironmentVariable` in
`OrchestratorConfigurationService`, `Node/ConfigurationService`, Elsa `RIoTConfigurationService` and
Influx `ConnectorConfigurationService`. Each has its own required/URL validation code: this review
added fail-fast checks in four slightly different styles. Tests have to mutate process-wide
environment variables, which forced `[DoNotParallelize]`.

## Steps

1. Add an options model per service (`OrchestratorOptions`, `NodeOptions`, `WorkflowOptions`,
   `InfluxConnectorOptions`, plus shared `MqttOptions`) with `[Required]`/`[Url]` data annotations
   or an `IValidateOptions<T>` implementation.
2. Map the existing `RIOT2_*` names in one place per service with
   `builder.Configuration.AddEnvironmentVariables()` and an explicit key mapping, so the variable
   names users set don't change. Bind with
   `services.AddOptions<T>().Bind(...).ValidateDataAnnotations().ValidateOnStart()`.
3. Have the configuration services receive `IOptions<T>` instead of reading the environment. Delete
   the per-service `Require*` helpers and `NodeEnvironmentValidator`; the startup validation
   replaces them.
4. Put the shared pieces (`MqttOptions`, URL validation attribute, env-name mapping helper) into
   `RIoT2.Core.Mqtt`/`RIoT2.Core.Contracts` ([M1](m01-split-core-packages.md)), or into a small shared source file until M1 lands.
5. Rewrite the configuration tests to build options from an in-memory configuration. Remove
   `[DoNotParallelize]` and the environment mutation.
6. This is also where the [A1](../architecture/target.md#a1-optional-security-mode) `RIOT2_SECURITY_MODE` switch will live.

**Done when.** No `GetEnvironmentVariable` remains outside the options registration, all four
services fail fast with the same message format, and the configuration tests run in parallel.
