## What this changes

<!-- A sentence or two. If it changes the public surface, say so plainly: this SDK is a port of
     the reference Python one, and the TypeScript, Java, and PHP ports share its shape. -->

## Checklist

- [ ] `bundle exec rspec` passes
- [ ] `bundle exec rubocop` passes
- [ ] `bundle exec rbs -I sig validate` passes, and `sig/dregs.rbs` covers any new public method
- [ ] New behavior has a test, or the fix has one that failed before it
- [ ] `Gemfile.lock` is committed, if dependencies changed
- [ ] `CHANGELOG.md` has an entry under Unreleased, for anything user-visible
