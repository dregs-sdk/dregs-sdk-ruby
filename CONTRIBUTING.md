# Contributing

Thanks for helping improve the Dregs Ruby SDK.

This is a **port** of the reference SDK, [dregs-sdk-python](https://github.com/dregs-sdk/dregs-sdk-python),
which the TypeScript, Java, Ruby, and PHP clients all follow the shape of. A change to the public
surface here is a change to all five, so surface changes are worth discussing in an issue before you
write the code.

## Getting set up

You need Ruby 3.1 or newer and Bundler.

```bash
bundle install
```

Then:

```bash
bundle exec rake             # everything below, in order
bundle exec rspec            # tests
bundle exec rubocop          # lint
bundle exec rubocop -a       # lint, fixing what it safely can
bundle exec rbs -I sig validate  # check the signatures parse and resolve
```

CI runs exactly these, against the same locked versions, so a green run locally means a green run
there. Tests run on Ruby 3.1 through 3.4.

If you change a dependency in the `Gemfile` or the gemspec, commit the resulting `Gemfile.lock`
alongside it. CI installs with `BUNDLE_FROZEN=true` and fails if the two disagree.

## What we look for

- **Tests.** The suite mocks HTTP with [WebMock](https://github.com/bblimke/webmock), so tests are
  fast and hit no network. New behavior needs a test; a bug fix needs one that fails without it.
- **Signatures.** `sig/dregs.rbs` describes the public surface. A new public method belongs there.
- **Lenient parsing.** Models tolerate fields they do not recognize and keep the raw body in
  `raw`. An SDK that raises on a response it half-understands ages badly.
- **No runtime dependencies.** The gem deliberately depends on nothing but the standard library, so
  it cannot drag a conflicting HTTP or JSON gem into an application. Adding one needs a very good
  reason.

## The API this wraps

The [Dregs manual](https://dregs.com/manual/api/) is the source of truth for the REST API. If this
SDK disagrees with the manual, the manual wins; please say so in your pull request so both get
fixed.

## Reporting problems

Bugs and feature requests go to
[GitHub issues](https://github.com/dregs-sdk/dregs-sdk-ruby/issues). Security reports go to
[security@dregs.com](mailto:security@dregs.com) instead — see [SECURITY.md](SECURITY.md).
Questions about your account or the service go to [support@dregs.com](mailto:support@dregs.com).
