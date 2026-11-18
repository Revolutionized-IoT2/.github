# Voice satellites: talk to RIoT2 through an Amazon Echo

Applies to: the Voice satellite device (`VoiceSatellite`) of RIoT2.Net.Devices 3.1.0, the `voice-assistant.json`
workflow template, and `deploy/compose.voice.yml`. It works with any Wyoming voice satellite, and with hassmic over
the ESPHome native API. This guide uses an Amazon Echo Dot 2nd gen (model RS03QR) running
[echo-dot-assist](https://github.com/Gamer92000/echo-dot-assist), which replaces Alexa with a local daemon (hassmic)
and keeps Amazon's microphones and wake word engine. The design is [ADR 0022](../adr/0022-voice-satellites.md).

How a request flows:

1. The Echo hears its wake word ("Alexa") and streams the request to the node.
2. The node finds where you stopped speaking and turns the audio into text (speech to text).
3. The device reports the text as `transcript`. A workflow (Run LLM) answers it, and may read values and send
   commands on the way.
4. The workflow sends the answer to the device's `speak` command. The node turns it into speech (text to speech) and
   the Echo plays it.

Audio never goes over MQTT: only the text does.

## 1. Prepare the Echo

> **Warning:** the unlock writes the Echo's bootloader and system partition and can brick it. echo-dot-assist is
> unaudited. Read what you run.

1. Keep the Echo offline (no Wi-Fi, no Amazon registration) until the step below is done.
2. Follow echo-dot-assist's page for your model: [Echo Dot 2nd gen (`biscuit`)](https://github.com/Gamer92000/echo-dot-assist/blob/main/devices/biscuit/README.md).
   - The unlock connects over micro-USB, with no soldering. You must do it by hand from the XDA thread that page links
     to (the unlock's author asks that it never runs from a script). It needs a Linux PC or a Linux live USB stick.
   - Then `scripts/setup.sh biscuit` flashes the pinned Fire OS 6574.1, installs hassmic and joins your Wi-Fi.
   - Back up `secrets/update.key`; it signs the Echo's updates.
3. Give the Echo a fixed address (a DHCP reservation in your router).
4. Choose the protocol (the device's `protocol` parameter):
   - **ESPHome** (`esphome`, hassmic's default, recommended): TCP port 26053, encrypted, and the Echo's volume,
     microphone mute, do not disturb, light ring, buttons, wake word and timers become reports and commands. Several
     Echos decide among themselves which one answers. Nothing to change on the Echo. If Home Assistant adopted it,
     delete it there first: Home Assistant gave it an encryption key of its own.
   - **Wyoming** (`wyoming`): plain TCP port 16700, voice only. With adb over USB (or `scripts/adb-wifi.sh <echo-ip>`),
     set `PROTO=wyoming` in `/data/local/hassmic/hassmic.conf`, then reboot the Echo:

     ```powershell
     adb shell "sed -i 's/^PROTO=.*/PROTO=wyoming/' /data/local/hassmic/hassmic.conf; grep PROTO /data/local/hassmic/hassmic.conf"
     adb reboot
     ```

5. **Choose the wake word** on the Echo's own settings page, `http://<echo-ip>:28931/` (press the action button to let
   your browser in), under **Wake word**:
   - **Amazon's** engine (the default) hears best. "Alexa" comes with the firmware; "Echo", "Computer" and others
     come from **Download from Amazon**.
   - **microWakeWord** offers "Okay Nabu", "Hey Jarvis", "Hey Mycroft" or your own model, but hears worse.
   - Don't choose Home Assistant's engine: RIoT2 doesn't run a wake word engine, and the device refuses those
     requests (it logs a warning).

   With `esphome`, the device's `wakeWord` command picks one of the installed wake words too.

## 2. Run speech to text and text to speech

Choose an engine for each direction in the device's parameters (step 3).

- **Local, with `compose.voice.yml`** (recommended: no audio leaves your network). It runs wyoming-faster-whisper
  on port 10300 and wyoming-piper on port 10200:

  ```powershell
  cd deploy
  docker compose -f docker-compose.yml -f compose.voice.yml up -d
  ```

  Run it on the strongest machine you have (the NAS), not on a Raspberry Pi: Whisper is CPU-heavy. A node on another
  host reaches it through the published ports. Set the variables in `.env` ([env-vars.md](../contracts/env-vars.md#compose-install-deploy)):

  | Language | `RIOT2_WHISPER_MODEL` | Piper voice (`ttsVoice`) |
  |---|---|---|
  | Finnish (`fi-FI`) | `medium-int8` (smaller models make many mistakes in Finnish) | `fi_FI-harri-medium` |
  | English, US (`en-US`) | `small-int8` (the default) | `en_US-lessac-medium` |
  | English, UK (`en-GB`) | `small-int8` | `en_GB-alan-medium` |

  The first start downloads the model, and the first request with a new voice downloads the voice.
- **OpenAI-compatible** (`openAiCompatible`): OpenAI itself, or a local server with the same API, such as Speaches
  or LocalAI. Speech to text posts the request to `<url>/audio/transcriptions`; text to speech asks
  `<url>/audio/speech` for WAV. Cloud services receive your voice and the answers.
- **Google Cloud Text-to-Speech** (`googleCloud`, text to speech only): the same API key as the Google Cast
  speaker's ([google-cast.md](google-cast.md#3-choose-the-speech-engine)), with voices such as `fi-FI-Wavenet-B`.

## 3. Add the device

In the UI, add **Voice satellite** to a node from its device templates:

| Parameter | Default | Meaning |
|---|---|---|
| `host` | — | The Echo's address |
| `protocol` | `wyoming` | `esphome` or `wyoming` (step 1) |
| `port` | empty | Empty: `26053` for `esphome`, `16700` for `wyoming` |
| `encryptionKey` | empty | `esphome`: 32 bytes in base64 (`openssl rand -base64 32`); the device gives it to an Echo without a key, then uses it. Empty: no encryption (secret) |
| `nodeBaseUrl` | the node's `RIOT2_NODE_URL` | `esphome`: the URL the Echo fetches the speech from this node at, for example `http://192.168.1.10:8081` |
| `language` | `en-US` | The language you speak: `fi-FI`, `en-US`, `en-GB`, … |
| `sttEngine` | `wyoming` | `wyoming` or `openAiCompatible` |
| `sttUrl` | — | `wyoming`: `tcp://<host>:10300`; `openAiCompatible`: the API's base URL, empty for `https://api.openai.com/v1` |
| `sttModel` | `whisper-1` | `openAiCompatible`: the model |
| `sttApiKey` | empty | `openAiCompatible`: the key, if the server needs one (secret) |
| `ttsEngine` | `wyoming` | `wyoming`, `openAiCompatible` or `googleCloud` |
| `ttsUrl` | — | `wyoming`: `tcp://<host>:10200`; `openAiCompatible`: as `sttUrl` |
| `ttsModel` | `tts-1` | `openAiCompatible`: the model |
| `ttsVoice` | empty | A Piper, OpenAI or Google voice (see step 2); empty: the server's default (OpenAI: `alloy`) |
| `ttsApiKey` | empty | `openAiCompatible` or `googleCloud`: the key (secret) |
| `replyTimeoutSeconds` | `30` | How long a request waits for its answer |
| `maxRequestSeconds` | `15` | The longest request |
| `silenceMs` | `700` | The pause that ends a request |
| `speechThresholdDb` | `-45` | The level under which audio never counts as speech |

The node connects to the Echo at start and again whenever the connection drops. The `state` report shows
`offline` until it is connected, then `idle`, `listening`, `thinking` and `speaking`. The device keeps running while
the Echo is unreachable and shows why.

With `esphome`, the Echo fetches each answer from the node (`GET /api/voice/audio/{token}`, kept an hour), so it
must reach `nodeBaseUrl`. These reports and commands work only with `esphome`:

| Address | Report | Command |
|---|---|---|
| `volume` | The volume, 0-100 | Sets it |
| `mute` | The microphone is muted | Mutes or unmutes it |
| `doNotDisturb` | Do not disturb is on (announcements aren't played) | Switches it |
| `light` | The light ring: `{on, brightness, color, effect}` | Sets what it names, or `true`/`false`; needs a light ring of its own on the Echo's settings page |
| `wakeWord` | The wake word in use | Picks an installed one by its id or name |
| `button` | A button event, for example `action_press` | — |
| `timerRinging` | A timer rings | — |
| `timer` | — | `{"seconds": 300, "name": "Pasta"}` starts a timer the Echo rings; `{"cancel": true, "name": "Pasta"}` cancels it, without a name all |
| `stopRinging` | — | Stops a ringing timer |

`speak` without an open request is an announcement; with do not disturb on, the command fails.

### Several Echos

A node runs one device of each type, so each Echo needs a node of its own (another node container on the same
host works). With `esphome`, Echos that hear the same wake word decide among themselves which one answers (hassmic's
wake word arbitration, on by default). They share a key for it: pair each new Echo by holding Volume up and Volume
down together for 2 s on it, then on one already in. Home Assistant's other ways to share the key don't apply.

## 4. Answer with a workflow

1. On the UI's **AI models** page, add a model connection ([automation.md](automation.md#run-llm)). A small local
   model (Ollama) answers fastest and keeps your requests at home.
2. On the **Workflows** page, import `voice-assistant.json` from
   [RIoT2.Elsa/templates](https://github.com/Revolutionized-IoT2/RIoT2.Elsa/tree/master/templates).
3. In **Request**, choose the device's **Transcript** report. In **Answer**, choose the connection and the commands
   the assistant may send (for example the living room light). In **SayAnswer** and **SaySorry**, choose the
   device's **Speak** command.
4. Keep **Answer**'s `TimeoutSeconds` (20) below the device's `replyTimeoutSeconds` (30), then **Publish**.

Say "Alexa, what is the temperature in the living room?" or "Alexa, sytytä olohuoneen valot". The model answers in
the language you spoke.

Other workflows can use the device too: a **RIoT Compare** on the transcript for fixed phrases, or the `speak`
command alone for announcements.

## Troubleshooting

- **`state` stays `offline`:** check that the node reaches the Echo's port (26053 or 16700) and that `protocol`
  matches the Echo's `PROTO`. The Echo's log is on its settings page (**System** → **Log**); `client connected` means
  the node is connected.
- **"The satellite has another encryption key":** Home Assistant (or an earlier key) set one. Delete the Echo in Home
  Assistant, or delete `/data/local/hassmic/state/api_key` and restart hassmic; the device then gives it its own.
- **"The satellite refused the encryption key it took before":** the device gives its key only once, so that nothing
  else at the Echo's address can collect it. If the Echo was reset, set a new `encryptionKey`.
- **The Echo answers nothing although `transcript` and `speak` work (`esphome`):** the Echo can't fetch the answer.
  Check that `nodeBaseUrl` is the node's LAN address and port, and the Echo's log for `media:` lines.
- **The wake word does nothing:** the ring shows the error animation when nothing is connected. Check `state`.
- **The request ends too early, or never:** lower `speechThresholdDb` (for example `-55`) if quiet speech is cut off;
  raise it, or shorten `silenceMs`, if a noisy room keeps requests open. `maxRequestSeconds` always ends them.
- **The ring spins and then goes dark:** no `speak` came within `replyTimeoutSeconds`. Check the workflow's runs and
  the **AI models** page's usage.
- **Wrong words:** use a larger Whisper model, and check that `language` matches what you speak.

## Limitations

- With `wyoming` the Echo's light ring, buttons, volume and timers aren't RIoT2 values, and with several Echos every
  one that hears the wake word answers. Whether hassmic plays `speak` while idle in Wyoming mode hasn't been tried on
  an Echo yet.
- Timers are kept in the node's memory: a node restart drops them. The Echo's Drop In, Bluetooth, music and sound
  detection aren't RIoT2 values.
- With `wyoming`, or `esphome` without `encryptionKey`, the link is plain TCP, like all traffic on the isolated
  network ([ADR 0002](../adr/0002-isolated-network-security-model.md)). The answers' URLs are anonymous: a random token
  kept for an hour is their only protection.
- The end of a request is found by its level, so loud speech near the Echo (a TV) can keep it open until
  `maxRequestSeconds`.
