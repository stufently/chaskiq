"""Mutation gate for fork-updates-m9: the tests written in this milestone must kill these mutants.

Usage (clone root): python3 -I docs/specs/fork-updates-m9-probes/m9_mutation_gate.py [MUTANT_ID ...]
Needs: image chaskiq-test:m1, gems in $HOME/.cache/chaskiq-m6/bundle (Rails 8.1 lock; CHASKIQ_BUNDLE
overrides), postgres:14-alpine, redis:8.10-alpine.

Mutants APPEND a Ruby override to the end of the file that brings back BASE-like behaviour of one
method (`append`); the file must define the overridden method (`needs`). For every target rspec
file the gate first proves it is green on the clean tree. A mutant counts as killed only when the
run had failures, no errors outside examples, and at least one failed example in the target file
whose full description matches the mutant's marker (case-insensitive). The original bytes are
restored in `finally` (sha256 re-checked). Exit 0 only when every mutant is killed by every target.
  OF1  deliver_attachments never calls on_failure            (partial failures lost again)
  OS1  deliver_attachments never calls on_success            (only the first provider id stored)
  OF2  deliver_attachments also reports the response it returns (single failure reported twice)
  NM1  BasePackage#notify_message as on BASE (unguarded get_message_id on the returned response)
  GD1  notify_message without any guard (a single text is sent again on a retry)
  GD2  the old guard find_by(provider:) (a series cut by a timeout is never resumed)
  RN1/RN2/RN3  delivery_hooks already_sent = 0 / N-1 / N+1 instead of the saved row count N
  RP1  replayed attachments do not consume the caption (caption sent again on resume)
  RP2  the separate text is not counted in already_sent (sent again on a full retry)
  LT2/LD2  twilio / dialog360 process_error put the raw webhook into the event again
  IM1  ids stored only after the whole series instead of as each request succeeds
  SG1  BasePackage#message_id_for raises on a success body without an id
  RF1  BasePackage#report_delivery_failure does nothing
  LK1  report_delivery_failure puts the raw provider body into the event (old Twilio format)
  DT1/DV1/DM1/DW1/DD1  telegram/vonage/message_bird/twilio/dialog360 #delivery_hooks returns {}
"""
import hashlib
import json
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
BUNDLE = os.environ.get("CHASKIQ_BUNDLE") or f"{HOME}/.cache/chaskiq-m6/bundle"
IMG = "chaskiq-test:m1"
HOOKS = "spec/controllers/api/v1/hooks"
SPECS = {p: f"{HOOKS}/{p}_spec.rb" for p in ("telegram", "vonage", "message_bird", "twilio", "dialog_360")}
BM_SPEC = "spec/services/message_apis/block_manager_spec.rb"
BM = "app/services/message_apis/block_manager.rb"
BASE_PKG = "app/services/message_apis/base_package.rb"
API = {p: f"app/services/message_apis/{d}/api.rb" for p, d in (
    ("telegram", "telegram"), ("vonage", "vonage"), ("message_bird", "message_bird"),
    ("twilio", "twilio"), ("dialog_360", "dialog360"))}
KLASS = {"telegram": "Telegram", "vonage": "Vonage", "message_bird": "MessageBird",
         "twilio": "Twilio", "dialog_360": "Dialog360"}


def reopen(mod, body):
    return f"\n{mod}\n{body}\nend\n"


def deliver(report_success=True, report_failure=True, report_returned=False,
            replay_takes_caption=True, replay_counts_text=True):
    """m9 contract of deliver_attachments with one part switched off (or over-reporting)."""
    ok = "on_success&.call(r) if r.respond_to?(:success?) && r.success?" if report_success else "nil"
    skip = "" if report_returned else " unless r.equal?(result)"
    fail = (f"failures.each {{ |r| on_failure.call(r){skip} }} if on_failure" if report_failure else "nil")
    replay_caption = "caption = nil if media_caption" if replay_takes_caption else "nil"
    text_guard = "to_skip.zero?" if replay_counts_text else "true"
    return (
        "  def self.deliver_attachments(attachments, plain_text, send_text:, captionless: [], on_success: nil,\n"
        "                               on_failure: nil, already_sent: 0)\n"
        "    first_success = nil\n"
        "    last_response = nil\n"
        "    delivered = false\n"
        "    to_skip = already_sent.to_i\n"
        "    failures = []\n"
        "    caption = plain_text.presence\n"
        "    omit = captionless.respond_to?(:call) ? captionless : ->(type, _url) { captionless.include?(type) }\n"
        "    track = ->(r) { " + ok + "; failures << r if r.respond_to?(:success?) && !r.success? }\n"
        "    attachments.each do |media|\n"
        "      attrs = block_data(media)\n"
        "      next unless attrs.is_a?(Hash)\n"
        "      url = absolute_url(attrs[\"url\"])\n"
        "      next unless url\n"
        "      media_caption = omit.call(media[\"type\"], url) ? nil : caption\n"
        "      if to_skip.positive?\n"
        "        to_skip -= 1\n"
        "        delivered = true\n"
        f"        {replay_caption}\n"
        "        next\n"
        "      end\n"
        "      last_response = yield(media[\"type\"], url, media_caption)\n"
        "      track.call(last_response)\n"
        "      next unless last_response.success?\n"
        "      first_success ||= last_response\n"
        "      delivered = true\n"
        "      caption = nil if media_caption\n"
        "    end\n"
        "    text = delivered ? caption : plain_text.presence\n"
        f"    text_response = send_text.call(text) if text && {text_guard}\n"
        "    track.call(text_response) unless text_response.nil?\n"
        "    ok_text = text_response if text_response.respond_to?(:success?) && text_response.success?\n"
        "    result = if delivered then first_success || ok_text\n"
        "             elsif text then text_response\n"
        "             else last_response\n"
        "             end\n"
        f"    {fail}\n"
        "    result\n"
        "  end")


NOTIFY_BASE = (
    "  def notify_message(conversation:, part:, channel:)\n"
    "    provider = self.class::PROVIDER\n"
    "    return if part.conversation_part_channel_sources.find_by(provider: provider).present?\n"
    "    response = send_message(conversation, part)\n"
    "    return if response.nil?\n"
    "    message_id = get_message_id(JSON.parse(response.respond_to?(:body) ? response.body : response))\n"
    "    return if message_id.blank?\n"
    "    part.conversation_part_channel_sources.create(provider: provider, message_source_id: message_id)\n"
    "  end")

NOTIFY_NO_GUARD = (
    "  def notify_message(conversation:, part:, channel:)\n"
    "    response = send_message(conversation, part)\n"
    "    store_message_id(part, response) unless response.nil?\n"
    "  end")

NOTIFY_OLD_GUARD = (
    "  def notify_message(conversation:, part:, channel:)\n"
    "    return if part.conversation_part_channel_sources.find_by(provider: self.class::PROVIDER).present?\n"
    "    response = send_message(conversation, part)\n"
    "    store_message_id(part, response) unless response.nil?\n"
    "  end")


def hooks_with(n_expr):
    return (
        "  def delivery_hooks(conversation, part)\n"
        "    count = part.persisted? ? part.conversation_part_channel_sources.where(provider: self.class::PROVIDER).count : 0\n"
        f"    {{ already_sent: {n_expr},\n"
        "      on_success: ->(r) { store_message_id(part, r) if part.persisted? },\n"
        "      on_failure: ->(r) { report_delivery_failure(conversation, part, r) } }\n"
        "  end")


TWILIO_OLD_ERROR = (
    "  def process_error(params)\n"
    "    channel = find_channel_from_part_source(params[\"SmsSid\"])\n"
    "    return unless channel\n"
    "    channel.conversation_part.conversation.add_message_event(\n"
    "      action: \"errored: #{params['SmsStatus']}\", provider: PROVIDER,\n"
    "      message_source_id: \"bypass-internal-#{params['id']}\", data: { status: params })\n"
    "  end")

D360_OLD_ERROR = (
    "  def process_error(params)\n"
    "    channel = find_channel(params[\"id\"])\n"
    "    return if channel.blank?\n"
    "    errors = params[\"errors\"]\n"
    "    msg = errors.is_a?(Array) ? errors.map { |o| \"#{o['code']} #{o['title']}\" }.join : \"\"\n"
    "    channel.conversation_part.conversation.add_message_event(\n"
    "      action: \"errored: #{msg}\", provider: PROVIDER,\n"
    "      message_source_id: \"bypass-internal-#{params['id']}\", data: { status: params })\n"
    "  end")

DEFERRED = (
    "  def delivery_hooks(conversation, part)\n"
    "    { already_sent: part.persisted? ? part.conversation_part_channel_sources.where(provider: self.class::PROVIDER).count : 0,\n"
    "      on_success: ->(r) { (@m9_late ||= []) << r },\n"
    "      on_failure: ->(r) { report_delivery_failure(conversation, part, r) } }\n"
    "  end\n\n"
    "  def notify_message(conversation:, part:, channel:)\n"
    "    sent = part.conversation_part_channel_sources.where(provider: self.class::PROVIDER).count\n"
    "    return if sent.positive? && !resumable_delivery?(part)\n"
    "    @m9_late = []\n"
    "    response = send_message(conversation, part)\n"
    "    return if response.nil?\n"
    "    ([response] + @m9_late).each { |r| store_message_id(part, r) }\n"
    "  end")

UNSAFE_ID = (
    "  def message_id_for(response)\n"
    "    get_message_id(JSON.parse(response.respond_to?(:body) ? response.body : response)).to_s.presence\n"
    "  end")

RAW_EVENT = (
    "  def report_delivery_failure(conversation, part, response)\n"
    "    body = begin\n"
    "      JSON.parse(response.body)\n"
    "    rescue StandardError\n"
    "      \"\"\n"
    "    end\n"
    "    msg = body.is_a?(Hash) ? body[\"message\"] : \"\"\n"
    "    conversation.add_message_event(action: \"errored: #{msg}\", provider: self.class::PROVIDER,\n"
    "                                   message_source_id: \"bypass-internal-#{part.id}\", data: { status: body })\n"
    "  end")

BM_CLASS = "class MessageApis::BlockManager"
PKG_CLASS = "class MessageApis::BasePackage"

MUTANTS = [
    # id, file, (kind, text, needs), targets, marker (regex on failed example description)
    ("OF1", BM, ("append", reopen(BM_CLASS, deliver(report_failure=False)), "on_failure"),
     [BM_SPEC, SPECS["twilio"]], r"on_failure|partial failure"),
    ("OS1", BM, ("append", reopen(BM_CLASS, deliver(report_success=False)), "on_success"),
     [BM_SPEC, SPECS["vonage"], SPECS["dialog_360"]], r"on_success|provider id"),
    ("OF2", BM, ("append", reopen(BM_CLASS, deliver(report_returned=True)), "on_failure"),
     [BM_SPEC, SPECS["twilio"]], r"returned|once"),
    ("NM1", BASE_PKG, ("append", reopen(PKG_CLASS, NOTIFY_BASE), "def notify_message"),
     [SPECS["dialog_360"]], r"empty"),
    ("GD1", BASE_PKG, ("append", reopen(PKG_CLASS, NOTIFY_NO_GUARD), "def notify_message"),
     [SPECS["twilio"]], r"single text"),
    ("GD2", BASE_PKG, ("append", reopen(PKG_CLASS, NOTIFY_OLD_GUARD), "def resumable_delivery?"),
     [SPECS["vonage"]], r"resume"),
    ("RN1", BASE_PKG, ("append", reopen(PKG_CLASS, hooks_with("0")), "already_sent"),
     [SPECS["vonage"]], r"resume|retry"),
    ("RN2", BASE_PKG, ("append", reopen(PKG_CLASS, hooks_with("[count - 1, 0].max")), "already_sent"),
     [SPECS["vonage"]], r"resume|retry"),
    ("RN3", BASE_PKG, ("append", reopen(PKG_CLASS, hooks_with("count + 1")), "already_sent"),
     [SPECS["vonage"]], r"resume"),
    ("RP1", BM, ("append", reopen(BM_CLASS, deliver(replay_takes_caption=False)), "already_sent"),
     [BM_SPEC, SPECS["vonage"]], r"already_sent|resume"),
    ("RP2", BM, ("append", reopen(BM_CLASS, deliver(replay_counts_text=False)), "already_sent"),
     [BM_SPEC, SPECS["twilio"]], r"already_sent|separate text"),
    ("IM1", BASE_PKG, ("append", reopen(PKG_CLASS, DEFERRED), "def store_message_id"),
     [SPECS["vonage"]], r"immediately"),
    ("SG1", BASE_PKG, ("append", reopen(PKG_CLASS, UNSAFE_ID), "def message_id_for"),
     [SPECS["dialog_360"]], r"empty"),
    ("RF1", BASE_PKG, ("append", reopen(PKG_CLASS, "  def report_delivery_failure(*) = nil"), "def report_delivery_failure"),
     [SPECS["twilio"], SPECS["telegram"]], r"partial failure|once"),
    ("LK1", BASE_PKG, ("append", reopen(PKG_CLASS, RAW_EVENT), "def report_delivery_failure"),
     [SPECS["twilio"]], r"safe"),
    ("LT2", API["twilio"], ("append", reopen("class MessageApis::Twilio::Api", TWILIO_OLD_ERROR), "def process_error"),
     [SPECS["twilio"]], r"status callback"),
    ("LD2", API["dialog_360"], ("append", reopen("class MessageApis::Dialog360::Api", D360_OLD_ERROR), "def process_error"),
     [SPECS["dialog_360"]], r"failed status event"),
] + [
    (f"D{k}1", API[p], ("append", reopen(f"class MessageApis::{KLASS[p]}::Api", "  def delivery_hooks(*) = {}"),
                        "delivery_hooks(conversation, part)"),
     [SPECS[p]], r"partial failure|provider id")
    for k, p in (("T", "telegram"), ("V", "vonage"), ("M", "message_bird"), ("W", "twilio"), ("D", "dialog_360"))
]


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


class Env:
    def __init__(self, root):
        self.root = root
        self.id = f"chqm9m-{hashlib.sha256(root.encode()).hexdigest()[:8]}-{os.getpid()}"
        self.n = 0

    def up(self):
        sh(["docker", "network", "create", self.id], check=True)
        sh(["docker", "run", "-d", "--name", f"{self.id}-pg", "--network", self.id, "--network-alias", "pg",
            "-e", "POSTGRES_PASSWORD=password", "--tmpfs", "/var/lib/postgresql/data", "postgres:14-alpine"], check=True)
        sh(["docker", "run", "-d", "--name", f"{self.id}-redis", "--network", self.id, "--network-alias", "redis",
            "redis:8.10-alpine"], check=True)
        for _ in range(60):
            if sh(["docker", "exec", f"{self.id}-pg", "pg_isready", "-U", "postgres", "-h", "127.0.0.1"]).returncode == 0:
                break
            sh(["sleep", "1"])
        r = self.ruby_run("bundle install --quiet && bin/rails db:create db:schema:load >/dev/null")
        if r.returncode != 0:
            sys.exit(f"setup failed: {r.stdout[-2000:]}{r.stderr[-2000:]}")

    def down(self):
        sh(["docker", "rm", "-f", f"{self.id}-pg", f"{self.id}-redis"])
        sh(["docker", "network", "rm", self.id])

    def ruby_run(self, script):
        uid = f"{os.getuid()}:{os.getgid()}"
        return sh(["docker", "run", "--rm", "--network", self.id, "--user", uid,
                   "-e", "HOME=/tmp", "-e", "BUNDLE_PATH=/bundle", "-e", "RAILS_ENV=test",
                   "-e", "DATABASE_URL=postgres://postgres:password@pg:5432/chaskiq_test",
                   "-e", "REDIS_URL=redis://redis:6379/0",
                   "-v", f"{BUNDLE}:/bundle", "-v", f"{self.root}:/app", "-w", "/app", IMG,
                   "bash", "-c", script])

    def rspec(self, target):
        self.n += 1
        out = f"tmp/m9-mut-{os.getpid()}-{self.n}.json"
        if os.path.exists(out):
            os.remove(out)
        r = self.ruby_run(f"bundle exec rspec {target} --format json --out {out}")
        try:
            data = json.load(open(out, encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as e:
            return {"rc": r.returncode, "error": f"no rspec json ({e}); {r.stdout[-400:]}{r.stderr[-400:]}"}
        failed = [e for e in data["examples"] if e["status"] == "failed"]
        return {"rc": r.returncode, "total": data["summary"]["example_count"],
                "failures": data["summary"]["failure_count"],
                "outside": data["summary"]["errors_outside_of_examples_count"],
                "failed": [(e["file_path"], e["full_description"],
                            (e.get("exception") or {}).get("message", "")[:160]) for e in failed]}



def run_target(env, target):
    return env.rspec(target)


def green(target, res):
    return res.get("rc") == 0 and res.get("total", 0) > 0 and res.get("failures") == 0 and res.get("outside") == 0


def killed(target, res, marker):
    if "error" in res or res.get("outside", 1) != 0 or not res.get("failures"):
        return False, [res.get("error", "no failures / errors outside examples")]
    rel = "./" + target
    hits = [f for f in res["failed"] if f[0] in (target, rel) and re.search(marker, f[1], re.I)]
    first = (hits or res["failed"])[0]
    return bool(hits), [f"{first[1]} :: {first[2]}"]


def mutate(raw, kind):
    if kind[0] == "replace":
        return raw.replace(kind[1].encode(), kind[2].encode())
    return raw + kind[1].encode()


def main():
    root = sh(["git", "rev-parse", "--show-toplevel"], check=True).stdout.strip()
    os.chdir(root)
    os.makedirs("tmp", exist_ok=True)
    wanted = set(sys.argv[1:])
    mutants = [m for m in MUTANTS if not wanted or m[0] in wanted]
    if wanted - {m[0] for m in mutants}:
        sys.exit(f"unknown mutant ids: {sorted(wanted - {m[0] for m in mutants})}")
    for mid, path, kind, targets, _marker in mutants:
        text = open(path, encoding="utf-8").read()
        if kind[0] == "replace" and text.count(kind[1]) != kind[3]:
            print(f"{mid}: fragment occurs {text.count(kind[1])} times in {path}, expected {kind[3]}")
            sys.exit(1)
        if kind[0] == "append" and kind[2] and kind[2] not in text:
            print(f"{mid}: {path} does not define `{kind[2]}` (required by the spec)")
            sys.exit(1)
        for t in targets:
            if not os.path.exists(t):
                print(f"{mid}: target {t} missing")
                sys.exit(1)
    env = Env(root)
    ok = True
    try:
        env.up()
        for t in sorted({t for m in mutants for t in m[3]}):
            res = run_target(env, t)
            if not green(t, res):
                print(f"CLEAN TARGET NOT GREEN: {t}: {res}")
                sys.exit(1)
            print(f"clean green: {t}")
        for mid, path, kind, targets, marker in mutants:
            raw = open(path, "rb").read()
            digest = hashlib.sha256(raw).hexdigest()
            try:
                open(path, "wb").write(mutate(raw, kind))
                for t in targets:
                    res = run_target(env, t)
                    k, why = killed(t, res, marker)
                    ok &= k
                    print(f"{mid} {'killed' if k else 'SURVIVED'} by {t}: {why[0][:220]}")
            finally:
                open(path, "wb").write(raw)
                if hashlib.sha256(open(path, "rb").read()).hexdigest() != digest:
                    print(f"{mid}: restore failed for {path}")
                    sys.exit(2)
    finally:
        env.down()
    if not ok:
        print("MUTATION GATE FAIL")
        sys.exit(1)
    print("MUTATION GATE PASS")


main()
