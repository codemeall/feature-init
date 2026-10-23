# Read only the canonical, script-owned v1/v2 manifest format. This is intentionally
# not a general JSON parser: reject unfamiliar input instead of guessing a baseline.
function fail(message) {
  print "Error: invalid sources.json: " message > "/dev/stderr"
  failed = 1
  exit 2
}
function path_ok(path, source) {
  if (source && path == ".") return 1
  return path != "" && path !~ /[\\"[:cntrl:]]/ && path !~ /^\// &&
    path !~ /\/$/ && path !~ /\/\// && path !~ /(^|\/)\.\.?($|\/)/
}
# Older stamps accepted harmless dot segments and repeated slashes in --source.
# Normalize only legacy source spelling; traversal and absolute paths stay invalid.
function legacy_source(path,    segments, count, i, result) {
  if (path == "" || path ~ /^[\/]/ || path ~ /[\\"[:cntrl:]]/) fail("invalid legacy source path")
  count = split(path, segments, "/")
  result = ""
  for (i = 1; i <= count; i++) {
    if (segments[i] == "..") fail("invalid legacy source traversal")
    if (segments[i] == "" || segments[i] == ".") continue
    result = result (result == "" ? "" : "/") segments[i]
  }
  return result == "" ? "." : result
}
function date_ok(date) { return date ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ }
NR == 1 { if ($0 != "{") fail("expected canonical object"); next }
closed { fail("content after object") }
section != "" {
  if ($0 ~ /^  },?$/) {
    if (entries && map_comma) fail("trailing comma in " section)
    last_comma = ($0 ~ /,$/)
    section = ""
    next
  }
  if ($0 !~ /^    "[^"\\]+": "[0-9a-f]+",?$/) fail("invalid hash entry in " section)
  if (entries && !map_comma) fail("missing comma in " section)
  value = $0
  sub(/^    "/, "", value)
  split(value, parts, /": "/)
  path = parts[1]
  hash = parts[2]
  sub(/",?$/, "", hash)
  if (!path_ok(path, 0) || length(hash) != 64) fail("invalid path or SHA-256 in " section)
  if ((section SUBSEP path) in hashes) fail("duplicate path in " section ": " path)
  hashes[section SUBSEP path] = hash
  order[++n] = section SUBSEP path
  counts[section]++
  entries++
  map_comma = ($0 ~ /,$/)
  next
}
$0 == "}" {
  if (!fields || last_comma) fail("invalid object ending")
  closed = 1
  next
}
{
  if ($0 !~ /^  "(version|source|synced|files|reviewed|documents|evidence)": /) fail("unknown field or noncanonical formatting")
  if (fields && !last_comma) fail("missing field comma")
  key = $0
  sub(/^  "/, "", key)
  sub(/".*/, "", key)
  if (key in seen) fail("duplicate field: " key)
  seen[key] = 1
  fields++
  value = $0
  sub(/^  "[a-z]+": /, "", value)
  last_comma = (value ~ /,$/)
  sub(/,$/, "", value)
  if (key == "files" || key == "documents" || key == "evidence") {
    if (value == "{}") next
    if (value != "{" || last_comma) fail("expected hash map for " key)
    section = key
    entries = 0
    map_comma = 0
    next
  }
  if (key == "version") {
    if (value != "2") fail("unsupported manifest version")
    values[key] = value
  } else if ((key == "source" || key == "synced") && value == "null") {
    values[key] = ""
  } else {
    if (value !~ /^"[^"\\]*"$/) fail("invalid scalar for " key)
    values[key] = substr(value, 2, length(value) - 2)
    if (key != "source" && !date_ok(values[key])) fail("invalid date for " key)
  }
}
END {
  if (failed) exit 2
  if (!closed || section != "") fail("incomplete object")
  if (!("source" in seen) || !("synced" in seen) || !("files" in seen)) fail("missing source fields")
  version = ("version" in seen) ? "2" : "1"
  if (version == "1") {
    if (fields != 3 || values["source"] == "" || values["synced"] == "" || !counts["files"]) fail("invalid legacy manifest")
    values["source"] = legacy_source(values["source"])
  } else {
    if (fields != 7 || !("reviewed" in seen) || !("documents" in seen) || !("evidence" in seen)) fail("missing review fields")
    if (counts["documents"] != 3 || !("documents" SUBSEP "overview.md" in hashes) ||
        !("documents" SUBSEP "decisions.md" in hashes) || !("documents" SUBSEP "tickets.md" in hashes)) fail("expected three document hashes")
    if (!counts["evidence"]) fail("empty reviewed evidence inventory")
    if (values["source"] == "") {
      if (values["synced"] != "" || counts["files"]) fail("source-free baseline has source hashes or date")
    } else if (values["synced"] == "" || !counts["files"]) fail("missing source baseline")
  }
  if (values["source"] != "" && !path_ok(values["source"], 1)) fail("invalid source path")
  if (mode == "field") {
    if (field == "version") print version
    else print values[field]
  } else if (mode == "hashes") {
    for (i = 1; i <= n; i++) {
      split(order[i], pair, SUBSEP)
      if (pair[1] == field) print pair[2] "\t" hashes[order[i]]
    }
  }
}
