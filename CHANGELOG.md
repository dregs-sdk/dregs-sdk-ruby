# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - Unreleased

The first stable release. It catches the SDK up with the public API: groups, the rest of the identity
reads and writes, events, devices, and escalations, with paging throughout. Nothing from 0.1.0 changes,
so upgrading needs no code changes.

### Added

- `groups:` on `track`: the organizations, teams, workspaces, or other groups the user is acting in,
  each with an `id`, an optional `type` (`"organization"` by default), and optional `data`. Dregs makes
  the identity a member of each.
- `client.groups`: `list`, `list_all`, `get`, `create`, `update`, `add_member`, and `remove_member`.
- `identities.list`, `list_all`, `update` (to disregard an identity or merge attributes), `history`,
  `links`, `reviews`, and `review`, and a `cycle_id:` on `analysis` for a past cycle.
- `client.events`: `list`, `list_all`, and `get`, with the groups each event was sent with.
- `client.devices`: `list`, `list_all`, `get`, and `update` to disregard a device.
- `client.escalations`: `list`, `list_all`, `get`, `update` to move an escalation along, and `summary`.
- `Dregs::Page`, an `Enumerable` page of items with its position and totals, and a `list_all` on every
  namespace that walks the pages for you.

### Fixed

- An error response without a message of its own now reads as the status's reason phrase, such as
  "HTTP 404: Not Found", rather than "Request failed".

## [0.1.0] - 2026-09-22

The first release. A server-side client for tracking events and reading scores.

### Added

- `Dregs::Client`, authenticating with a credential's `sk_` secret key against a configurable base
  URL, with no runtime dependencies beyond the standard library.
- `track` for recording backend events against an identity, always sending an idempotency `id` so a
  retry cannot double-count.
- `identities.get`, `identities.scores`, `identities.analysis`, and `identities.analyze`.
- Typed errors for 400, 401, 402, 403, 404, 429, and 5xx, plus connection and timeout failures, all
  deriving from `Dregs::Error`.
- Automatic retries with exponential backoff and jitter, honouring `Retry-After`.
- `Dregs::Webhooks.verify` for checking a webhook's signature and rejecting replays.
- Lenient models with a `raw` escape hatch, and RBS signatures in `sig/`.

[1.0.0]: https://github.com/dregs-sdk/dregs-sdk-ruby/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/dregs-sdk/dregs-sdk-ruby/releases/tag/v0.1.0
