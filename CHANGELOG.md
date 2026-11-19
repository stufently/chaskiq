# Changelog

## 2026-11-19 — fork-updates-m8

Changed
- `config.load_defaults 8.1` (was 7.0) with every 7.1–8.1 default on; the empty
  `new_framework_defaults_6_0/7_0` initializers are gone. Old sessions,
  remember-cookies, message-verifier and `CHASKIQ_*` tokens and cache entries keep
  working (checked by the m8 compat probe). YJIT is on in production/staging:
  watch puma/sidekiq RSS after the deploy.

Fixed
- Inbound email with deeply nested markup no longer stores an empty message: the
  HTML5 sanitizer (new default) raises on >400 levels, so it falls back to the
  HTML4 one, and if serialization still fails the reply is kept as text.

Known issues
- Rolling back to `load_defaults 7.0` is one-way for links and signed ids issued
  after the upgrade (JSON message serializer). Do not run `Rails.cache.clear` on
  rollback: Redis is shared with Sidekiq and Rack::Attack, and Rails 8.1 reads the
  cache under both defaults.

## 2026-11-19 — fork-updates-m7

Fixed
- Twilio and Dialog360 now send every attachment, one request each. The caption
  goes only where the provider shows it: Twilio jpeg/png images, never audio.
  Any other text is sent as its own message.
- Twilio and Dialog360 status callbacks for an unknown attachment SID no longer
  crash.
- The oEmbed endpoint and Content Showcase autofill no longer return 500 when a
  page has no preview.
- Boot no longer crashes when `SECRET_KEY_BASE` yields a NUL byte in the URLcrypt
  key (~22% of random keys): the deprecated `URLcrypt.key=` is replaced. Keys
  without NUL keep the same bytes.

Security
- The remaining server-side URL fetches now go through `SafeDownload`:
  - SNS `SubscribeURL` is fetched only for https on port 443 at
    `sns.<region>.amazonaws.com`, with no redirects;
  - link cards are one GET of at most 2 MB that honours the charset and
    verifies TLS (it used to be `VERIFY_NONE`);
  - `og:image` and oEmbed thumbnails;
  - `CreateUrlUpload`, limited to 100 MB.
- oEmbed asks only registered providers. Discovery of endpoints from page HTML
  is off.

Known issues
- In a multi-attachment send, a failure after the first successful request is
  not reported back. Each message part stores one provider id.

## 2026-11-19 — CI repair, local CI

Fixed
- Ruby 3.3.5 → 3.3.14 (latest 3.3 patch) in Gemfile, .ruby-version,
  Gemfile.lock, Dockerfiles, compose and workflows: setup-ruby has no 3.3.5
  build for ubuntu-26.04 runners.
- Docker images: base `ruby:*-slim-bullseye` → `-slim-trixie` (bullseye
  security repo is gone, apt exited 100); PGDG/NodeSource/Yarn repos via
  `signed-by` keyrings instead of the removed `apt-key`; deps add libyaml-dev,
  pkg-config.
- Docker images: Node 16 (EOL) → 26 LTS (same as CI), pinned to NodeSource (trixie's own
  nodejs 20 used to win over NODE_MAJOR); the build fails on a wrong major.
- CI: postgres:14-alpine and redis:8.10-alpine services (as in compose), Node 26
  LTS for the spec JS deps, app store packages and E2E only with the upstream
  secrets; current action versions (codeql upload-sarif v4, anchore v7).
- Rubocop workflow: the exit-code check was expanded by the outer shell and
  never ran; offenses stay non-fatal, a RuboCop error fails the job.
- Push Docker Image skips its steps when Docker Hub secrets are absent.
- Workflows: release tag passed to the push script via env (script
  injection); Docker Hub and app store secrets only in the steps that use them.
- `bin/ci-local` fails on a `bundle install` error instead of reading it as
  style offenses; the pre-push hook refuses unless HEAD is the pushed commit
  and tracked files are clean; deleted refs and tags are skipped. Secret
  presence checks see only a true/false flag.
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
- (fixed in m7) Twilio/Dialog360 attachments, SafeDownload outside relaying.
  `Campaign#clean_inline_css` still fetches the app's own premailer URL directly:
  the app builds that URL itself.

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
