# Dregs Ruby SDK

[![Gem](https://img.shields.io/gem/v/dregs.svg)](https://rubygems.org/gems/dregs)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.1-CC342D.svg)](https://www.ruby-lang.org/)
[![License](https://img.shields.io/github/license/dregs-sdk/dregs-sdk-ruby.svg)](LICENSE)

The official Ruby client for [Dregs](https://dregs.com), which scores the users of your application
for fraud and abuse across four categories: humanity, authenticity, uniqueness, and behavior.

Send events from your backend, read back the scores and the observations behind them.

```bash
bundle add dregs
```

The gem has no runtime dependencies: it uses `net/http`, `json`, and `openssl` from the standard
library, so adding it cannot conflict with the HTTP client your application already has.

## Getting started

You need the **secret key** from an API credential, which you will find under **Settings → Credentials**
in the Dregs dashboard. It starts with `sk_`. The `pk_` public key is for the browser tracker and cannot
read identities or scores.

```ruby
require "dregs"

client = Dregs::Client.new(secret_key: ENV.fetch("DREGS_SECRET_KEY"))
```

The key is read from `DREGS_SECRET_KEY` when you do not pass one, so `Dregs::Client.new` on its own is
usually enough. Build one at startup and keep it; the client holds no per-request state, so it is safe
to share across threads.

## Tracking events

```ruby
client.track(
  "user.signup",
  identity: "user_12345",
  data: { plan: "pro", referrer: "partner-x" },
  identity_data: { email: "ada@example.com", name: "Ada Lovelace" }
)
```

`identity:` is your own id for the user — the same one you pass to `dregs.identify()` in the browser
tracker, and the one you look scores up by. It is required: a server-side event carries no device
signature, so the identity is the only thing tying the event to a user.

`identity_data:` carries attributes of the *user* rather than the event. The analyzers lean on these
heavily, so send them whenever you have them. Name the keys the way your application already does and
map them to Dregs's canonical fields under **Settings → Mappings**; the same goes for event names.

### Idempotency

Every event is sent with an `id`, which makes ingestion idempotent: reposting the same id returns the
original event instead of recording a second one. Pass the id your application already has, and a retry
after a timeout can never double-count.

```ruby
client.track("purchase", identity: "user_12345", event_id: "order-#{order.id}")
```

When you omit it the SDK generates one, which is what makes its own retries safe.

### What comes back

```ruby
result = client.track("user.signup", identity: "user_12345")

result.accepted?  # true when Dregs recorded the event
result.id         # the event's id
```

`accepted?` is `false` for the handful of rejections Dregs answers quietly rather than naming the check
that failed. Failures that are yours to act on raise instead — see [Errors](#errors).

## Reading scores

```ruby
scores = client.identities.scores("user_12345")

scores.humanity      # 85
scores.authenticity  # 72
scores.uniqueness    # 91
scores.behavior      # 68
```

This is the cheap read and the one most integrations want. A category Dregs has not scored yet reads as
`nil`, and a brand-new identity comes back empty. `Scores` is `Enumerable`, so you can map and sort it.

Scoring is **asynchronous**. Scores appear moments after the events that move them, not in the same
breath, so read them at a decision point rather than immediately after a `track` call.

```ruby
hold_for_review("user_12345") if scores.authenticity && scores.authenticity < 40
```

### Seeing exactly why

The scores are the summary; the observations are the evidence. When you need to show or log *why* an
identity scored the way it did, ask for the analysis.

```ruby
analysis = client.identities.analysis("user_12345")

analysis.observations.each do |observation|
  puts "#{observation.label}: #{observation.explanation} (value #{observation.value})"
end
```

Each observation carries the analyzer that produced it, a `value` from 0.0 (suspicious) to 1.0
(legitimate), a `confidence`, a `weight`, and the counts behind the finding in `metadata`. `analysis`
raises `Dregs::NotFoundError` until the identity has been analyzed at least once.

### The whole identity

```ruby
identity = client.identities.get("user_12345")

identity.display_email   # "ada@example.com"
identity.humanity_score  # 85
identity.badges          # [#<Dregs::Badge name="Account Takeover Suspected" ...>]
identity.data            # every attribute you have sent
```

### Forcing a rescore

```ruby
client.identities.analyze("user_12345")
```

This queues the work and returns; it does not wait for the cycle to finish. Dregs rescores on its own
as events arrive, so you rarely need this outside of a support or backfill flow.

## Errors

```ruby
begin
  client.track("user.signup", identity: "user_12345")
rescue Dregs::QuotaExceededError
  # over the monthly event limit; the event was not queued
rescue Dregs::RateLimitError => e
  # ingesting too fast; e.retry_after when the server said how long
rescue Dregs::Error => e
  # anything else this library raises
end
```

| Exception | When |
| --- | --- |
| `Dregs::BadRequestError` | 400, the event was malformed |
| `Dregs::AuthenticationError` | 401, the secret key was not recognized |
| `Dregs::QuotaExceededError` | 402, the account is over its monthly event limit |
| `Dregs::PermissionDeniedError` | 403, the credential may not do this |
| `Dregs::NotFoundError` | 404, no such identity, or it has not been analyzed |
| `Dregs::RateLimitError` | 429, too many requests |
| `Dregs::ServerError` | 5xx |
| `Dregs::TimeoutError` | the request timed out |
| `Dregs::ConnectionError` | the request never reached Dregs |

All of them derive from `Dregs::Error`. Those that reached the API also derive from `Dregs::APIError`
and carry `status_code`, `body`, and `request_id`. A mistake in how you called the SDK — a missing
secret key, an event id the API would refuse — raises `ArgumentError` before anything leaves the
process.

### Retries

Connection failures, timeouts, 429s, and 5xx are retried automatically with exponential backoff and
jitter, honouring `Retry-After` when the server sends one. Two retries by default:

```ruby
client = Dregs::Client.new(max_retries: 5)  # or 0 to handle it yourself
```

## Concurrency

The client is synchronous: every call blocks until Dregs answers or the retries run out. Ruby has no
idiomatic async twin to offer, so there is one client rather than two.

It holds no connection state between calls, which makes it safe to share across threads and to call
from a background job. If you do not want a signup to wait on an HTTP round trip, put the `track` call
in Sidekiq, Active Job, or a thread pool rather than reaching for a different client.

## Webhooks

Dregs signs every webhook with the channel's signing secret. Verify it against the **raw request body**
before acting on the payload — a re-serialized hash will not match, because key order and whitespace
change.

```ruby
post "/webhooks/dregs" do
  event = Dregs::Webhooks.verify(
    payload: request.body.read,
    signature: request.env["HTTP_X_DREGS_SIGNATURE"],
    secret: ENV.fetch("DREGS_WEBHOOK_SECRET")
  )

  handle(event)
rescue Dregs::WebhookVerificationError
  halt 400
end
```

In Rails the raw body is `request.raw_post`; in Rack it is `request.body.read`, and you may need to
`rewind` the body if something downstream reads it again. Do not use `params` — by the time Rails has
parsed and merged them, the bytes that were signed are gone.

`verify` also rejects payloads older than five minutes as replays; pass `tolerance: nil` to skip that if
you are deduplicating on the event id yourself. The signing secret is shown once, when you create the
webhook channel, and is not your API secret key.

## Configuration

```ruby
client = Dregs::Client.new(
  secret_key: nil,  # defaults to $DREGS_SECRET_KEY
  base_url: nil,    # defaults to $DREGS_BASE_URL, then https://dregs.com/api
  timeout: 10,      # seconds, for connecting and for reading
  max_retries: 2
)
```

## Type signatures

The gem ships RBS signatures in `sig/`, so Steep, RBS, and editors that read them see the full surface
without stubs. Responses are plain objects with readers; each one also keeps the body it was built from
in `raw`, so a field Dregs adds after this release is reachable without waiting for an SDK upgrade.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The short version:

```bash
bundle install
bundle exec rake        # rubocop, rbs validate, and rspec
```

## Links

- [Dregs manual](https://dregs.com/manual/) and [REST API reference](https://dregs.com/manual/api/)
- [Dregs MCP server](https://github.com/dregs-sdk/dregs-mcp), for connecting AI agents to your data
- [Security policy](SECURITY.md)

## License

MIT. See [LICENSE](LICENSE).
