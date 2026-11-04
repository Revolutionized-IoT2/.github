# Netatmo devices

Applies to: the Netatmo Security and Netatmo Weather devices of RIoT2.Net.Devices 3.0.0, on a Node built on Core 2.4.0,
with an Orchestrator and UI that connect devices to their accounts. Upgrading from the earlier devices:
[upgrading.md](upgrading.md#netatmo-devices-devices-300).

The devices use the Netatmo Connect API with your own Netatmo app. You create the app once; after that, the UI
connects each device with **Connect to Netatmo**. Security events arrive through Netatmo's webhook when the node is
reachable from the internet, and through polling otherwise.

## 1. Create a Netatmo app (once per account)

1. Sign in at [dev.netatmo.com](https://dev.netatmo.com/apps/) and create an app. Name and description are free text.
2. Set its **Redirect URI** to the one the device form shows in its Account section: the address your browser
   reaches the RIoT2 API at, plus `/api/oauth/callback`. With the compose install that is the UI's address, for
   example `http://<host>:8080/api/oauth/callback`.
3. Leave the app's webhook URL empty: the Security device registers it itself.
4. Copy the app's **client id** and **client secret**.

Netatmo allows one webhook per app. If Home Assistant or another integration already uses an app, create a
separate one for RIoT2.

> Not yet verified with every account: whether Netatmo requires the redirect URI to match the app's exactly, and
> whether it accepts an `http://` LAN address. If the sign-in page reports a redirect URI error, open the UI at the
> address you registered, or register the HTTPS address of a tunnel to the UI.

## 2. Add and connect a device

1. In the UI, add **Netatmo Security** or **Netatmo Weather** to a node from its device templates, enter `clientId`
   and `clientSecret`, and save.
2. In the device's **Account** section, select **Connect to Netatmo**. Sign in to Netatmo in the popup and allow the
   access. The popup closes, and the section shows **Connected as** your Netatmo e-mail address.
3. Add the device again from its template once it runs, to get the reports and commands of your modules.

The node exchanges the sign-in code with the app's secret and keeps the tokens in its `Data/` volume
(`netatmoAuth-<clientId>.json`); the browser never sees them. Back that volume up and keep it private.

Devices that use the same app share its connection, and one sign-in asks for the permissions of all of them:

| Device | Netatmo scopes |
|---|---|
| Netatmo Security | `read_camera access_camera write_camera read_presence access_presence write_presence read_doorbell access_doorbell read_smokedetector read_carbonmonoxidedetector` |
| Netatmo Weather | `read_station`, and `read_homecoach` with `includeHomeCoach` |

When you add a device type to an app that is already connected, connect again: the account status shows
**Expired** until the new permissions are granted.

Without the UI, the optional `token` and `refresh_token` parameters still take tokens from the token generator on
the app's page at dev.netatmo.com. Tokens the node stored win over them.

## 3. Security events through the webhook

Without a webhook, Netatmo Security polls every 5 minutes. With one, Netatmo pushes each event as it happens, and
the device polls only every 15 minutes to catch anything Netatmo didn't deliver. Pushed and polled copies of an
event are reported once.

Netatmo needs a public HTTPS address that answers quickly. The node answers a push at once and handles it
afterwards. Netatmo stops pushing to an app for 24 hours after 5 failed deliveries, so the address must stay up.

### With a Cloudflare Tunnel

A tunnel connects outwards from your network, so no port is opened. You need a domain on Cloudflare and a free
Zero Trust organization. The tunnel of [remote AI access](remote-ai-access.md) can serve both.

1. In the Cloudflare dashboard, open **Zero Trust > Networks > Tunnels**, create a Cloudflared tunnel, and copy its
   token into `CLOUDFLARE_TUNNEL_TOKEN` in `deploy/.env`.
2. Add a **public hostname**, for example `netatmo.<your-domain>`, with the path `^/api/netatmo/webhook/` and the
   service `HTTP` `node:80`. Don't put a Cloudflare Access application on this hostname: Netatmo can't sign in. The
   secret at the end of the webhook URL is the credential. Never publish the node without the path: its API is
   anonymous while the security mode is off.
3. Optionally, add a WAF rule that blocks requests to the hostname whose method isn't `POST`.
4. Start the tunnel next to the node:

   ```bash
   docker compose --profile node -f docker-compose.yml -f compose.netatmo-cloudflare.yml up -d --wait
   ```

5. Set the device's `webhookUrl` to `https://netatmo.<your-domain>` and `webhookSecret` to a random value of at least
   32 letters, digits, `-` or `_` (for example the output of `openssl rand -hex 32`), and save.

The device registers `https://netatmo.<your-domain>/api/netatmo/webhook/<secret>` with Netatmo. Its `home|webhook`
report turns true, and its state message stays empty. Trigger a motion in front of a camera to test it.

To change the secret, set a new `webhookSecret`: the device replaces its earlier URL.

### Other ways in

Publish only the path `/api/netatmo/webhook/` of the node (port 8081 by default) over HTTPS:

- **Tailscale Funnel**: no domain needed (`<machine>.<tailnet>.ts.net`).
- **ngrok**: the free plan includes one static domain.
- **A reverse proxy with a forwarded port**, for example Caddy or Traefik with Let's Encrypt.

## What the devices report

Netatmo Security, per module of the home (`homeId`, or else the home with security modules):

| Address | Value |
|---|---|
| `<module id>\|event` | `SecurityReport` of cameras (`NACamera`, `NOC`, `NPC`), the doorbell (`NDB`), door tags, the siren and smoke and CO alarms: motion, person (with a known person's name), stranger, animal, vehicle, sound, doorbell call, door opened, tag moved, smoke, CO, siren, tampering, connection lost. Filter `image` or `no-image`; the snapshot is kept in the node's memory storage (`downloadSnapshots`). |
| `<camera>\|monitoring`, `<module>\|connection` | Boolean |
| `<outdoor camera>\|floodlight` | `on`, `off` or `auto` |
| `<battery module>\|battery` | `full`, `high`, `medium`, `low` or `very_low` |
| `person\|<id>` | The named person is at home |
| `home\|webhook` | The webhook works |

Commands: `refresh`, `<camera>|monitoring` (true or false), `<outdoor camera>|floodlight`, `person|<id>` (true: home,
false: away) and `home|away`.

Netatmo Weather reports per module what it measures (`<module id>|<field>`: `Temperature`, `min_temp`, `max_temp`,
`temp_trend`, `CO2`, `Humidity`, `Noise`, `Pressure`, `AbsolutePressure`, `pressure_trend`, `Rain`, `sum_rain_1`,
`sum_rain_24`, `WindStrength`, `WindAngle`, `GustStrength`, `GustAngle`, `max_wind_str`, and `health_idx` for a Healthy
Home Coach), stamped with the measurement's time, and `<module id>|battery`, `|reachable` and `|signal`. Stations
upload about every 10 minutes; an upload already reported isn't reported again.

## Troubleshooting

| Symptom | What to do |
|---|---|
| State message "Connect the device to Netatmo in its settings." | Connect it in its Account section. |
| Account status **Expired** | Netatmo refused the tokens or a permission is missing: connect again. |
| "Another webhook (for example Home Assistant's) is registered for this Netatmo app." | Use a separate Netatmo app for RIoT2. `webhookTakeover` set to `true` replaces the other webhook, which then stops working. |
| "Netatmo refused the webhook URL" | The URL must be public HTTPS: check the tunnel's hostname and path, and `webhookUrl`. |
| "Netatmo stopped the webhook" | Deliveries failed, for example while the node or the tunnel was down. The device polls meanwhile and registers again after an hour. |
| "Netatmo limits the calls" | Netatmo's rate limit: the device waits 15 minutes. Fewer devices per app, or a webhook, need fewer calls. |
| The sign-in popup shows a Netatmo error | The redirect URI must be the one the Account section shows, and registered on the app. |

Security: the webhook route and the OAuth callback are the only anonymous parts of this setup; see
[security.md](security.md). The tokens are as sensitive as your Netatmo password.
