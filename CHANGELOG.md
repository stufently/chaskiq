# Changelog

## 2026-11-19 — CI repair, local CI

Fixed
- Ruby 3.3.5 → 3.3.14 (latest 3.3 patch) in Gemfile, .ruby-version,
  Gemfile.lock, Dockerfiles, compose and workflows: setup-ruby has no 3.3.5
  build for ubuntu-26.04 runners.
- Docker images: base `ruby:*-slim-bullseye` → `-slim-trixie` (bullseye
  security repo is gone, apt exited 100); PGDG/NodeSource/Yarn repos via
  `signed-by` keyrings instead of the removed `apt-key`; deps add libyaml-dev,
  pkg-config. Asset precompile uses a throwaway SECRET_KEY_BASE without NUL
  bytes (config/application.rb puts `[key].pack('H*')` into ENV).
- CI: postgres:14-alpine and redis:8.10-alpine services (as in compose), Node 26
  LTS for the spec JS deps, app store packages and E2E only with the upstream
  secrets; current action versions (codeql upload-sarif v4, anchore v7).
- Rubocop workflow: the exit-code check was expanded by the outer shell and
  never ran; offenses stay non-fatal, a RuboCop error fails the job.
- Push Docker Image skips its steps when Docker Hub secrets are absent.
- CI/Rubocop build scout_apm 5.3.5's C extension as C17
  (`BUNDLE_BUILD__SCOUT_APM`): GCC 15 on ubuntu-26.04 defaults to C23.
- RuboCop excludes `vendor/**/*`: CI installs gems into vendor/bundle and
  RuboCop crashed loading their configs (exit 2).

Added
- `bin/ci-local` (rubocop + rspec in Docker, `--docker` for the image build)
  and the `.githooks/pre-push` hook; CLAUDE.md with the pre-push rule.

## 2026-11-19 — fork-updates-m6

Changed
- Rails 7.2.1.1 (EOL) → 8.1.4.1. `config.load_defaults` stays at 7.0, so behaviour
  is unchanged; raising it is a separate step.
- acts-as-taggable-on now comes from rubygems (`~> 13.0`) instead of a git
  branch. Also bumped: uri `~> 1.1`, mini_magick `~> 5.1`, ruby-vips 2.3,
  jbuilder 2.15.
- `Dotenv::Rails` replaces `Dotenv::Railtie`, keyword `enum` uses the Rails 8
  syntax, and RSpec uses `fixture_paths`.

## 2026-11-19 — fork-updates-m5

Fixed
- Telegram, Vonage and MessageBird send every attachment, each as its own
  request, in document order. The text is the caption of the first attachment
  that sends. If no attachment sends, the text goes as a separate message.
- MessageBird reads the message id from the documented top-level `id`.

Security
- Twitter media uploads use `MessageApis::SafeDownload` (stdlib, no new gems):
  - only http(s) URLs;
  - the request goes only to the address that passed the check (no DNS
    rebinding) and ignores ENV proxies;
  - private, loopback, link-local, CGNAT, multicast, Azure WireServer, NAT64,
    6to4, Teredo and IPv4-mapped/compatible addresses are refused;
  - every redirect is re-checked, at most 3;
  - at most 15 MB and 30 s per download.
  - The app's own HOST (same scheme and port) is allowed.

Known issues
- Vonage read receipts link only the first attachment of a multi-attachment
  message: a message part stores one external id.
- Twilio and Dialog360 still send only the first attachment. Server-side URL
  fetches outside relaying (hooks_controller, link cards, URL uploads,
  campaigns) do not use SafeDownload yet.

## 2026-11-19 — fork-updates-m4

Fixed
- Legacy `{"blocks": ...}` messages (Slack inbound, older media; Dante nodes and
  Draft.js blocks) are relayed again by telegram, vonage, message_bird, telnyx_sms
  and Slack.
- Plain text puts a newline between paragraphs; a media caption is used when the
  message has no other text.
- Media URLs: `BlockManager.absolute_url` replaces `URI.join`. It percent-encodes
  spaces and non-ASCII characters, keeps existing `%XX` escapes, sends
  protocol-relative `//host` URLs as https, and rejects non-HTTP schemes.
- Slack: message text is mrkdwn-escaped (`& < >`) and sent with `verbatim: true`,
  so `@here` and `@channel` are not parsed as mentions.
- SMTP without `SMTP_USERNAME` works without authentication (was 500) in
  production, staging and development. Staging and development now also read
  SMTP_PORT and SMTP_DOMAIN.

Changed
- docker-compose: `redis:8.10-alpine` (was 5; Sidekiq 7 needs Redis 6.2+). The
  existing volume's RDB loads. Redis 8 is licensed AGPL/RSAL/SSPL, not BSD.

Known issues
- Telegram, Vonage and MessageBird forward only the first attachment of a message.
- Twitter plugin downloads relayed image URLs server-side without a destination
  check.
- Rails 7.2 is EOL (Aug 2026); upgrade to 8.x is a separate milestone.

## 2026-11-18 — fork updates (fork-updates-m1..m3)

Added
- Rack::Attack: 20 password-grant logins/hour per IP on `/oauth/token(.:format)`;
  query `grant_type` wins over body (as in Rails); counters in Redis (`REDIS_URL`)
  in production/staging.
- Devise password-change and email-changed notifications (`deliver_later`).
- Appstore plugins restored from upstream tag `1.0.0` (+ Zapier `07b747ae`),
  adapted to Faraday 2 and the Dante block format; Slack user scopes reduced (#917).
- SMTP_PORT / SMTP_DOMAIN from ENV; `.gitattributes` (LF); puma workers from
  `WEB_CONCURRENCY` (default unchanged).

Changed
- Dead git gem sources replaced: globalize `~> 7.1`, roadie-rails `~> 3.4` (rubygems).
- Dependency bumps (Snyk): devise 5, faraday 2, aws-sdk-rails 5 + aws-actionmailer-ses,
  rack 2.2.25, axios 1.21.1, etc. SES configured via `ses_settings` in all envs.
- CI actions: checkout v7, login v4, metadata v6, build-push v7, `$GITHUB_OUTPUT`.
- Propshaft no longer scans `node_modules` (public/assets 848 MB -> 14 MB).
- docker-compose: postgres on named volume (`POSTGRES_DATA` to keep old path), no tmpfs.

Fixed
- `locahost` typo in dev WS URL; plugin autoload guarded by plugins table check;
  null-safe meta tags in App.tsx; deterministic campaign escaping spec.

Known issues
- (fixed in m4) legacy `{"blocks": ...}` relay, paragraph separator, staging
  Rack::Attack Redis store test.
