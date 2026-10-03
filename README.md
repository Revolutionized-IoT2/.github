# .github

Organization-level files for [Revolutionized-IoT2](https://github.com/Revolutionized-IoT2), and
the platform documentation hub.

- [docs/README.md](docs/README.md): the platform documentation index. It covers guides (install,
  configure, operate), architecture, contracts (MQTT, HTTP/gRPC, environment variables,
  configuration) and architecture decision records.
- [AGENTS.md](AGENTS.md): the workspace guide for AI coding agents. It has a repository map,
  build/test commands and platform-wide rules.
- [profile/README.md](profile/README.md): the organization landing page. It has the platform summary,
  the repository map, and links to the guides and documentation.
- [ROADMAP.md](ROADMAP.md): the order of upcoming work, linking to the backlog, plans and designs.
- [tools/ui-screenshots](tools/ui-screenshots/README.md): regenerates the UI screenshots used by
  the guides.
- [tools/docs-check](tools/docs-check/README.md): the documentation drift check (links, layout,
  secrets, and contracts against code). CI runs it on hub changes and weekly.
- [build](build/README.md): the shared `Directory.Build.props`, `.editorconfig` and central
  package template that every .NET repository copies.
- [PLATFORM-REVIEW.md](PLATFORM-REVIEW.md): a redirect. The September 2026 review was split into
  `docs/` on 2026-10-03, and this file maps its old sections and IDs to their new locations.
