# frozen_string_literal: true

# Fixture probe for fork-updates-r10e (run by r10e_fixture_gate.sh inside the CI image, plain Ruby).
# Usage: ruby r10e_fixture_probe.rb <r10e_config.json> <base_dir> <tree_dir>
# <base_dir> holds the BASE copies of the config's app_files; fixtures and specs are read from <tree_dir>.
# For every entry of "fixtures" (BASE file, line, kind, key, fixture, ref, vars, drop_keys):
#   1. the BASE literal is found with Prism: kind "string" = the longest plain '…'/"…" string starting on
#      that line; kind "hash" = the hash value of the pair whose string key is "key", starting on that line
#      (exactly one); its value is evaluated (each name of "vars" bound to one sentinel object);
#   2. BYTES: the fixture file is byte for byte the literal's value (string), or JSON.pretty_generate of the
#      literal's hash without "drop_keys" plus "\n" (hash: JSON values only, each dropped key = the sentinel);
#   3. SELF-CHECK: the same comparison on the fixture with one byte flipped (first, middle, last), one byte
#      cut and one "\n" added must fail (a comparator that accepts a corrupted fixture is a probe defect);
#   4. VALUE: "ref" evaluated against the tree (Rails.root = <tree_dir>, the same sentinels, default external
#      encoding UTF-8 as in Rails) equals the BASE value exactly (Hash key order, String encoding and bytes);
# then for every app file: ISEQ: the BASE file with each entry's literal replaced by its "ref" compiles to the
# same YARV bytecode as the tree file (line numbers ignored): fixtures are the only change of meaning, the
# rest is layout (adjacent string pieces, line breaks, do/end, comments).
# Prints one line per check and "R10E FIXTURES PASS …" or "FAIL: …" lines; exit 1 on any failure.
require "json"
require "pathname"
require "prism"

cfg_path, BASE_DIR, TREE_DIR = ARGV
abort "usage: r10e_fixture_probe.rb <config> <base_dir> <tree_dir>" unless TREE_DIR

Encoding.default_external = Encoding::UTF_8
SENT = Object.new.freeze
CFG = JSON.parse(File.read(cfg_path))
FAILS = []

module Rails
  def self.root = Pathname(TREE_DIR)
end

# Normalized YARV bytecode, as in r10c_iseq.rb: locations dropped, literals compared exactly.
module Iseq
  HEADER = "YARVInstructionSequence/SimpleDataFormat"
  CANON = {
    String => ->(o) { [:S, o.encoding.name, o.bytes, o.frozen?] },
    Symbol => ->(o) { [:Y, o.name.encoding.name, o.name.bytes] },
    Float => ->(o) { [:F, [o].pack("G").bytes] },
    Regexp => ->(o) { [:R, canon(o.source), o.options, o.encoding.name] },
    Range => ->(o) { [:G, canon(o.begin), canon(o.end), o.exclude_end?] }
  }.freeze

  module_function

  def norm(obj)
    case obj
    when Array then obj[0] == HEADER ? norm_iseq(obj) : [:A, obj.map { |x| norm(x) }]
    when Hash then [:H, obj.map { |k, v| [norm(k), norm(v)] }]
    else canon(obj)
    end
  end

  def canon(obj)
    rule = CANON.find { |klass, _| obj.is_a?(klass) }
    rule ? rule.last.call(obj) : [obj.class.name, obj.inspect]
  end

  def norm_iseq(obj)
    misc = obj[4].except(:code_location, :node_id, :node_ids).sort.to_h
    params = obj[11].is_a?(Hash) ? obj[11].except(:node_id) : obj[11]
    body = obj[13].reject { |x| x.is_a?(Integer) || x == :RUBY_EVENT_LINE }
    [obj[5], obj[9], norm(obj[10]), norm(params), norm(obj[12]), norm(misc), body.map { |x| norm(x) }]
  end

  def of(src) = norm(RubyVM::InstructionSequence.compile(src, "f.rb", "f.rb", 1).to_a)

  def first_diff(left, right, where = "")
    unless left.is_a?(Array) && right.is_a?(Array)
      return left == right ? nil : "#{where}: #{left.inspect[0, 100]} <> #{right.inspect[0, 100]}"
    end

    [left.size, right.size].min.times do |i|
      d = first_diff(left[i], right[i], "#{where}[#{i}]")
      return d if d
    end
    "#{where}: length #{left.size} <> #{right.size}" unless left.size == right.size
  end
end

def find_literal(src, entry)
  res = Prism.parse(src)
  raise "BASE #{entry['file']} does not parse" unless res.success?

  found = []
  stack = [res.value]
  until stack.empty?
    n = stack.pop
    stack.concat(n.compact_child_nodes)
    next unless n.location.start_line == entry["line"] || n.is_a?(Prism::AssocNode)

    if entry["kind"] == "hash"
      next unless n.is_a?(Prism::AssocNode) && n.key.is_a?(Prism::StringNode) && n.key.unescaped == entry["key"]
      next unless n.value.is_a?(Prism::HashNode) && n.value.location.start_line == entry["line"]

      found << n.value
    elsif n.is_a?(Prism::StringNode) && %w[' "].include?(n.opening_loc&.slice)
      found << n
    end
  end
  return found.max_by { |n| n.location.length } if entry["kind"] == "string" && found.any?
  return found.first if found.size == 1

  raise "BASE #{entry['file']}:#{entry['line']}: #{found.size} #{entry['kind']} literals#{" for #{entry['key']}" if entry['key']}"
end

def sentinel_binding(vars)
  b = binding
  (vars || []).each { |v| b.local_variable_set(v.to_sym, SENT) }
  b
end

def json_value?(obj)
  case obj
  when Hash then obj.all? { |k, v| k.is_a?(String) && json_value?(v) }
  when Array then obj.all? { |v| json_value?(v) }
  else [String, Integer, TrueClass, FalseClass, NilClass].any? { |c| obj.is_a?(c) }
  end
end

# Exact equality: Hash key order, String encoding and bytes (not frozenness), the sentinel by identity.
def same?(left, right)
  return left.equal?(right) if left.equal?(SENT) || right.equal?(SENT)
  return false unless left.class == right.class

  case left
  when Hash then left.keys == right.keys && left.keys.all? { |k| same?(left[k], right[k]) }
  when Array then left.size == right.size && left.each_index.all? { |i| same?(left[i], right[i]) }
  when String then left.encoding == right.encoding && left.bytes == right.bytes
  else left == right
  end
end

def expected_bytes(entry, value)
  return value.b if entry["kind"] == "string" && value.is_a?(String)
  raise "#{entry['file']}:#{entry['line']}: literal is a #{value.class}, not a #{entry['kind']}" unless value.is_a?(Hash)

  (entry["drop_keys"] || []).each do |k|
    raise "#{entry['file']}:#{entry['line']}: dropped key #{k} is not the sentinel" unless value[k].equal?(SENT)
  end
  rest = value.except(*(entry["drop_keys"] || []))
  raise "#{entry['file']}:#{entry['line']}: hash is not plain JSON data" unless json_value?(rest)

  "#{JSON.pretty_generate(rest)}\n".b
end

def corruptions(bytes)
  flip = ->(i) { bytes.dup.tap { |b| b.setbyte(i, b.getbyte(i) ^ 0x01) } }
  [flip.call(0), flip.call(bytes.bytesize / 2), flip.call(bytes.bytesize - 1), bytes.byteslice(0, bytes.bytesize - 1),
   "#{bytes}\n".b]
end

entries = CFG.fetch("fixtures")
FAILS << "fixtures of the config differ from its new_files" if entries.map { |e| e["fixture"] }.uniq.sort != CFG["new_files"].sort
replacements = Hash.new { |h, k| h[k] = [] }
checked = {}
entries.each do |e|
  src = File.binread(File.join(BASE_DIR, e["file"])).force_encoding(Encoding::UTF_8)
  node = find_literal(src, e)
  base_value = eval(node.slice, sentinel_binding(e["vars"]), e["file"], e["line"]) # rubocop:disable Security/Eval
  want = expected_bytes(e, base_value)
  path = File.join(TREE_DIR, e["fixture"])
  got = File.exist?(path) ? File.binread(path) : nil
  if got != want
    at = got && (0...[got.bytesize, want.bytesize].min).find { |i| got.getbyte(i) != want.getbyte(i) }
    FAILS << "BYTES #{e['fixture']}: #{got ? "#{got.bytesize} bytes" : 'missing'}, BASE literal " \
             "#{e['file']}:#{e['line']} gives #{want.bytesize} bytes#{" (first difference at byte #{at})" if at}"
  elsif !checked[e["fixture"]]
    accepted = corruptions(got).count { |bad| bad == want }
    FAILS << "SELF-CHECK #{e['fixture']}: #{accepted} corrupted copies accepted" unless accepted.zero?
    checked[e["fixture"]] = true
    puts "BYTES OK #{e['fixture']} (#{got.bytesize} bytes = #{e['file']}:#{e['line']}); self-check: 5 corruptions rejected"
  end
  begin
    ref_value = eval(e["ref"], sentinel_binding(e["vars"]), "ref", 1) # rubocop:disable Security/Eval
    FAILS << "VALUE #{e['file']}:#{e['line']}: ref does not give the BASE value" unless same?(base_value, ref_value)
  rescue StandardError => err
    FAILS << "VALUE #{e['file']}:#{e['line']}: ref raises #{err.class}: #{err.message[0, 160]}"
  end
  replacements[e["file"]] << [node.location.start_offset, node.location.end_offset, e["ref"]]
end

CFG.fetch("app_files").each do |f|
  base = File.binread(File.join(BASE_DIR, f))
  list = replacements[f].sort_by(&:first)
  list.each_cons(2) { |a, b| FAILS << "ISEQ #{f}: overlapping literals" if a[1] > b[0] }
  list.reverse_each { |s, t, ref| base[s...t] = ref.b }
  tree = File.binread(File.join(TREE_DIR, f))
  d = Iseq.first_diff(Iseq.of(base.force_encoding(Encoding::UTF_8)), Iseq.of(tree.force_encoding(Encoding::UTF_8)))
  if d
    FAILS << "ISEQ #{f}: tree is not BASE with #{list.size} literals replaced by their refs: #{d}"
  else
    puts "ISEQ SAME #{f} (#{list.size} literals replaced)"
  end
rescue SyntaxError, StandardError => err
  FAILS << "ISEQ #{f}: #{err.class}: #{err.message.lines.first&.strip}"
end

FAILS.each { |m| puts "FAIL: #{m}" }
exit 1 unless FAILS.empty?

puts "R10E FIXTURES PASS #{entries.size} literals, #{checked.size} fixtures, #{CFG['app_files'].size} files"
