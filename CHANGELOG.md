# Changelog

## 2026-11-20 — fork-updates-r5b2

- Removed: unused routing constraints `PersonalizedDomain` and `NoSubdomain` and the `DOMAIN` constant
  (lib/subdomain_routes.rb), and the unused `ApiController#eu_location?` stub.
- Changed: remaining Lint offenses in app/ and lib/ cleaned up in 18 files without behaviour changes
  (AssignmentInCondition, BooleanSymbol, SymbolConversion, NonLocalExitFromIterator and others);
  characterization specs added.

## 2026-11-20 — fork-updates-r5b1

- Fixed: Slack notification of a conversation event no longer raises when the event data is nil or
  an array (unused `data["label"]` read removed).
- Changed: Lint/UselessAssignment, Lint/Void, Lint/UselessOr, Lint/UnusedMethodArgument and
  Rails/Present cleaned up in 25 files of app/ without other behaviour changes; characterization specs added.

## 2026-11-20 — fork-updates-r3b1

- Changed: Rails/Blank and Rails/Presence autocorrected in 7 files of app/ and lib/ (9 places;
  receiver types checked per site).

## 2026-11-20 — fork-updates-r6b

- Changed: Lint/UnusedMethodArgument allows unused keyword arguments (plugin interface, owner
  decision); unused positional arguments renamed to `_name` in 28 files of app/ and lib/ (45 places,
  RuboCop autocorrect); two ERB presenters stay in the todo.

## 2026-11-20 — fork-updates-r6a

- Changed: Lint/UselessAssignment autocorrected in 64 files of app/ and lib/ (119 unused local
  assignments removed, right-hand sides kept), layout re-aligned; eleven files stay in the todo.

## 2026-11-20 — fork-updates-r5

Fixed
- Compare usage against the configured limit in `Plan#limit_reached?` and treat
  unlimited and unlisted features as having no limit.
- Fall back to named metadata in link cards when the matching Open Graph
  property has no content. Treat blank metadata as absent so the card can
  use the document title.
- Fetch campaign premailer HTML through `SafeDownload` with same-origin
  redirects and raise `Campaign::PremailerFetchError` on fetch failure.
  Trust the origin from the route configuration so the development premailer
  works without a separate `HOST` setting. Compare the redirect origin
  case-insensitively so host capitalization does not block a local redirect.

Removed
- Remove duplicate definitions of `Plan#features=`, `Role#avatar_url`, and
  `AppUserDashboard#conversations`.

## 2026-11-20 — fork-updates-r4

Changed
- Use RuboCop to convert compact class and module declarations to nested
  declarations in 65 files. Verify that constant resolution and class ancestry
  agree with the previous declarations. Keep compact declarations in the five
  files still listed in the `Style/ClassAndModuleChildren` todo.

## 2026-11-20 — fork-updates-r7a

Changed
- Disable `Style/Documentation`, `Naming/AccessorMethodName`, and
  `Naming/MethodParameterName` by owner decision. Record the reasons in
  `.rubocop.yml` and remove the corresponding entries from `.rubocop_todo.yml`.
  This change affects RuboCop configuration only.

## 2026-11-20 — fork-updates-r3

Changed
- Add `# frozen_string_literal: true` to 127 files with RuboCop. Static analysis and the full test suite with all string literals frozen found no literal mutations.

## 2026-11-19 — fork-updates-r2

Changed
- Autocorrect 10 RuboCop Style and Naming cops and remove their todo entries. Each syntax tree change is explained by the matching cop rule and preserves runtime behavior.

## 2026-11-19 — fork-updates-r1

Changed
- RuboCop backlog, first step: 16 layout/style cops autocorrected in 49 files
  (each file compiles to the same Ruby bytecode as before); their entries are
  removed from `.rubocop_todo.yml`. `docs/**` (frozen milestone specs and
  probes pinned by sha256) is excluded from RuboCop. Plan for the rest:
  `docs/specs/fork-updates-rubocop-plan.md`.

## 2026-11-19 — fork-updates-r1

Changed
- Reduce the RuboCop backlog with safe autocorrection for 16 Layout and Style cops without changing runtime behavior, and exclude `docs/` from RuboCop.

## 2026-11-19 — fork-updates-m14

Changed
- Upgrade the application, Docker images and CI to Ruby 4.0.10 and Bundler
  4.0.20. Session cookies, signed tokens and cache entries remain compatible
  between Ruby 3.3 and Ruby 4.0.
- Vendor `php_serialize` 1.2 with writable string buffers. Paddle's PHP
  serialization stays byte-for-byte compatible.
- Keep controller mocks stable in direct test runs and enable reloading
  under Spring.

For Docker Compose operators
- Run `docker compose build` after `git pull`. Compose populates the new
  `bundle_ruby4` volume with the image's gems on the first startup.
- Compose stops mounting the old `<project>_bundle_rack3` volume. Keep it for
  rollback to Ruby 3.3, where the old commit mounts it again. When you no
  longer need it, run `docker volume rm <project>_bundle_rack3` with your
  Compose project name.

## 2026-11-19 — fork-updates-m11

Added
- Telnyx MMS. Outgoing images, video (mp4/3gp), text and vCard attachments are
  sent as `media_urls`, one request per attachment, resumable on retry like the
  other channels; other files go as links in the text. Incoming MMS media is
  downloaded (https `*.telnyx.com` only, on every redirect too; ≤5 MB; API key
  sent only to the first host) and stored as attachments; a failed download or
  upload leaves an "attachment unavailable" line instead of dropping the
  message.
- `message.finalized`: delivered marks the part read; sending/delivery failures
  add one error event per message.

Known issues
- Two workers processing the same incoming webhook at once can store the
  message twice (same as the other channels).
- A `message.finalized` that arrives before the outgoing message id is stored
  is ignored.

## 2026-11-19 — fork-updates-m9

Fixed
- Multi-attachment sends (Telegram, Vonage, MessageBird, Twilio, Dialog360)
  report every failed request as an `errored:` event, and every provider id is
  stored, so Vonage/Dialog360/Twilio receipts match any attachment. A retried
  job sends only the attachments not yet accepted.
- Error events carry only status, provider code and a short text (URLs
  replaced, ≤200 chars); raw provider bodies no longer reach the Messenger.
- Migration: `conversation_part_channel_sources.delivery_index` (run
  `db:migrate`; the index is built concurrently).
- Attachment delivery records each accepted request by index and resumes from
  the remaining requests. The delivery index is created concurrently on
  PostgreSQL. A rerun rebuilds an invalid index left by a failed build.
- Status callbacks ignore blank provider IDs. Error events are deduplicated by
  a session advisory lock and committed before notifications are queued. Lock
  contention lasting five seconds raises an error for Sidekiq to retry.
- Delivery closes the PostgreSQL session when unlocking fails. Failure hooks
  report every failed request and raise the first hook error if delivery did
  not already raise. A lost advisory lock is logged when unlock returns false.

Known issues
- Delivery is at least once. If the provider accepts an attachment or separate
  text request before Chaskiq records its delivery index, a retry can send
  that request again.
- If notification fan-out fails after a status event is saved, deduplication
  skips the replay and the notification remains unsent.

## 2026-11-19 — fork-updates-m10

Security
- Every SNS message (Notification, SubscriptionConfirmation,
  UnsubscribeConfirmation) is verified before anything is done with it:
  SignatureVersion 1 and 2, the exact AWS field lists, and a signing
  certificate fetched only from `https://sns.<region>.amazonaws.com(.cn)`
  (TLS-verified, at most 64 KB, 5 s, no redirects), checked for its validity
  period and cached only after a good signature. An invalid message gets 403.
  A certificate that cannot be fetched gets 503 so SNS retries.
- New `SNS_ALLOWED_TOPIC_ARNS` (comma-separated). When it is set, only those
  topics are accepted. When it is empty, existing subscriptions keep working
  (with a warning in the log) but new subscriptions are not confirmed: set it
  before subscribing a topic.
- A failed `SubscribeURL` confirmation returns 503 instead of 200, so SNS
  retries it.
- A repeated delivery of the same SNS `MessageId` is processed once (Redis
  key, 24 h).

Known issues
- SNS raw message delivery cannot be verified and is rejected; use the
  standard JSON envelope. After deploying, check the log that a real
  subscription confirmation passed verification.

## 2026-11-19 — fork-updates-m13

Changed
- Upgrade to Rack 3.2.8. The maintenance response uses a lowercase `content-type` header.
- Preserve Rack 2's proxy header order. Rack uses `X-Forwarded-For` for the client IP, prefers `X-Forwarded-Scheme` over `X-Forwarded-Proto`, and ignores `Forwarded`.

Operators
- After `git pull`, run `docker compose build`. On first start, Docker fills the new `<project>_bundle_rack3` volume from the rebuilt image.
- Compose stops mounting `<project>_bundle`. Remove it with `docker volume rm <project>_bundle` if you no longer need it. Rolling back to the previous commit restores the original volume mount.

## 2026-11-19 — fork-updates-m12

Changed
- Nightfury is vendored and keeps the existing Redis keys and connection settings. Rails, Cypress, RSpec, and RuboCop no longer use the deprecated APIs and configuration covered by this milestone.

Fixed
- Dashboard metrics include the oldest point in series stored without metadata.
- Twilio Phone reads use the same Kredis connection and namespace as writes, including in staging.
- The offline checker uses the Action Cable Redis connection and checks the exact prefixed channel, so closing one tab keeps users online only while another tab is subscribed to the same channel.
- The Rack health check shares one Redis client across requests, including concurrent first requests.

## 2026-11-19 — agent sign-in fix

Fixed
- `POST /agents/sign_in` returned 500: it called doorkeeper's `AccessToken.find_or_create_for` with positional arguments, which doorkeeper 5.6 dropped for keywords.

## 2026-11-19 — CI parity

Changed
- `bin/ci-local` test image is `ubuntu:26.04` (GCC 15, C23 by default) with the
  ruby/setup-ruby build of Ruby, like the runners; it used to be
  `ruby:*-slim-trixie` with GCC 14 and missed the scout_apm C23 build failure.
  `BUNDLE_BUILD__SCOUT_APM` is set as in the workflows.
- `bin/ci-local` installs gems into `vendor/bundle` in the tree (bind mount of
  its cache, now gitignored and dockerignored), as setup-ruby does, so RuboCop
  sees them as in CI. RuboCop skips other untracked files.

Fixed
- A push could be lost after a long pre-push hook: git connects over SSH before
  the hook, GitHub drops the idle connection after 6-8 min, and git exits 141
  (SIGPIPE) with no message. `bin/ci-local` records passed jobs (key: commit,
  `bin/ci-local` hash, test image content; only for a tree with no untracked or
  non-cache ignored files) and the hook reuses them; without SSH keepalives
  (every <= 60 s, README: `core.sshCommand`) a hook run over 300 s aborts the
  push loudly.
- The pre-push hook accepts only `--docker` in `CI_LOCAL_ARGS` (rubocop and
  rspec always run), has `bin/ci-local --commit` verify the pushed commit
  before and after the run, and refuses untracked files in app/, lib/,
  config/, spec/, db/.
- `bin/ci-local` RuboCop: per-run target lists (parallel runs), tracked files
  with non-ASCII names are no longer skipped as untracked, and
  `tmp/rubocop.txt` holds the offenses (it held only progress dots).
- `bin/ci-local` removes its rspec containers, network and temp files on any
  exit, including Ctrl-C and SIGTERM (a signal used to leave the run going).

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

## 2026-11-19 — strict RuboCop

Changed
- RuboCop offenses now fail CI and `bin/ci-local`. The existing backlog (2554
  offenses) is regenerated into `.rubocop_todo.yml` as per-file excludes only, so
  every cop stays on for new files; `inherit_mode: merge: Exclude` keeps the
  todo excludes alongside `.rubocop.yml`'s own.

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
