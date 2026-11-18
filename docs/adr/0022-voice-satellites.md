# 0022. Voice satellites: the speech pipeline in the node, answers from workflows

- Status: Accepted
- Date: 2026-11-18
- Applies to: RIoT2.Net.Devices, RIoT2.Elsa, deploy/

## Context

Old Amazon Echos can run [echo-dot-assist](https://github.com/Gamer92000/echo-dot-assist), whose daemon (hassmic)
keeps Amazon's microphone processing and wake word engine and replaces Alexa with a local voice satellite. hassmic
speaks two protocols that Home Assistant understands:

- **Wyoming** (TCP 16700): small JSON-lines events with binary audio. Voice, wake word, buttons and the light ring
  work on the Echo; timers, announcements, arbitration between several Echos and settings as entities don't. The link
  is plain TCP.
- **ESPHome native API** (TCP 26053, the default): protobuf messages, encrypted with a key Home Assistant sets
  (Noise). Everything works, but the protocol is much larger.

RIoT2 has the parts for an assistant: Run LLM with tools that read values and send commands
([ADR 0016](0016-integrated-workflows-and-llm.md)), and text to speech in the Google Cast speaker device. It has no
speech to text, and nothing speaks Wyoming or the ESPHome API.

## Decision

- **A device, not a service.** The Voice satellite device (`VoiceSatellite`, RIoT2.Net.Devices) connects to the
  satellite and runs the pipeline in the node: it finds the end of the request, runs speech to text, and runs text
  to speech for the answer. No Core, MQTT or orchestrator change.
- **Audio stays out of MQTT.** Only text crosses the bus: the `transcript` report and the `speak` command. A
  `state` report shows the satellite's phase.
- **Workflows answer.** A workflow triggered by `transcript` decides the answer (the `voice-assistant.json` template:
  Run LLM with `ReadValues` and `SendCommands`) and sends it to `speak`. A request without an answer in
  `replyTimeoutSeconds` ends quietly. The device doesn't call a model itself.
- **Wyoming first, the ESPHome API later.** I62 implements the Wyoming client. I63 adds the ESPHome API to the same
  device with the same report and command ids, for the light ring, buttons, volume, timers, announcements and
  arbitration, so workflows survive the switch.
- **Pluggable engines.** Speech to text from a Wyoming server (wyoming-faster-whisper) or an OpenAI-compatible
  `/audio/transcriptions`; text to speech from a Wyoming server (wyoming-piper), an OpenAI-compatible
  `/audio/speech` or Google Cloud. `deploy/compose.voice.yml` runs the local Wyoming servers.
- **The end of speech by level.** A managed detector (frame level against an adaptive noise floor and a threshold)
  keeps the plugin free of native code, so it runs on x64 and ARM64 nodes alike.
- **The wake word stays on the satellite.** It is chosen on the Echo's own settings page (Amazon's engine or
  microWakeWord). RIoT2 runs no wake word engine and ignores requests that ask for one.

## Consequences

- An Echo becomes a local voice assistant for RIoT2 without Home Assistant or Amazon's cloud. With local engines,
  no audio leaves the network.
- The answer takes one more hop (report, workflow, command) than an assistant built into the device; the model's
  time dominates anyway.
- Until I63, several Echos that hear the same wake word all answer, and the Echo's controls aren't RIoT2 values.
- The Wyoming link is unencrypted, as the rest of the isolated network is ([ADR 0002](0002-isolated-network-security-model.md)).
- The level-based detector can end requests early or late in loud rooms; its threshold and pause are parameters.

### Update for I63 (2026-11-18)

- Over the ESPHome API the device takes Home Assistant's place as the client. It sets the satellite's encryption key
  itself (its `encryptionKey`, given over a link with the all-zero key, as Home Assistant does); a satellite that
  already has another key must be released first.
- hassmic doesn't take the reply over the API: it fetches it over HTTP. The node serves it at
  `GET /api/voice/audio/{token}` (anonymous, a random token kept an hour), so the satellite must reach the node.
- Arbitration between Echos is hassmic's own (UDP, a key paired with the buttons); RIoT2 relays nothing. A node runs
  one device of each type, so each Echo has a node of its own.
- X25519 and ChaCha20-Poly1305 come from BouncyCastle: .NET has no X25519, and its ChaCha20-Poly1305 depends on the
  operating system.

## Alternatives considered

- **Through Home Assistant.** The Echo goes to Assist, and the Home Assistant connector gives Assist the RIoT2
  devices. No code, but it requires Home Assistant, and RIoT2's workflows and models don't answer.
- **Audio over MQTT to a separate voice service.** Rejected: audio would load the broker and every subscriber, and a
  second service would need its own deployment for what fits in a device.
- **The device calls Run LLM itself.** Rejected for now: a workflow is easier to change and to combine with other
  steps, and the device would need the orchestrator's API.
- **The ESPHome API first.** Rejected for the first increment: it needs Noise encryption and a protobuf schema before
  anything works; Wyoming proves the pipeline first.
