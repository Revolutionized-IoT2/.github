# Remote AI access (MCP)

Applies to: people who want AI assistants (Claude, ChatGPT, VS Code, other MCP clients) to read and
control RIoT2. Orchestrator 1.22.0 and UI 1.12.0 or later. The decision is
[ADR 0018](../adr/0018-mcp-server-and-remote-ai-access.md); the routes and tools are in
[mcp.md](../contracts/mcp.md), the variables in
[env-vars.md](../contracts/env-vars.md#orchestrator).

The orchestrator is an MCP server. Assistants list the home's values, read them, send the commands
you allow and look at workflows and node health. On the LAN they use `/mcp` on the orchestrator's
port. From the internet, ChatGPT and Claude reach a second port through a Cloudflare Tunnel, and
Cloudflare Access signs you in first.

## What assistants may do

Open the UI's **AI access** page (under Automation):

- **Tools**: the groups an assistant gets. A new installation only reads (values, health,
  workflows). *Commands*, *Variables* and *Workflow control* need the Operator role, *Configuration*
  the Admin role.
- **Commands**: `send_command` sends only the commands you pick here, and every command goes
  through the delivery queue. **Writes per minute** limits commands, variable changes and
  configuration writes of all assistants together.
- **On this network** and **From the internet** switch either listener off at once, without a
  restart.
- **Activity** shows every tool call since the orchestrator started: who, which tool, on what, and
  the result. Calls are logged as `RIoT2.Mcp` and counted in `riot2_mcp_tool_calls_total`.

No tool deletes anything, and none reaches security, backups, language model keys, Matter or these
settings. Device parameters are always shown as `[redacted]`.

## On the LAN

1. In `deploy/.env`, set `RIOT2_MCP_ENABLED=true`, then `docker compose up -d --wait`.
2. The AI access page shows the URL, `http://<host>:8080/mcp`. Add it to a client as an HTTP
   (streamable) MCP server, for example:
   - VS Code, `.vscode/mcp.json`: `{ "servers": { "riot2": { "type": "http", "url": "http://<host>:8080/mcp" } } }`
   - Claude Code: `claude mcp add --transport http riot2 http://<host>:8080/mcp`

While the security mode is off, `/mcp` is as open as the REST API: anyone on the network can use
the tools you enabled.

## From the internet with Cloudflare

You need a domain on Cloudflare and a Zero Trust organization (the free plan is enough), with an
identity provider; the one-time PIN by e-mail works. Nothing is forwarded on your router: the tunnel
connects outwards.

1. **Tunnel.** In the Cloudflare dashboard, open **Zero Trust > Networks > Tunnels** and create a
   Cloudflared tunnel. Copy its token. Add a public hostname, for example `riot.<your-domain>`, with
   the service **HTTP** `orchestrator:8090`. Never use port 8080: the REST API there has no login.
2. **Access application.** Open **Zero Trust > Access controls > Applications** and add a
   self-hosted application (or an MCP server application) for the same hostname. Give it a policy
   that allows only you, for example *Emails* = your address. Under **Advanced settings**, turn on
   **Managed OAuth**, so assistants can sign in. Copy the **Application Audience (AUD) tag**.
3. **Settings.** In `deploy/.env`:

   ```
   CLOUDFLARE_TUNNEL_TOKEN=<tunnel-token>
   RIOT2_MCP_PUBLIC_URL=https://riot.<your-domain>/mcp
   RIOT2_MCP_CF_TEAM_DOMAIN=<team>.cloudflareaccess.com
   RIOT2_MCP_AUTH_AUDIENCE=<aud-tag>
   RIOT2_MCP_REMOTE_MAX_ROLE=operator
   RIOT2_MCP_ALLOWED_SUBJECTS=<your-e-mail>
   ```

   The team domain is under **Zero Trust > Settings**. `RIOT2_MCP_ALLOWED_SUBJECTS` repeats the
   Access policy in the orchestrator; leave it empty to rely on the policy alone.
4. **Start** with the overlay:

   ```powershell
   docker compose -f docker-compose.yml -f compose.mcp-cloudflare.yml up -d --wait
   ```

   The AI access page now shows the public URL and **From the internet** as *Cloudflare Access*.
5. **Connect an assistant** with the public URL, then sign in on Cloudflare's page when it opens:
   - **Claude** (claude.ai or Claude Desktop): *Settings > Connectors > Add custom connector*.
   - **ChatGPT**: turn on developer mode under *Settings > Apps & Connectors > Advanced*, then create
     a connector with the URL and OAuth authentication. Write tools such as `send_command` need
     developer mode.

   The menus of both apps change often; look for "custom connector" or "MCP server".

The orchestrator checks Cloudflare's signed token on every request, with the team's keys and the AUD
tag, so a request that didn't pass Access is refused even if it reaches the port.

### Roles

A remote assistant gets `RIOT2_MCP_REMOTE_MAX_ROLE`: `viewer` (read only), `operator` (default:
commands, variables, cancelling runs) or `admin` (also the configuration tools). Configuration over
the internet needs both `admin` here and the *Configuration* group on the AI access page.

## With another OAuth issuer

Any OAuth 2.1 / OpenID Connect issuer (Auth0, Keycloak, Microsoft Entra ID) works with
`RIOT2_MCP_AUTH=oidc`: set `RIOT2_MCP_AUTH_AUTHORITY` to the issuer's https URL and
`RIOT2_MCP_AUTH_AUDIENCE` to the audience it puts in tokens for RIoT2, and publish port 8090 through
your own tunnel or https reverse proxy. The listener answers `401` with
`WWW-Authenticate: Bearer resource_metadata="…"` and serves the protected resource metadata at
`/.well-known/oauth-protected-resource/mcp`, which points clients at the issuer. The issuer must let
the assistant register (dynamic client registration or client ID metadata documents). Scopes
`riot2.read`, `riot2.operate` and `riot2.admin`, or roles `Viewer`, `Operator` and `Admin`, lower the
role a token gets.

## Troubleshooting

| Symptom | Check |
|---|---|
| The orchestrator doesn't start | Its log lists every `RIOT2_MCP_*` problem at once: a profile needs `RIOT2_MCP_ENABLED=true`, an https public URL, the audience and the team domain (or authority). |
| The assistant gets 401 after signing in | The AUD tag and team domain must be the Access application's; the tunnel must point at port 8090; `RIOT2_MCP_ALLOWED_SUBJECTS` must contain your sign-in address. `riot2_mcp_auth_failures_total` counts refusals by reason. |
| The assistant sees no tools, or not the ones you expect | The groups on the AI access page, the listener switches, and the role: a remote caller gets no tool above `RIOT2_MCP_REMOTE_MAX_ROLE`. |
| `send_command` answers "not allowed" | Pick the command under **Commands** on the AI access page. |
| `send_command` answers `expired` | The node is offline or didn't answer in time; see the System page. |

## Security notes

- Keep the tunnel on port 8090 only. Port 8090 serves `/mcp` and its metadata and nothing else.
- An assistant acts on a real home, and what devices report reaches a model as text. Allow only the
  commands you'd let a guest use, keep the rate low, and read the activity now and then.
- To cut internet access off at once, switch **From the internet** off on the AI access page, or stop
  the `cloudflared` service.
