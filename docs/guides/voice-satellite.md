# Voice satellites: talk to RIoT2 through an Amazon Echo

Applies to: the Voice satellite device (`VoiceSatellite`) of RIoT2.Net.Devices 3.1.0, the `voice-assistant.json`
workflow template, and `deploy/compose.voice.yml`. It works with any Wyoming voice satellite. This guide uses an
Amazon Echo Dot 2nd gen (model RS03QR) running [echo-dot-assist](https://github.com/Gamer92000/echo-dot-assist),
which replaces Alexa with a local daemon (hassmic) and keeps Amazon's microphones and wake word engine. The design is
[ADR 0022](../adr/0022-voice-satellites.md).

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
4. Switch hassmic to Wyoming. With adb over USB (or `scripts/adb-wifi.sh <echo-ip>`), set `PROTO=wyoming` in
   `/data/local/hassmic/hassmic.conf`, then reboot the Echo:

   ```powershell
   adb shell "sed -i 's/^PROTO=.*/PROTO=wyoming/' /data/local/hassmic/hassmic.conf; grep PROTO /data/local/hassmic/hassmic.conf"
   adb reboot
   ```

   The Echo now listens on TCP port 16700.
5. **Choose the wake word** on the Echo's own settings page, `http://<echo-ip>:28931/` (press the action button to let
   your browser in), under **Wake word**:
   - **Amazon's** engine (the default) hears best. "Alexa" comes with the firmware; "Echo", "Computer" and others
     come from **Download from Amazon**.
   - **microWakeWord** offers "Okay Nabu", "Hey Jarvis", "Hey Mycroft" or your own model, but hears worse.
   - Don't choose Home Assistant's engine: RIoT2 doesn't run a wake word engine, and the device ignores those
     requests (it logs a warning).

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
| `port` | `16700` | hassmic's Wyoming port |
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

- **`state` stays `offline`:** check that the node reaches `<echo-ip>:16700` and that `PROTO=wyoming` is set. The
  Echo's log is on its settings page (**System** → **Log**); `client connected` means the node is connected.
- **The wake word does nothing:** the ring shows the error animation when nothing is connected. Check `state`.
- **The request ends too early, or never:** lower `speechThresholdDb` (for example `-55`) if quiet speech is cut off;
  raise it, or shorten `silenceMs`, if a noisy room keeps requests open. `maxRequestSeconds` always ends them.
- **The ring spins and then goes dark:** no `speak` came within `replyTimeoutSeconds`. Check the workflow's runs and
  the **AI models** page's usage.
- **Wrong words:** use a larger Whisper model, and check that `language` matches what you speak.

## Limitations

- In Wyoming mode the Echo's light ring, buttons, volume, timers and multi-Echo arbitration aren't RIoT2 values, and
  with several Echos every one that hears the wake word answers. The ESPHome API (increment I63) will add them.
- `speak` without an open request plays as an announcement; whether hassmic plays speech while idle in Wyoming mode
  hasn't been tried on an Echo yet.
- The link to the Echo is plain TCP, like all traffic on the isolated network ([ADR 0002](../adr/0002-isolated-network-security-model.md)).
- The end of a request is found by its level, so loud speech near the Echo (a TV) can keep it open until
  `maxRequestSeconds`.
