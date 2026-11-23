# Changelog

## 2026-11-23 — Review fixes (backend)

- EventsChannel now rejects subscriptions from anyone who is not the owner or
  an agent of the connection's app whose role may read conversations (an
  `admin_only` role is rejected, as in the GraphQL conversation resolvers).
- SES complaint and permanent bounce notifications unsubscribe the address
  only in the app that sent the campaign or conversation email; notifications
  without a Chaskiq header unsubscribe nobody, and already unsubscribed
  contacts no longer abort processing.
- Launching a campaign that is already delivering or sent is a no-op (one
  conditional UPDATE); if the job cannot be enqueued the state is restored so
  the campaign can be launched again. Each recipient is mailed at most once: SesSenderJob
  records a "send" metric under an advisory lock, MailSenderJob retries skip
  recipients that have one, and the SES "send" event does not add a second.
- mergeContact finds the app by key and passes the destination contact
  record, so the mutation works.

## 2026-11-23 — Review fixes (frontend)

- Agent inbox: a late response for a conversation the agent already left no
  longer replaces the open conversation, and replies or notes are refused
  while the loaded conversation differs from the one in the URL.
- Agent and widget editors keep the typed message until the server accepts
  it; on failure the text stays for a retry, and a second send while one is
  in flight is ignored.
- An expired agent session now refreshes the token and replays the failed
  request instead of redirecting to the home page.
- Widget: a conversation state update no longer falls through into the
  typing handler, which could leave the typing indicator stuck.
- Contact profile "Compose a new message": a second send while one is in
  flight is ignored, and the text is cleared only after the conversation was
  started (kept for a retry on failure).

## 2026-11-23 — Review fixes (release and deploy)

- Publish GHCR and Docker Hub images only after CI passed for the commit
  (`workflow_run` of CI for branches; releases and manual runs check for a
  successful CI run). GitHub releases `vX.Y.Z` add `X.Y.Z`, `X.Y` and `X`
  tags on GHCR.
- Heroku: move `app.json` from the retired heroku-20 stack to heroku-26, replace
  the removed free dyno size with `basic`, and run `rails db:prepare` in a
  `release` phase (it also replaces the postdeploy schema load and seed).
- README: upgrade notes; migrations must run before the new image serves
  traffic, since channel delivery needs the `delivery_index` unique index.

## 2026-11-23 — Security updates

- Update JWE to 1.1.1, ProseMirror View to 1.43.0, and Doorkeeper to
  5.9.9 to fix CVE-2025-54887, GHSA-c8x8-7fp4-3x9w, and CVE-2026-115472.
- Use ProseMirror Model 1.25.13 across the editors to meet the updated View's
  dependency requirement.

## 2026-11-23 — fork-updates-r9

- Remove the RuboCop backlog file and its inheritance settings after resolving
  the remaining exclusions. The local and GitHub checks use the main RuboCop
  configuration directly, preserving the existing default exclusions.

## 2026-11-23 — fork-updates-r10r

- Split GraphQL execution, package iframe handling, and inbound email processing into
  smaller methods. Preserve request contexts, responses, and multipart handling.
  Remove four RuboCop exclusions for the affected controllers and concern.

## 2026-11-23 — fork-updates-r10t

- Split AppType resolvers by domain while keeping GraphQL field declarations and
  arguments in their original order. Extract conversation filtering and search
  helpers and remove the three AppType RuboCop exclusions.

## 2026-11-23 — fork-updates-r10u

- Refactored four RuboCop outliers: `AppPackageIntegration#call_hook` and
  `Plugin.save_plugin_files_to_folder` (AbcSize), `GlobalizeAccessors` included
  block (BlockLength), and `BaseSchema#initialize` (CyclomaticComplexity). Each
  method was split into smaller helpers without changing behaviour. Removed the
  four corresponding exclusions from .rubocop_todo.yml. Tests cover hook dispatch,
  plugin file writing, localized accessor generation, and schema validation.

## 2026-11-23 — fork-updates-r10s

- Split conversation creation and notification email delivery into smaller methods.
  Preserve bot reply attribution and the original email headers, templates, and skip
  conditions. Remove the six RuboCop exclusions for both implementations.

## 2026-11-23 — fork-updates-r10q

- Split bot scenario templates and step dispatch into smaller methods while preserving
  path order, fallbacks, reply handling, and follow-up actions. Remove six RuboCop
  exclusions for the action trigger services.

## 2026-11-23 — fork-updates-r10p2

- Pinned the full Elasticsearch request body in `spec/models/segment_es_r10p2_spec.rb`
  (28 examples): app_id filter, page/per_page passthrough, must/must_not/should/filter
  grouping, unknown-attribute and match-type skipping, all standard and nested custom-field
  comparison branches, nested is_null/is_not_null, empty predicates, array order, regex
  strings, and Rails.logger call. Refactored `es_search` and `nested_preds_group` into
  smaller private helpers (`es_search_attrs`, `standard_comparison_fragment`,
  `nested_comparison_fragment`, `es_query_body`); removed dead code. Removed the three
  remaining Segment exclusions (AbcSize, CyclomaticComplexity, MethodLength).

## 2026-11-23 — fork-updates-r10v

- Move app agent and administrator methods into a dedicated concern.
  Restore RuboCop's default module length limit. Tests cover user, lead,
  and visitor handling, plus bot and administrator roles.

## 2026-11-23 — fork-updates-r10p1

- Split Segment's tag matching, joins, and exclusions into smaller methods.
  Each exclusion still builds its EXCEPT subquery from the original app scope.
  Tests cover matching, scoping, duplicate rows, and the shape of exclusion SQL.
  Removed the BlockLength and PerceivedComplexity exclusions for Segment.

## 2026-11-22 — fork-updates-r10o

- Changed: attachment delivery separates media attempts, text fallback and failure reporting.
  Dante renders HTML nodes through smaller dispatch methods and migrates bot-task messages
  one record at a time. Tests cover attachment replay indices, HTML and renderer arguments,
  and migration failures. Eight RuboCop exclusions were removed.

## 2026-11-22 — fork-updates-r10n

- Changed: `MessageApis::OpenAi::Api#notify_message` and `MessageApis::Csat::Api#report` are split
  into smaller private helpers without a change in behaviour (Metrics/AbcSize outliers of R8a,
  milestone R10n of the R10 programme): OpenAI builds the prompt messages in `build_prompt_messages`
  and saves the GPT reply in `save_gpt_reply` (early exits, cache write before HTTP and the rescue
  boundary for response extraction are kept); CSAT dispatches `report` to `report_general` and
  `report_events_table` (filter, serialisation, pagination and percentages are preserved). Their two
  AbcSize lines leave the todo.

## 2026-11-22 — fork-updates-r10m

- Changed: the Telegram, Twitter and TwilioPhone adapters build their outgoing and incoming
  flows in smaller methods without a change in behaviour (Metrics outliers of R8a, milestone
  R10m of the R10 programme): Telegram `send_message` extracts the HTML fallback, the block
  parse (with the original rescue boundary over `get_blocks` and `plain_text`), the channel
  lookup and the attachment delivery; Twitter `process_event` moves each DM into
  `process_twitter_dm` with the conversation creation in its own helper, and `send_message`
  keeps the header before the block parse and adds the image attachment in
  `attach_twitter_image`; TwilioPhone `process_message` keeps the original routing order and
  the `external_profiles` probe, `process_incoming_call` splits the phone extraction, the
  conversation lookup, the controls, the agent notification and the conference call, and
  `process_incoming_event` splits the status recording, the SID store, the broadcast and the
  per-event branch. Their four todo lines are gone.

## 2026-11-22 — fork-updates-r10l

- Changed: the WhatsApp adapters (Twilio, Vonage, MessageBird, Dialog360) build their outgoing
  requests in smaller methods without a change in behaviour (Metrics outliers of R8a, milestone
  R10l of the R10 programme): each `send_message` hands the delivery to a `deliver_blocks` helper,
  Vonage and MessageBird parse the message content in `outgoing_blocks`/`parse_blocks`, and
  Dialog360 `send_template_message` finds the conversation, the profile, the payload and the sent
  message record in their own methods. A golden fixture (spec/fixtures/whatsapp/provider_payloads.json,
  110 cases generated on the old code with WebMock) pins the returned values, every request (URI,
  headers, raw body) and the conversation rows afterwards, and a new spec checks it. Their seven
  todo lines are gone.

## 2026-11-22 — fork-updates-r10k

- Changed: `MessageApis::Slack::Api` builds its Block Kit payloads in smaller methods without a
  change in behaviour (Metrics outliers of R8a, milestone R10k of the R10 programme): the thread
  head is assembled from intro, participant fields and agent picker blocks, `notify_message` picks
  the replied/event section and posts through one helper, and `attachment_block` fetches each file
  in its own method under the same rescue. A golden fixture (spec/fixtures/slack/block_kit_payloads.json,
  50 cases generated on the old code with WebMock) pins the returned values and every request
  (URI, headers, raw JSON body) and upload, and a new spec checks it. Its four todo lines are gone.

## 2026-11-22 — fork-updates-r10h2

- Changed: `MessageApis::InboxSections::Presenter.content_hook` is split without a change in
  behaviour (Metrics outliers of R8a, milestone R10h of the R10 programme): each block type is a
  method, picked from two tables (blocks before and after the `c` flag, in the order of the old
  chain), and the "Visit" button is one helper. A golden fixture
  (spec/fixtures/presenters/inbox_sections_hooks.json, 43 cases generated on the old code, records
  as fixed doubles) pins the full output of every block and hook, and a new spec checks it. Its four
  todo lines are gone.

## 2026-11-22 — fork-updates-r10i

- Changed: `MessageApis::Dialog360::Presenter.configure_hook` (the WhatsApp template wizard of the
  Dialog360 app) is split into one private method per step: contact search gate, template list
  with pagination buttons, parameters form (`submit-template`) and send (`pick-template`), picked
  from the `TEMPLATE_STEPS` table. The order of the checks, the key forms read from `ctx` and the
  calls to the Dialog360 API are kept; the stray in-file disable comment for PerceivedComplexity is gone.
  Its output is pinned by 29 JSON snapshots generated from the old code with a stubbed API
  (spec/fixtures/dialog360/configure_hook/, one per branch, including raised errors and the API
  calls made) and a new spec that compares the full returned value, key order included. The
  three Metrics outliers of the method leave the todo.

## 2026-11-22 — fork-updates-r10h1

- Changed: `MessageApis::ContentShowcase::Presenter.configure_hook` is split without a change in
  behaviour (Metrics outliers of R8a, milestone R10h of the R10 programme): the chain of twelve
  field-id branches is a table of actions with one method per branch, and the response skeletons
  `{kind:, definitions:}` / `{kind: "initialize", definitions:, results:}` are two helpers. A golden
  fixture (spec/fixtures/presenters/content_showcase_hooks.json, 30 cases generated on the old code)
  pins the full output of every branch, and a new spec checks it. Its four todo lines are gone.

## 2026-11-22 — fork-updates-r10g

- Changed: `MessageApis::UiCatalog::Presenter.configure_hook` (the messenger UI catalog demo) picks its
  answer from two tables instead of a chain of nine `if`s: `SUBMIT_RESPONSES` (button id => response
  method) and `ITEM_DEFINITIONS` (list item id => definitions method); each literal moved unchanged
  into its own private method (decision K1 of the R10 programme counts it as one line). The order of
  the checks is kept: a known list item still wins over the "bubu" button.
  Its output is pinned by 32 JSON snapshots generated from the old code (spec/fixtures/ui_catalog/
  configure_hook/, one per catalog element with an action, plus non-submit, precedence and string-key
  cases) and a new spec that compares the full returned hash, key order included. The four Metrics
  outliers of the method leave the todo.

## 2026-11-22 — fork-updates-r10e

- Changed: no spec line is over 140 characters any more (Layout/LineLength outliers of R8a in ten spec
  files, decision K3 of the R10 programme): 22 long request payloads of the Dante renderer, Pipedrive,
  Twitter and Amazon SES specs moved into 21 files under spec/fixtures/requests/<provider>/, read in
  place of the literal; header values, a settings string, expected arrays and call arguments are
  wrapped. Each fixture is byte for byte the old literal and every spec compiles to its old bytecode
  with the fixture read in place of the literal (probe of the milestone); the suite runs the same
  examples. Their 10 entries leave the Layout/LineLength block of the todo.

## 2026-11-22 — fork-updates-r10c

- Changed: every line over 140 characters in the nine files fork-updates-r9b touched (Layout/LineLength
  outliers of R8a) is wrapped: four comments, a `%w[]` list, form-field hashes, a block inside a hash,
  a ternary turned into if/else, a condition, a method chain, a call with keywords and two string
  literals split into adjacent pieces; the 232-character ransack symbol of the conversation search is
  built from its field list.
  Seven files compile to the same bytecode as before; the hooks controller, the conversation search
  and the form-field and ransack lists are pinned by four new specs. Their 9 lines leave the
  Layout/LineLength block of the todo.

## 2026-11-22 — fork-updates-r10cfg

- Changed: Metrics/MethodLength, Metrics/ClassLength and Metrics/BlockLength count a multi-line array,
  hash or heredoc literal as one line (`CountAsOne`, decision K1 of the R10 programme): plugin
  definitions, messenger presenter schemas and provider fixtures are data, not complexity. No code
  changes; 74 length outliers disappear and their 35 entries leave the todo.

## 2026-11-21 — fork-updates-r10b

- Changed: six Metrics outliers of R8a are split without a change in behaviour:
  `SegmentComparator#compare_with` (a table of comparisons), `AppPolicy#find_role_by_resource`
  (`resource_app`), `Dante::Converter.convert_inline_styles` (three helpers), `VisitCollector#add_web_sessions`,
  `Types::MessengerType#browser_data` and `FetchLinkCardService#attempt_oembed` (extracted helpers). Six specs
  pin every branch, including two defects kept as they are (styles that start mid-text are dropped by the
  draft converter; the oEmbed card type is never stored). Their six todo lines are gone.

## 2026-11-21 — fork-updates-r10a

- Changed: every line over 140 characters in 20 files of app/ (Layout/LineLength outliers of R8a) is
  wrapped: 29 comments, a `%w[]` list, a hash, an argument list and five string literals split into
  adjacent pieces. Nineteen files compile to the same bytecode as before; the twentieth (the GraphQL
  schema error message) and every other method whose code was wrapped are pinned by seven new specs.
  Their 20 lines leave the Layout/LineLength block of the todo.

## 2026-11-21 — fork-updates-r9b

- Changed: the last one-off RuboCop Style offenses outside Metrics, behaviour kept: modifier if/unless
  (same bytecode), safe navigation chains split through a local, block chains through a local,
  interpolation instead of `+` where the operand is always a String, `case` and a frozen hash instead
  of if-chains and a hash-like `case`, `map`, `each_key`, `method_defined?`, `include?` on a word list.
- Changed: `Style/StringConcatenation` excludes the two GraphQL controllers and `campaign.rb`: there
  `+` raises on a non-String operand (client operationName, a nameless campaign) and that stays.
- Removed: empty todo blocks IdenticalConditionalBranches and SpecialGlobalVars. Seven specs pin the
  changed behaviour; the modifier rewrite is checked by bytecode.

## 2026-11-21 — fork-updates-r9a

- Changed: every `a === b` whose receiver is a String, Integer or nil is written `a == b` (30 places in
  app/, three `be ===` matchers in a spec): the same method for those receivers. `Style/CaseEquality`
  allows `Klass === obj` (`AllowOnConstant`); its todo block is gone.
- Changed: `SegmentComparator#compare` -> `compare?` and `Zapier::Api#event_identifier_available?` ->
  `event_identifier_and_url`, each old name kept as an `alias`; Slack's `receive_oauth_code` and
  `TarDownloader#download_plugin` act, so they stay and go to `Naming/PredicateMethod` AllowedMethods.
- Changed: in the same files `select { != }` -> `reject { == }`, `.dig("value")` -> `["value"]`, a
  modifier `if` and `each`+`<<` -> `map`. Ten specs pin the behaviour of every changed place.

## 2026-11-21 — fork-updates-r8a

- Changed: RuboCop metric limits by owner decision (R8), each with its reason in `.rubocop.yml`:
  MethodLength and AbcSize 30, Cyclomatic/PerceivedComplexity 13, ParameterLists 7, ClassLength 300
  (integration adapters under `app/services/message_apis/**` excluded), ModuleLength 123 (the length of
  `user_handler.rb`, until its refactor), BlockLength excludes `lib/tasks/**` and `config/routes.rb`,
  LineLength 140 with AllowedPatterns for a URL or base64 blob running to the end of the line.
- Changed: `.rubocop_todo.yml` keeps only the files still above the new limits (outliers, listed for
  refactor milestones) and five Style/IfUnlessModifier entries that Max 140 created; no code changed.

## 2026-11-21 — fork-updates-r7c

- Changed: predicate methods renamed for Naming/PredicatePrefix and Naming/PredicateMethod, each old
  name kept as an `alias` (callers, stubs and integrations keep working):
  `HooksController#is_notification_message?` -> `notification_message?` (private),
  `AppPackage#is_external?` -> `external?`, `ConversationPart#is_event_message?` -> `event_message?`,
  `ConversationPart#is_from_auto_message_campaign?` -> `from_auto_message_campaign?`,
  `Conversation#has_user_visible_comment?` -> `user_visible_comment?`, `OutgoingWebhook#is_enabled` ->
  `enabled?`, `OriginValidator#is_valid?` -> `valid?`, `OriginValidator#validate_domain` ->
  `validate_domain?`. Specs pin both names.

## 2026-11-21 — fork-updates-r7b

- Changed: RuboCop settings by owner decision, each with its reason in `.rubocop.yml`:
  Style/FormatStringToken keeps `unannotated`; Style/ClassAndModuleChildren excludes the five plugin
  files left compact by R4; Naming/PredicateMethod excludes `app/graphql/types/**` (resolvers named
  after schema fields); Style/OneClassPerFile excludes `plugin_schema_validator.rb`. Their entries
  (and the stale `lib/subdomain_routes.rb` one) left `.rubocop_todo.yml`.
- Changed: `ActiveJob::TestHelper` is included once in the RSpec configuration instead of at the top
  level of 13 spec files (Style/MixinUsage); the suite runs the same examples.

## 2026-11-21 — fork-updates-r7d

- Changed: classes that shared a file with another top-level class moved to their own files under
  Zeitwerk, names unchanged (Style/OneClassPerFile): `OauthExeption` (app/controllers),
  `AttachProfileAvatar` (app/graphql), `ExternalApiClient` and `ExternalPresenterManager`
  (app/models). They now autoload on first use instead of only after their former host file loaded.
- Changed: local variables renamed (Naming/VariableName, Naming/VariableNumber): `maxWidth`/`maxHeight`
  in `MessageApis::Helpers#get_aspect_ratio`, `step_7` in `ActionTriggerFactory.infer_for`, and a
  `let` in `segment_spec.rb`; no behaviour change. Specs pin the moved classes and both methods.

## 2026-11-21 — fork-updates-r2b

- Changed: `MessageApis::OpenAi::Api#locked_for_channel?` and `MessageApis::Twilio::Api#new_conversation_thread?`
  return `false` instead of `nil` on their early exits (Style/ReturnNilInPredicateMethodDefinition); callers
  only test truthiness.
- Changed: `MessageApis::OauthUtils::HEADERS` is frozen (Style/MutableConstant).
- Changed: `App#availability` memoizes in `@availability` (was `@biz`); ApiController's memoized ivars are
  excluded from Naming/MemoizedInstanceVariableName in `.rubocop.yml` with the reason.
- Changed: Gemfile gems sorted within their sections (Bundler/OrderedGems); Gemfile.lock unchanged.

## 2026-11-21 — fix-cleanup-3

- Fixed: `Lead#verify!` no longer turns the matching app user into a lead: the merge copied the lead's
  `type` attribute onto the user, and a repeated `verify!` then converted the lead itself.
- Fixed: `Lead#verify!` merges into the matching app user with the smallest id when several app users
  of the app share the email (`find_by` without an order picked an arbitrary row).

## 2026-11-21 — fork-updates-r3b3

- Changed: `POST /package_iframe_internal/:package` reads the user id with
  `params.expect(user: [:id])` and answers 400 when `user` is missing, not a hash or has no `id`
  (was 500 for a missing `user` and 404 otherwise).
- Changed: Rails/StrongParametersExpect cleaned up: the two path parameters (`provider` of the global
  hooks, `id` of the campaign preview) are read with `params.expect` without behaviour changes;
  specs added for all three sites.

## 2026-11-21 — fix-cleanup-2

- Fixed: `Lead#verify!` of a lead whose email no app user of the app has turns the lead into an app
  user (it called `clone_records_and_discard(nil)` and raised `NoMethodError`).
- Fixed: `needs_privacy_consent` honours the "ue" setting that the messenger settings UI saves (only
  "eu" was checked, so EU consent was never asked); both values are accepted.
- Fixed: `Dashboard#visits` returns no visits instead of raising when the visits series was deleted.
- Fixed: the "none" privacy consent radio in the messenger settings is checked when the saved value
  is "none" or unset (it compared with an empty string).

## 2026-11-20 — fix-cleanup-bugs

- Fixed: `MessageApis::TwilioPhone::Store.delete_key` deletes the field that `set` wrote (it deleted
  from a double-namespaced key, so nothing was ever removed).
- Fixed: Slack notification of an `assigned` event no longer raises when the event data is nil or an
  array (the assignee mention is looked up only for hash data with an email).
- Fixed: `needs_privacy_consent` with the "eu" setting no longer raises `TypeError`: it calls
  `EuCountries.includes?`, now a module function, and answers true only for an EU country code.
- Fixed: unused `ApiController::EULocationError` and its `rescue` in `Api::GraphqlController` removed
  (never raised); the origin error still answers 422.
- Fixed: Nightfury time series use `redis.exists?`: with redis 4.8 `exists` returns an Integer and 0
  is truthy, so a new series was never initialised (its `meta` raised) and `get_range`/`get_all` of a
  deleted series returned `{}` instead of nil.

## 2026-11-20 — fork-updates-r3b2

- Changed: Rails/OrderArguments, Rails/Pluck, Rails/WhereRange and Rails/Delegate cleaned up in 22 files
  (hash arguments in `order`, `pluck` on arrays, a range in `prev_article_url`, `delegate` for two
  forwarders) without behaviour changes; characterization specs added for every site.

## 2026-11-20 — fork-updates-r5b2

- Removed: unused routing constraints `PersonalizedDomain` and `NoSubdomain` and the `DOMAIN` constant
  (lib/subdomain_routes.rb), and the unused `ApiController#eu_location?` stub.
- Changed: remaining Lint offenses in app/ and lib/ cleaned up in 18 files without behaviour changes
  (AssignmentInCondition, BooleanSymbol, SymbolConversion, NonLocalExitFromIterator and others);
  characterization specs added.

## 2026-11-20 — fork-updates-r6c

- Changed: Lint offenses in spec/ cleaned up in 18 files (useless assignments, void literals, ambiguous
  block association and operator precedence); the empty spec/controllers/graphql/agent_spec.rb removed;
  the unprivileged agent invite spec now checks that no agent is added.

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
