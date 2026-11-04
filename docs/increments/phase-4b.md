# Increments I59 and later: phase 4 (features), continued

Applies to: all repositories. Index, definition of done and rules: [README.md](README.md). Earlier phase 4
increments are in [phase-3-4.md](phase-3-4.md).

### I59. Voice announcements on Google Cast speakers (S)

- **Scope:** workflows speak on Google Home and other Cast speakers ([google-cast.md](../guides/google-cast.md)):
  - Devices: the Google Cast speaker device (`GoogleCast`, SharpCaster) with the commands `speak`, `playUrl`,
    `setVolume` and `stop`; an announcement volume that is set back afterwards; speech from Google Translate (no key)
    or Google Cloud Text-to-Speech, which the speaker downloads from the node's `GET /api/cast/audio/{token}`
    ([http-api-services.md](../contracts/http-api-services.md)).
  - Elsa: the template `sauna-ready-announcement.json` (Trigger, Threshold, Output to Speak).

  Depends on I45 (async devices with typed options) and I48 (RIoT Threshold). No Core, MQTT or configuration
  contract changes.
- **Done when:**
  - `GoogleCastTests` pass: commands, volume set back also after a failure, both speech engines, the audio cache
    and the endpoint's token check.
  - The template imports (`WorkflowTemplateTests`).
  - The maintainer's speaker says "Sauna is ready" from the published template.
- **Release order:** Devices `3.0.0` (with the Netatmo and Eufy changes already in it), then Elsa (templates only).
