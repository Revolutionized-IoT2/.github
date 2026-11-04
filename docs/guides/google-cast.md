# Google Cast speakers: voice announcements

Applies to: the Google Cast speaker device (`GoogleCast`) of RIoT2.Net.Devices 3.0.0. It works with Google Home,
Nest Audio, Nest Mini, Nest Hub, Chromecast, Cast-enabled speakers and speaker groups. Workflows use it to say
things such as "Sauna is ready".

The device has four commands. A workflow sends them with **RIoT Output**, or with **RIoT Command with
confirmation** when it should know whether the speaker played the message:

| Command | Value | What it does |
|---|---|---|
| `speak` (Speak) | Text, at most 1000 characters | Says the text |
| `playUrl` (Play media URL) | An http or https URL of an audio file | Plays it, for example a chime |
| `setVolume` (Set volume) | 0–100 | Sets the speaker's volume |
| `stop` (Stop playback) | `true` | Stops whatever the speaker plays |

## 1. Find the speaker's address

The node connects to the speaker's IP address. Discovery (mDNS) doesn't reach into the node's Docker network, so
the address is a parameter.

- In the Google Home app, open the speaker, then **Settings** → **Device information**. **IP address** is at the
  bottom.
- Give the speaker a fixed address (a DHCP reservation in your router), or the device loses it.
- A **speaker group** has the address of one of its speakers and a port of its own, not 8009. Find the port with
  `avahi-browse -rt _googlecast._tcp` (Linux) or `dns-sd -B _googlecast._tcp` and then `dns-sd -L "<group name>"
  _googlecast._tcp` (Windows, macOS). The port changes when the group's leader changes.

The node must reach the speaker on that port (TCP). The default compose install allows this.

## 2. Add the device

In the UI, add **Google Cast speaker** to a node from its device templates:

| Parameter | Default | Meaning |
|---|---|---|
| `ipAddress` | — | The speaker's address, from step 1 |
| `port` | `8009` | A speaker group's port, from step 1 |
| `ttsEngine` | `googleTranslate` | `googleTranslate` or `googleCloud` (step 3) |
| `language` | `en-GB` | The speech's language, for example `en-US`, `fi-FI` or `sv-SE` |
| `voice` | empty | `googleCloud`: a voice from Google's voice list, for example `en-GB-Neural2-B`; empty: Google's default voice for the language |
| `cloudTtsApiKey` | empty | `googleCloud`: the API key (secret) |
| `nodeBaseUrl` | empty | `googleCloud`: the URL the speaker downloads the speech from; empty: the node's `RIOT2_NODE_URL` |
| `announcementVolume` | empty | 0–100: the volume of `speak` and `playUrl`; empty: the speaker's current volume |
| `restoreVolume` | `true` | Set the volume back afterwards |

The device doesn't connect at start, so a speaker that is off or asleep doesn't stop the device. Each command
connects, plays and disconnects. A failed command fails with the reason. The device keeps running and shows that
reason until the next command succeeds.

## 3. Choose the speech engine

- **`googleTranslate`** needs no account and no key. The speaker downloads the speech from Google Translate
  itself, so it needs internet access. The service is unofficial and free, and Google may change or limit it. Text
  longer than 200 characters is split at sentences and spoken in parts.
- **`googleCloud`** uses [Google Cloud Text-to-Speech](https://cloud.google.com/text-to-speech), which has better
  voices. It is paid beyond a monthly free quota.
  1. In the [Google Cloud console](https://console.cloud.google.com/), create a project and enable the
     **Cloud Text-to-Speech API**.
  2. Under **APIs & Services** → **Credentials**, create an API key and restrict it to that API.
  3. Enter the key in `cloudTtsApiKey`.

  The node asks Google for the speech and keeps it in memory for an hour. The speaker then downloads it from the
  node at `<nodeBaseUrl>/api/cast/audio/<token>`, so the speaker must reach the node: with the compose install,
  `RIOT2_NODE_URL` is `http://<host>:8081`, and that is the default. Set `nodeBaseUrl` only when the speaker reaches
  the node at another address. `localhost` doesn't work, because it is the speaker itself.

## 4. Announce from a workflow

Example: say "Sauna is ready" when the sauna reaches 80 °C.

1. On the UI's **Workflows** page, import the template `sauna-ready-announcement.json` from
   [RIoT2.Elsa/templates](https://github.com/Revolutionized-IoT2/RIoT2.Elsa/tree/master/templates)
   ([automation.md](automation.md#templates)).
2. In **SaunaTemperature**, choose the sauna's temperature report. In **SaySaunaReady**, choose the speaker's
   **Speak** command. Its value is the script `return 'Sauna is ready';`.
3. Adjust the limits in **SaunaReady**: the announcement comes when the temperature rises above `Upper` (80). It
   comes again only after the temperature has fallen below `Lower` (60). Then **Publish**.

To build it yourself: **RIoT Trigger** (the temperature report) → **RIoT Threshold** (`Upper` 80, `Lower` 60) →
from `Above`, **RIoT Output** with the Speak command. A Threshold starts `unknown` after Elsa restarts, so a sauna
that is already hot is announced once more.

The Output's value is a JavaScript expression that returns the text, so a workflow can build the text from earlier
steps.

## Limitations

- An announcement replaces what the speaker plays (music, radio). Afterwards the speaker is idle. Cast can't resume
  another app's playback.
- Announcements to one speaker play one after another. A command waits at most 60 s for the media to end. Longer
  media keeps playing; the volume is set back after those 60 s.
- `stop` stops any app the speaker runs, not only the device's announcements.
- A Nest Hub shows the Default Media Receiver while it speaks.
