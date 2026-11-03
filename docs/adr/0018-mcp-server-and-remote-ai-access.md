# 0018. An MCP server in the orchestrator, with authenticated remote access through a tunnel

- Status: Accepted
- Date: 2026-11-03
- Applies to: RIoT2.Net.Orchestrator, RIoT2.UI, deploy/

## Context

AI assistants (Claude, ChatGPT, VS Code and other agents) talk to systems through the Model Context
Protocol (MCP). The user wants to control RIoT2 from them, also from the internet: ChatGPT and
Claude.ai call remote MCP servers from their own clouds, over https, and sign users in with OAuth 2.1
as the MCP authorization specification describes.

The orchestrator already has what the tools need: the templates and values, the command outbox,
the variables, the workflow engine behind `IWorkflowEngine`, and the Run LLM step's tools
([ADR 0016](0016-integrated-workflows-and-llm.md)). But RIoT2 is anonymous by design
([ADR 0002](0002-isolated-network-security-model.md): no port forwarding), and the optional security
mode ([ADR 0004](0004-optional-security-mode.md)) accepts only `off`, so nothing could protect an
internet-facing endpoint.

## Decision

- **The orchestrator hosts the MCP server**, with the official C# SDK (`ModelContextProtocol.AspNetCore`),
  over Streamable HTTP and stateless, so proxies and tunnels need no session affinity. It is off
  unless `RIOT2_MCP_ENABLED=true`. The Run LLM tools and the MCP tools share one core (`RiotTools`);
  every command still goes through the command outbox.
- **Two listeners, one tool set.** `/mcp` on the API port follows the security mode like the REST
  API. With `RIOT2_MCP_AUTH`, a **remote listener** on its own port (`RIOT2_MCP_REMOTE_PORT`, default
  8090) serves only `/mcp` and its OAuth metadata, and **always requires a valid token, whatever the
  security mode**. This is a scoped exception to ADR 0004's single switch: it covers no other endpoint.
  The port, not the `Host` header, decides which listener a request is on.
- **The orchestrator is an OAuth resource server, never an authorization server.** Two profiles:
  `cloudflare-access` validates the JWT Cloudflare Access sends in `Cf-Access-Jwt-Assertion`
  (Access's Managed OAuth runs the flow and dynamic client registration with the assistant);
  `oidc` validates bearer JWTs of any issuer and serves the protected resource metadata (RFC 9728).
- **Remote access goes through a tunnel**, not port forwarding: `deploy/compose.mcp-cloudflare.yml`
  runs `cloudflared` against the remote port only. ADR 0002's "no port forwarding" stays: the REST
  API, the UI and MQTT are never published.
- **Least privilege.** Tools are in groups (`read`, `health`, `commands`, `variables`, `workflows`,
  `workflowControl`, `admin`), each needing the Viewer, Operator or Admin role. A new installation
  only reads. `send_command` sends only the commands the UI allows, and writes are limited per minute.
  Remote callers get at most `RIOT2_MCP_REMOTE_MAX_ROLE` (default operator); token scopes or roles can
  only lower it, and `RIOT2_MCP_ALLOWED_SUBJECTS` can restrict who connects. The tool policy is the
  stored `McpConfiguration`, changed on the UI's *AI access* page, which also switches either listener
  off at once. No tool deletes anything or touches security, backups, LLM keys, Matter or the policy;
  device parameters are always redacted.
- Every tool call is logged with its caller, counted (`riot2.mcp.tool_calls`) and kept in memory for
  the AI access page.

## Consequences

- Assistants on the LAN can use RIoT2 with one setting; internet access needs a Cloudflare account
  (or another OAuth issuer and a tunnel or reverse proxy) and the orchestrator's MCP port only.
- An assistant acts on a real home: device names and values reach a model as untrusted text, so the
  allowlist, the roles and the rate limit hold whatever the model asks for.
- The orchestrator takes a second port when remote access is on. Explicit Kestrel endpoints would
  replace `ASPNETCORE_HTTP_PORTS`, so the port is added to the configured URLs instead.
- When the security mode's `api` feature arrives (S1), the local `/mcp` gets its login with the rest
  of the API; the remote listener keeps its own token validation.

## Alternatives considered

- **A separate MCP gateway service calling the REST API.** Rejected: one more container, and it would
  need the API's trust or keys while adding nothing the orchestrator lacks.
- **An authorization server in the orchestrator.** Rejected: user management, consent and client
  registration are a large attack surface; established issuers already do them.
- **The gateway terminates auth and the orchestrator trusts a shared key.** Rejected: anything that
  reached the port with the key would be trusted; validating the signed token at the origin is the
  defence Cloudflare itself requires for Managed OAuth.
- **Port forwarding or exposing `/mcp` on the API port.** Rejected by ADR 0002: the API port is
  anonymous.
