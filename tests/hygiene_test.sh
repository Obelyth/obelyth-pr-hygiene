#!/usr/bin/env bash
# Tests for every script that decides something: the title-to-label mapping,
# the size buckets, quarter milestone naming and due dates, the issue number a
# branch carries, closing-keyword detection, the placeholder gate that decides
# whether the describer runs, the guard that decides whether its output is
# applied, the label plan, the milestone plan, the project field lookup and
# the settings file - then the runners against a stubbed gh that answers the
# reads they make and refuses any call it does not know.
#
# No network: every script under test is a pure function of its arguments and
# its stdin, and the runner cases stub gh with a script on PATH.
#
# Bodies under test are quoted literally, backticks and all, and the runner
# checks are shell expressions handed to eval; neither is meant to expand.
# shellcheck disable=SC2016
set -uo pipefail
export LC_ALL=C.UTF-8
# No case may wait on a terminal: every script under test gets an empty stdin
# unless the case feeds it one.
exec < /dev/null

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/scripts"
PASS=0; FAIL=0
ok()  { printf '  ok    %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL  %s%s\n' "$1" "${2:+ ($2)}"; FAIL=$((FAIL+1)); }

SUITE_TMP="$(mktemp -d)" || exit 1
export TMPDIR="$SUITE_TMP"
trap 'rm -rf "$SUITE_TMP"' EXIT

# expect NAME EXPECTED COMMAND... : stdout must equal EXPECTED
expect() {
  local name="$1" want="$2"; shift 2
  local got; got="$("$@" 2> /dev/null)"
  if [[ "$got" == "$want" ]]; then ok "$name"; else bad "$name" "wanted '$want', got '$got'"; fi
}
# status NAME EXPECTED_RC COMMAND... : exit status must equal EXPECTED_RC
status() {
  local name="$1" want="$2"; shift 2
  "$@" > /dev/null 2>&1; local rc=$?
  if [[ "$rc" == "$want" ]]; then ok "$name"; else bad "$name" "wanted exit $want, got $rc"; fi
}
# status_in NAME EXPECTED_RC INPUT COMMAND... : same, with INPUT on stdin
status_in() {
  local name="$1" want="$2" input="$3"; shift 3
  "$@" > /dev/null 2>&1 <<< "$input"; local rc=$?
  if [[ "$rc" == "$want" ]]; then ok "$name"; else bad "$name" "wanted exit $want, got $rc"; fi
}
# yq on PATH and working: a version manager's shim that errors does not count.
have_yq() { yq --version > /dev/null 2>&1; }

echo "title -> type label"
expect "feat:"                       type/feat     bash "$S/type-label.sh" "feat: add passkeys"
expect "fix(scope):"                 type/fix      bash "$S/type-label.sh" "fix(auth): null user"
expect "feat!: (breaking)"           type/feat     bash "$S/type-label.sh" "feat!: drop node 18"
expect "fix(scope)!: (breaking)"     type/fix      bash "$S/type-label.sh" "fix(auth)!: rotate keys"
expect "docs:"                       type/docs     bash "$S/type-label.sh" "docs: runbook"
expect "ci:"                         type/ci       bash "$S/type-label.sh" "ci: pin actions"
expect "refactor:"                   type/refactor bash "$S/type-label.sh" "refactor: split parser"
expect "test:"                       type/test     bash "$S/type-label.sh" "test: cover leap years"
expect "perf:"                       type/perf     bash "$S/type-label.sh" "perf: cache lookups"
expect "Uppercase Fix: still fix"    type/fix      bash "$S/type-label.sh" "Fix: typo"
expect "no prefix -> chore"          type/chore    bash "$S/type-label.sh" "Update README"
expect "unknown prefix -> chore"     type/chore    bash "$S/type-label.sh" "feature: not a real type"
expect "build: is not in the scheme" type/chore    bash "$S/type-label.sh" "build: bump"
expect "prefix with no space after"  type/chore    bash "$S/type-label.sh" "docs:notes"
expect "feat inside the title only"  type/chore    bash "$S/type-label.sh" "Add feat: flag"
expect "empty title"                 type/chore    bash "$S/type-label.sh" ""

echo "diff size -> size label"
expect "0 -> XS"        size/XS bash "$S/size-label.sh" 0 0
expect "9 -> XS"        size/XS bash "$S/size-label.sh" 4 5
expect "10 -> S"        size/S  bash "$S/size-label.sh" 5 5
expect "49 -> S"        size/S  bash "$S/size-label.sh" 49 0
expect "50 -> M"        size/M  bash "$S/size-label.sh" 25 25
expect "199 -> M"       size/M  bash "$S/size-label.sh" 100 99
expect "200 -> L"       size/L  bash "$S/size-label.sh" 200 0
expect "499 -> L"       size/L  bash "$S/size-label.sh" 0 499
expect "500 -> XL"      size/XL bash "$S/size-label.sh" 250 250
expect "12000 -> XL"    size/XL bash "$S/size-label.sh" 12000 0
status "non-numbers are refused" 2 bash "$S/size-label.sh" ten 0

echo "date -> quarter milestone"
q() { bash "$S/quarter.sh" "$1" | paste -sd' '; }
expect "Jan 1 -> Q1, due Mar 31"        "title=Q1 2026 due=2026-03-31" q 2026-01-01T00:00:00Z
expect "Mar 31 -> Q1"                   "title=Q1 2026 due=2026-03-31" q 2026-03-31T23:59:59Z
expect "Apr 1 -> Q2, due Jun 30"        "title=Q2 2026 due=2026-06-30" q 2026-04-01T00:00:00Z
expect "Sep 17 -> Q3, due Sep 30"       "title=Q3 2026 due=2026-09-30" q 2026-09-17T10:11:12Z
expect "Sep 30 -> Q3"                   "title=Q3 2026 due=2026-09-30" q 2026-09-30T12:00:00Z
expect "Oct 1 -> Q4, due Dec 31"        "title=Q4 2026 due=2026-12-31" q 2026-10-01T00:00:00Z
expect "Dec 31 -> Q4 of the same year"  "title=Q4 2026 due=2026-12-31" q 2026-12-31T23:59:59Z
expect "leap day 2028 -> Q1 2028"       "title=Q1 2028 due=2028-03-31" q 2028-02-29T08:00:00Z
expect "Feb 28 2027 (not leap) -> Q1"   "title=Q1 2027 due=2027-03-31" q 2027-02-28T00:00:00Z
expect "a bare date works too"          "title=Q2 2029 due=2029-06-30" q 2029-05-05
status "month 13 is refused" 2 bash "$S/quarter.sh" 2026-13-01
status "month 00 is refused" 2 bash "$S/quarter.sh" 2026-00-15
status "day 32 is refused"   2 bash "$S/quarter.sh" 2026-01-32
status "day 00 is refused"   2 bash "$S/quarter.sh" 2026-01-00
status "garbage is refused"  2 bash "$S/quarter.sh" yesterday

echo "branch -> issue number"
expect "feat/12-passkeys"      12 bash "$S/branch-issue.sh" feat/12-passkeys
expect "12-passkeys"           12 bash "$S/branch-issue.sh" 12-passkeys
expect "hotfix/#7-null-user"   7  bash "$S/branch-issue.sh" "hotfix/#7-null-user"
expect "fix/12_underscore"     12 bash "$S/branch-issue.sh" fix/12_underscore
expect "a bare number"         42 bash "$S/branch-issue.sh" 42
expect "deep path feat/a/9-x"  9  bash "$S/branch-issue.sh" feat/a/9-x
expect "leading zeros 007-x"   7  bash "$S/branch-issue.sh" 007-x
expect "leading zeros 009-x (not octal)" 9  bash "$S/branch-issue.sh" 009-x
expect "leading zeros 010-x (not octal)" 10 bash "$S/branch-issue.sh" feat/010-x
expect "a word starting with a digit after it: 12-2fa" 12 bash "$S/branch-issue.sh" feat/12-2fa
expect "a year with the # is an issue: #2026-x" 2026 bash "$S/branch-issue.sh" "feat/#2026-x"
expect "a date with the # is an issue: #12-01-x" 12 bash "$S/branch-issue.sh" "feat/#12-01-x"
expect "four digits below the year range: 1899-x" 1899 bash "$S/branch-issue.sh" feat/1899-x
expect "four digits above the year range: 2100-x" 2100 bash "$S/branch-issue.sh" feat/2100-x
status "no number"             1 bash "$S/branch-issue.sh" feature/no-number
status "release/v1.2"          1 bash "$S/branch-issue.sh" release/v1.2
status "number mid-segment"    1 bash "$S/branch-issue.sh" feat/v2-launch
status "dependabot version"    1 bash "$S/branch-issue.sh" dependabot/npm_and_yarn/lodash-4.17.21
status "zero is not an issue"  1 bash "$S/branch-issue.sh" 0-nothing
status "empty"                 1 bash "$S/branch-issue.sh" ""
status "number not followed by -/_/end: 12abc" 1 bash "$S/branch-issue.sh" feat/12abc
status "release/2024.1"        1 bash "$S/branch-issue.sh" release/2024.1
status "a date: 2026-09-17-cleanup" 1 bash "$S/branch-issue.sh" chore/2026-09-17-cleanup
status "a version: 1-2-3"      1 bash "$S/branch-issue.sh" feat/1-2-3
status "digits then underscore digits: 1_2" 1 bash "$S/branch-issue.sh" 1_2
status "a year: release/2026-Q3" 1 bash "$S/branch-issue.sh" release/2026-Q3
status "a bare year"           1 bash "$S/branch-issue.sh" chore/2026

echo "body -> closing keyword"
for kw in close closes closed fix fixes fixed resolve resolves resolved; do
  status_in "$kw #12" 0 "This $kw #12" bash "$S/closing-keyword.sh"
done
status_in "RESOLVES #12 upper case"        0 "RESOLVES #12"                      bash "$S/closing-keyword.sh"
status_in "Close: #12 with a colon"        0 "Close: #12"                        bash "$S/closing-keyword.sh"
status_in "owner/repo#12"                  0 "Fixes o/r#12"                      bash "$S/closing-keyword.sh"
status_in "issue URL"                      0 "Resolves https://github.com/o/r/issues/12" bash "$S/closing-keyword.sh"
status_in "mid-paragraph, after newline"   0 $'Summary.\n\ncloses #3\nmore'      bash "$S/closing-keyword.sh"
status_in "no newline at the end"          0 "Fixes #9"                          bash "$S/closing-keyword.sh"
status_in "keyword without a number"       1 "This fixes the bug"                bash "$S/closing-keyword.sh"
status_in "number without a keyword"       1 "See #12"                           bash "$S/closing-keyword.sh"
status_in "prefixes is not a keyword"      1 "prefixes #12"                      bash "$S/closing-keyword.sh"
status_in "empty body"                     1 ""                                  bash "$S/closing-keyword.sh"
status_in "inside a code span"             1 'Use `closes #12` to link.'         bash "$S/closing-keyword.sh"
status_in "inside a double-backtick span"  1 'Use ``closes #12`` to link.'       bash "$S/closing-keyword.sh"
status_in "inside a fenced block"          1 $'Summary\n\n```\ncloses #12\n```'  bash "$S/closing-keyword.sh"
status_in "inside a ~~~ fenced block"      1 $'~~~md\nfixes #12\n~~~'            bash "$S/closing-keyword.sh"
status_in "inside an unclosed fence"       1 $'Summary\n```\nfixes #12'          bash "$S/closing-keyword.sh"
status_in "inside an HTML comment"         1 "<!-- closes #12 -->"               bash "$S/closing-keyword.sh"
status_in "inside a multi-line HTML comment" 1 $'<!-- note\ncloses #12\n-->'     bash "$S/closing-keyword.sh"
status_in "inside an unclosed HTML comment" 1 $'<!-- note\ncloses #12'          bash "$S/closing-keyword.sh"
status_in "real one outside, example inside" 0 $'Closes #12\n\n```\nfixes #13\n```' bash "$S/closing-keyword.sh"
status_in "after a comment, outside it"    0 $'<!-- reviewer note -->\nfixes #4' bash "$S/closing-keyword.sh"
status_in "after a fenced block, outside it" 0 $'```\nsh\n```\nfixes #4'         bash "$S/closing-keyword.sh"
status_in "for #12: Closes #12"            0 "Closes #12"                        bash "$S/closing-keyword.sh" 12
status_in "for #12: Closes #120 is not it" 1 "Closes #120"                       bash "$S/closing-keyword.sh" 12
status_in "for #12: Closes #13 is not it"  1 "Closes #13"                        bash "$S/closing-keyword.sh" 12
status_in "for #12: closes #12, then more" 0 "closes #12, and #13"               bash "$S/closing-keyword.sh" 12
status_in "for #12: URL form"              0 "Fixes https://github.com/o/r/issues/12" bash "$S/closing-keyword.sh" 12
status_in "for #12: in a code span is not it" 1 'Try `closes #12`'               bash "$S/closing-keyword.sh" 12
status "for #x: not a number is refused"   2 bash "$S/closing-keyword.sh" twelve

echo "body -> placeholder gate (exit 0 = the describer runs)"
tpl="$(cat "$ROOT/templates/pull_request_template.md")"
status_in "the untouched template"                  0 "$tpl"                        bash "$S/placeholder.sh"
status_in "empty body"                              0 ""                            bash "$S/placeholder.sh"
status_in "whitespace only"                         0 $'  \n\t\n'                   bash "$S/placeholder.sh"
status_in "one placeholder left among written text" 0 $'## Summary\n\nDone.\n\n## Why\n\n<!-- pr-hygiene: why. -->' bash "$S/placeholder.sh"
status_in "marker case does not matter"             0 "<!-- PR-Hygiene: summary -->" bash "$S/placeholder.sh"
status_in "a written body"                          1 $'## Summary\n\nAdds passkeys.\n\n## Why\n\nAsked for.' bash "$S/placeholder.sh"
status_in "an ordinary HTML comment is not a marker" 1 "Adds passkeys. <!-- reviewer: see the auth module -->" bash "$S/placeholder.sh"
status_in "the marker quoted inside a sentence is not one" 1 "Fills the \`<!-- pr-hygiene: ... -->\` comments from the diff." bash "$S/placeholder.sh"
status_in "the marker indented at the start of a line is one" 0 $'## Why\n\n  <!-- pr-hygiene: why. -->' bash "$S/placeholder.sh"
status_in "the app-starter template has no markers" 1 $'## What & why\n\n## How to test\n\n- **Steps:** 1.' bash "$S/placeholder.sh"

echo "body guard (exit 0 = apply, 3 = unchanged, 1 = rejected)"
guard() {  # name expected_rc old new
  local d; d="$(mktemp -d)"
  printf '%s' "$3" > "$d/old"; printf '%s' "$4" > "$d/new"
  status "$1" "$2" bash "$S/body-guard.sh" "$d/old" "$d/new"
}
ph_summary='<!-- pr-hygiene: summary. What this changes, in a sentence or two. Leave this comment in place and PR Hygiene writes it from the diff. -->'
ph_why='<!-- pr-hygiene: why. The problem or request this answers. -->'
ph_test='<!-- pr-hygiene: test-plan. How it was verified: commands run, what was checked by hand, what was not. -->'
filled="${tpl//$ph_summary/Adds passkey sign-in next to passwords.}"
filled="${filled//$ph_why/Passwords alone were the top support ticket.}"
filled="${filled//$ph_test/- unit tests for the WebAuthn flow are in the diff
- the browser flow has not been exercised here}"
guard "all three placeholders filled"            0 "$tpl" "$filled"
guard "one placeholder left in place"            0 "$tpl" "${tpl//$ph_summary/Adds passkeys.}"
guard "nothing changed"                          3 "$tpl" "$tpl"
guard "a heading was renamed"                    1 "$tpl" "${filled//## Why/## Motivation}"
guard "a heading was deleted"                    1 "$tpl" "${filled//## Test plan/}"
guard "a checklist item was ticked"              1 "$tpl" "${filled//- \[ \] CI is green/- [x] CI is green}"
guard "text appended after the checklist"        1 "$tpl" "$filled"$'\n\nAlso rewrote the roadmap.'
guard "text inserted before the first heading"   1 "$tpl" "Hi! $filled"
guard "a human sentence was reworded"            1 $'## Summary\n\nWe use OAuth.\n\n## Why\n\n<!-- pr-hygiene: why. -->' $'## Summary\n\nWe use OIDC.\n\n## Why\n\nBecause.'
guard "a human sentence kept, placeholder filled" 0 $'## Summary\n\nWe use OAuth.\n\n## Why\n\n<!-- pr-hygiene: why. -->' $'## Summary\n\nWe use OAuth.\n\n## Why\n\nBecause.'
guard "a heading's case changed"                 1 $'## Why\n\n<!-- pr-hygiene: why. -->' $'## why\n\nBecause.'
guard "a human HTML comment is kept"             0 $'<!-- keep me -->\n<!-- pr-hygiene: summary. -->\n\nEnd' $'<!-- keep me -->\nWritten.\n\nEnd'
guard "a human HTML comment removed"             1 $'<!-- keep me -->\n<!-- pr-hygiene: summary. -->\n\nEnd' $'Written.\n\nEnd'
guard "empty body may become anything"           0 "" "Adds passkeys."
guard "empty body may not stay empty"            1 "" $'  \n'
guard "CRLF current body, LF new body"           0 "${tpl//$'\n'/$'\r\n'}" "$filled"
guard "a body with no placeholder is not touched" 1 "Written by hand." "Rewritten by a model."
mention="Fills the \`<!-- pr-hygiene: summary. -->\` comments."$'\n\n## Why\n\n<!-- pr-hygiene: why. -->'
guard "a quoted marker is kept, the real one filled"  0 "$mention" "Fills the \`<!-- pr-hygiene: summary. -->\` comments."$'\n\n## Why\n\nBecause.'
guard "a quoted marker rewritten is rejected"         1 "$mention" $'Fills the placeholder comments.\n\n## Why\n\nBecause.'
guard "a quoted marker's text rewritten in place, all else identical, is rejected" 1 "$mention" 'Fills the `<!-- rewritten -->` comments.'$'\n\n## Why\n\nBecause.'
guard "a body whose only marker is quoted is not touched" 1 "Fills the \`<!-- pr-hygiene: summary. -->\` comments." "Fills them."
guard "only-quoted body, marker text rewritten in place, is not touched" 1 'Fills the `<!-- pr-hygiene: summary. -->` comments.' 'Fills the `anything` comments.'
guard "an indented placeholder is filled"        0 $'## Why\n\n  <!-- pr-hygiene: why. -->' $'## Why\n\n  Because.'
guard "an upper-case marker is a placeholder too" 0 $'## Why\n\n<!-- PR-Hygiene: why. -->' $'## Why\n\nBecause.'
guard "a marker containing -> is one placeholder" 0 $'## Why\n\n<!-- pr-hygiene: why -> see below -->\n\nEnd' $'## Why\n\nBecause.\n\nEnd'
guard "a marker with no --> runs to the end"     0 $'## Why\n\n<!-- pr-hygiene: why.' $'## Why\n\nBecause.'
guard "a placeholder at the very end is filled"  0 $'## Why\n\n<!-- pr-hygiene: why. -->' $'## Why\n\nBecause.'
guard "a placeholder at the very end left in place" 3 $'## Why\n\n<!-- pr-hygiene: why. -->' $'## Why\n\n<!-- pr-hygiene: why. -->'
guard "the first filled, the last left in place"  0 $'## Summary\n\n<!-- pr-hygiene: summary. -->\n\n## Why\n\n<!-- pr-hygiene: why. -->' $'## Summary\n\nAdds x.\n\n## Why\n\n<!-- pr-hygiene: why. -->'
guard "a placeholder replaced by a different marker" 1 $'## Why\n\n<!-- pr-hygiene: why. -->' $'## Why\n\n<!-- pr-hygiene: summary. -->'
echo "body guard: what a placeholder may not be filled with"
guard "an HTML comment in a slot"                1 "$tpl" "${tpl//$ph_summary/<!-- }"
guard "a closed HTML comment in a slot"          1 "$tpl" "${tpl//$ph_summary/Adds x. <!-- hidden -->}"
guard "an unclosed \`\`\` fence in a slot"       1 "$tpl" "${tpl//$ph_summary/Run:$'\n'\`\`\`sh$'\n'make}"
guard "an unclosed ~~~ fence in a slot"          1 "$tpl" "${tpl//$ph_summary/Run:$'\n'~~~$'\n'make}"
guard "a closed fence in a slot is fine"         0 "$tpl" "${tpl//$ph_test/Run:$'\n'\`\`\`sh$'\n'make test$'\n'\`\`\`}"
guard "Closes #n in a slot"                      1 "$tpl" "${tpl//$ph_summary/Adds x. Closes #999}"
guard "fixes owner/repo#n in a slot"             1 "$tpl" "${tpl//$ph_summary/Adds x. fixes o/r#999}"
guard "resolves an issue URL in a slot"          1 "$tpl" "${tpl//$ph_summary/Resolves https://github.com/o/r/issues/9}"
guard "a keyword without a number is fine"       0 "$tpl" "${tpl//$ph_summary/Fixes the null user crash.}"
guard "an @mention in a slot"                    1 "$tpl" "${tpl//$ph_summary/@ShootJackal please look}"
guard "an @mention mid-sentence in a slot"       1 "$tpl" "${tpl//$ph_summary/Asked by @alice.}"
guard "an email address is not a mention"        0 "$tpl" "${tpl//$ph_summary/Contact ops@example.com.}"
guard "an Anthropic key shape in a slot"         1 "$tpl" "${tpl//$ph_summary/Uses sk-ant-api03-abc.}"
guard "a GitHub token shape in a slot"           1 "$tpl" "${tpl//$ph_summary/Token ghs_abc123.}"
guard "a fine-grained PAT shape in a slot"       1 "$tpl" "${tpl//$ph_summary/github_pat_11AAA.}"
guard "the slot at the end is checked too"       1 $'## Why\n\n<!-- pr-hygiene: why. -->' $'## Why\n\nBecause. @bob'
guard "an empty body gets the same checks"       1 "" "Adds passkeys. @bob"
guard "an empty body may not close an issue"     1 "" "Adds passkeys. Closes #1"

echo "label plan"
jq -r '.[].name | select(startswith("type/") or startswith("size/"))' "$ROOT/labels/labels.json" > "$SUITE_TMP/own"
printf 'type/feat\ntype/fix\n' > "$SUITE_TMP/own-fewer"   # as if labeler.yml owned every other type/*
plan2() {  # name expected ns want labels events [own-file]
  local d; d="$(mktemp -d)"
  printf '%s\n' "$5" > "$d/labels"; printf '%s\n' "$6" > "$d/events"
  expect "$1" "$2" bash "$S/label-plan.sh" "$3" "$4" "$d/labels" "$d/events" "${7:-$SUITE_TMP/own}"
}
plan2 "no labels yet -> add"                          "add=type/feat"                type type/feat "" ""
plan2 "already right -> nothing"                      ""                             type type/feat "type/feat" $'labeled\ttype/feat\tgithub-actions[bot]'
plan2 "bot's stale label -> replaced"                 $'remove=type/fix\nadd=type/feat' type type/feat "type/fix" $'labeled\ttype/fix\tgithub-actions[bot]'
plan2 "person's label -> kept, ours not added"        "note=type/docs was set by a person or another tool, so type/feat was not added over it" type type/feat "type/docs" $'labeled\ttype/docs\tkeith'
plan2 "label with no event history -> treated as a person's" "note=type/docs was set by a person or another tool, so type/feat was not added over it" type type/feat "type/docs" ""
plan2 "person's and bot's stale together"             $'remove=size/S\nnote=size/XL was set by a person or another tool, so size/M was not added over it' size size/M $'size/S\nsize/XL' $'labeled\tsize/S\tgithub-actions[bot]\nlabeled\tsize/XL\tkeith'
plan2 "other namespaces are ignored"                  "add=size/M"                   size size/M $'type/feat\nsecurity' $'labeled\ttype/feat\tgithub-actions[bot]\nlabeled\tsecurity\tkeith'
plan2 "the last labeled event wins"                   $'remove=type/fix\nadd=type/feat' type type/feat "type/fix" $'labeled\ttype/fix\tkeith\nunlabeled\ttype/fix\tkeith\nlabeled\ttype/fix\tgithub-actions[bot]'
plan2 "bot's label outside the scheme -> not ours, kept" "note=type/experimental was set by a person or another tool, so type/feat was not added over it" type type/feat "type/experimental" $'labeled\ttype/experimental\tgithub-actions[bot]'
plan2 "bot's label that labeler.yml owns -> kept"     "note=type/docs was set by a person or another tool, so type/feat was not added over it" type type/feat "type/docs" $'labeled\ttype/docs\tgithub-actions[bot]' "$SUITE_TMP/own-fewer"
printf 'size/M\nsize/L, XL\n' > "$SUITE_TMP/own-comma"
plan2 "a comma in a label name survives"              $'remove=size/L, XL\nadd=size/M' size size/M "size/L, XL" $'labeled\tsize/L, XL\tgithub-actions[bot]' "$SUITE_TMP/own-comma"
status "the own-list file is required"                2 bash "$S/label-plan.sh" type type/feat /dev/null /dev/null

echo "milestone plan"
mplan() {  # name expected policy created current milestones-json
  expect "$1" "$2" env POLICY="$3" CREATED_AT="$4" CURRENT="$5" bash "$S/milestone-plan.sh" <<< "$6"
}
mplan "quarter, missing -> create with due date"  $'action=create\ntitle=Q3 2026\ndue=2026-09-30' quarter 2026-09-17T00:00:00Z "" '[]'
mplan "quarter, exists open -> assign"            $'action=assign\ntitle=Q3 2026\nnumber=4'        quarter 2026-09-17T00:00:00Z "" '[{"title":"Q3 2026","state":"open","number":4}]'
mplan "quarter, exists closed -> skip, not reopened" $'action=skip\nreason=milestone \'Q3 2026\' is closed and is not reopened' quarter 2026-09-17T00:00:00Z "" '[{"title":"Q3 2026","state":"closed","number":4}]'
mplan "already has one -> skip"                   $'action=skip\nreason=already on milestone \'Launch\'' quarter 2026-09-17T00:00:00Z "Launch" '[]'
mplan "policy none -> skip"                       $'action=skip\nreason=milestone policy is none' none 2026-09-17T00:00:00Z "" '[]'
mplan "literal title, exists -> assign"           $'action=assign\ntitle=Launch\nnumber=9'         Launch 2026-09-17T00:00:00Z "" '[{"title":"Launch","state":"open","number":9}]'
mplan "literal title, missing -> skip, not created" $'action=skip\nreason=milestone \'Launch\' does not exist in this repository' Launch 2026-09-17T00:00:00Z "" '[]'
mplan "Dec 31 -> Q4 create"                       $'action=create\ntitle=Q4 2026\ndue=2026-12-31'  quarter 2026-12-31T23:00:00Z "" '[]'
mplan "empty stdin is an empty list"              $'action=create\ntitle=Q3 2026\ndue=2026-09-30' quarter 2026-09-17T00:00:00Z "" ''

echo "project field lookup"
fields='[{"id":"F1","name":"Status","options":[{"id":"O1","name":"Todo"},{"id":"O2","name":"In Progress"},{"id":"O3","name":"Done"}]},{"id":"F2","name":"Priority","options":[{"id":"P1","name":"High"}]}]'
expect "Status / In Progress"        $'field_id=F1\noption_id=O2' bash "$S/project-fields.sh" Status "In Progress" <<< "$fields"
expect "Status / Done"               $'field_id=F1\noption_id=O3' bash "$S/project-fields.sh" Status Done <<< "$fields"
expect "case does not matter: In progress" $'field_id=F1\noption_id=O2' bash "$S/project-fields.sh" Status "In progress" <<< "$fields"
expect "case does not matter: status / DONE" $'field_id=F1\noption_id=O3' bash "$S/project-fields.sh" status DONE <<< "$fields"
status_in "missing option -> exit 4" 4 "$fields" bash "$S/project-fields.sh" Status Cancelled
status_in "missing field -> exit 1"  1 "$fields" bash "$S/project-fields.sh" Stage Done
status_in "a field without options is a missing option" 4 '[{"id":"F9","name":"Status"}]' bash "$S/project-fields.sh" Status Done

echo "settings file"
if have_yq; then
  cfg() { bash "$S/config.sh" "$1" | paste -sd' '; }
  defaults_obelyth="milestone=quarter reviewers= copilot_review=false project_owner=Obelyth project_number=1 project_status_field=Status project_status_opened=In Progress project_status_merged=Done project_status_closed=remove"
  defaults="milestone=quarter reviewers= copilot_review=false project_owner= project_number=0 project_status_field=Status project_status_opened=In Progress project_status_merged=Done project_status_closed=remove"
  expect "the shipped template is all defaults" "$defaults_obelyth" cfg "$ROOT/templates/pr-hygiene.yml"
  expect "no file is all defaults"              "$defaults" cfg "$SUITE_TMP/does-not-exist.yml"
  printf '# settings\n# milestone: quarter\n' > "$SUITE_TMP/comments.yml"
  expect "a file of only comments is all defaults" "$defaults" cfg "$SUITE_TMP/comments.yml"
  printf -- '---\n' > "$SUITE_TMP/dashes.yml"
  expect "a bare --- is all defaults"           "$defaults" cfg "$SUITE_TMP/dashes.yml"
  printf 'milestone: Q4 2026\nreviewers: [alice, bob]\ncopilot_review: true\nproject:\n  owner: ShootJackal\n  number: 3\n  status:\n    closed: Cancelled\n' > "$SUITE_TMP/cfg.yml"
  expect "every key read, the rest defaulted" \
    "milestone=Q4 2026 reviewers=alice,bob copilot_review=true project_owner=ShootJackal project_number=3 project_status_field=Status project_status_opened=In Progress project_status_merged=Done project_status_closed=Cancelled" \
    cfg "$SUITE_TMP/cfg.yml"
  printf 'reviewers: alice\n' > "$SUITE_TMP/one.yml"
  expect "a single login is a one-element list" "${defaults/reviewers=/reviewers=alice}" cfg "$SUITE_TMP/one.yml"
  printf 'project:\n  number: three\n' > "$SUITE_TMP/bad.yml"
  status "a non-numeric project number is refused" 2 bash "$S/config.sh" "$SUITE_TMP/bad.yml"
  printf 'copilot_review: maybe\n' > "$SUITE_TMP/copilot.yml"
  status "copilot_review must be true or false"    2 bash "$S/config.sh" "$SUITE_TMP/copilot.yml"
  printf 'milestone: ""\n' > "$SUITE_TMP/empty-ms.yml"
  status "an empty milestone is refused"           2 bash "$S/config.sh" "$SUITE_TMP/empty-ms.yml"
  printf 'milestone: [\n' > "$SUITE_TMP/broken.yml"
  status "unparsable YAML is refused"              2 bash "$S/config.sh" "$SUITE_TMP/broken.yml"
  printf 'just a string\n' > "$SUITE_TMP/scalar.yml"
  status "a document that is not a mapping is refused" 2 bash "$S/config.sh" "$SUITE_TMP/scalar.yml"
  printf 'milestone: |\n  Q4 2026\n  proceed=true\n' > "$SUITE_TMP/multiline.yml"
  status "a multi-line value is refused (it would forge outputs)" 2 bash "$S/config.sh" "$SUITE_TMP/multiline.yml"
else
  echo "  skip  yq is not installed here; the settings cases run in CI"
fi

# --- runners against a stubbed gh, so the wiring is exercised too -------
echo "runners with a stubbed gh"
stub="$(mktemp -d)"; mkdir -p "$stub/bin"
cat > "$stub/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Records every call; answers the reads the runners make, from STUB_* when
# set; refuses anything it does not know, so a changed or dropped read is a
# failure rather than a silent pass.
printf '%s\n' "$*" >> "$STUB_LOG"
tpl_diff=$'diff --git a/a.txt b/a.txt\n--- a/a.txt\n+++ b/a.txt\n@@ -1 +1 @@\n-old\n+new\n'
board='[{"id":"F1","name":"Status","options":[{"id":"O1","name":"Todo"},{"id":"O2","name":"In Progress"},{"id":"O3","name":"Done"}]}]'
issue12='{"number":12,"state":"open","title":"Passkeys"}'
case "$*" in
  "pr view 5 --repo o/r --json milestone --jq .milestone.title // empty") printf '%s\n' "${STUB_MILESTONE:-}" ;;
  "api --paginate repos/o/r/milestones?state=all&per_page=100 --jq .[] | {title, state, number}") echo '{"title":"Q1 2026","state":"closed","number":1}' ;;
  "pr view 5 --repo o/r --json body --jq .body") printf '%s\n' "${STUB_BODY-Summary.}" ;;
  'pr view 5 --repo o/r --json body --jq .body // ""') printf '%s\n' "${STUB_BODY-Summary.}" ;;
  "pr view 5 --repo o/r --json title,body") jq -cn --arg t "${STUB_TITLE:-feat: passkeys}" --arg b "${STUB_BODY-Summary.}" '{title: $t, body: $b}' ;;
  "pr view 5 --repo o/r --json title,additions,deletions,labels") jq -cn --arg t "${STUB_TITLE:-feat: passkeys}" --argjson l "${STUB_LABELS:-[]}" '{title: $t, additions: 3, deletions: 1, labels: $l}' ;;
  "api --paginate repos/o/r/issues/5/events --jq "*) printf '%s' "${STUB_EVENTS:-}" ;;
  "api repos/o/r/contents/.github/labeler.yml --jq .content") [[ -n "${STUB_LABELER:-}" ]] || exit 1; printf '%s' "$STUB_LABELER" | base64 -w0 ;;
  "api repos/o/r/issues/12") printf '%s\n' "${STUB_ISSUE_12:-$issue12}" ;;
  "api repos/o/r/issues/13") echo '{"number":13,"state":"closed","title":"Old"}' ;;
  "api repos/o/r/issues/77") exit 1 ;;
  "api --paginate repos/o/r/pulls/5/files --jq .[].filename") printf 'a.txt\nb.bin\n' ;;
  "api --paginate repos/o/r/pulls/5/files --jq .[] | "*) printf '%s\n' "$tpl_diff"; printf 'diff --git a/b.bin b/b.bin\n--- a/b.bin\n+++ b/b.bin\n[no patch: binary or too large]\n\n' ;;
  "pr diff 5 --repo o/r")
    if [[ "${STUB_DIFF_FAILS:-false}" == true ]]; then
      echo "HTTP 406: Sorry, the diff exceeded the maximum number of files (300)" >&2; exit 1
    fi
    printf '%s' "$tpl_diff" ;;
  "pr edit 5 --repo o/r --body-file -") cat > "$STUB_SENT_BODY" ;;
  "pr edit 5 --repo o/r --body-file "*) cp "${@: -1}" "$STUB_SENT_BODY" ;;
  "pr edit 5 --repo o/r --add-reviewer ghost") exit 1 ;;
  "pr edit 5 --repo o/r --add-reviewer "*) : ;;
  "pr edit 5 --repo o/r --milestone "*) : ;;
  "pr edit 5 --repo o/r --add-label "*|"pr edit 5 --repo o/r --remove-label "*) : ;;
  "api -X POST repos/o/r/milestones "*) : ;;
  "api -X POST repos/o/r/pulls/5/requested_reviewers "*) : ;;
  # Projects v2, as project-sync.sh asks: the owner's kind, the board with its
  # fields, the pull request's item on it, the item's current status, then one
  # mutation - set a field or delete the item.
  "api users/Obelyth --jq .type") echo Organization ;;
  "api graphql -F login=Obelyth -F number=3 -f query="*)
    jq -cn --argjson f "${STUB_FIELDS:-$board}" '{data: {organization: {projectV2: {id: "P1", fields: {nodes: ([{}] + $f)}}}}}' ;;
  "api graphql -F id=PR_1 -f query="*)
    if [[ "${STUB_ON_BOARD:-true}" == true ]]; then echo '{"data":{"node":{"projectItems":{"nodes":[{"id":"I1","project":{"id":"P1"}},{"id":"I9","project":{"id":"P9"}}]}}}}'
    else echo '{"data":{"node":{"projectItems":{"nodes":[]}}}}'; fi ;;
  "api graphql -F id=I1 -F field="*)
    if [[ -n "${STUB_STATUS:-}" ]]; then jq -cn --arg n "$STUB_STATUS" '{data: {node: {fieldValueByName: {name: $n}}}}'
    else echo '{"data":{"node":{"fieldValueByName":null}}}'; fi ;;
  "api graphql -F project=P1 -F item=I1 -F field="*) echo '{"data":{"updateProjectV2ItemFieldValue":{"projectV2Item":{"id":"I1"}}}}' ;;
  "api graphql -F project=P1 -F item=I1 -f query="*) echo '{"data":{"deleteProjectV2Item":{"deletedItemId":"I1"}}}' ;;
  *) echo "unexpected gh call: $*" >&2; exit 99 ;;
esac
exit 0
STUB
chmod +x "$stub/bin/gh"
export STUB_LOG="$stub/log" STUB_SENT_BODY="$stub/sent-body"

# runner SCRIPT : runs it with the stub on PATH; STUB_* come from the caller's
# environment. Leaves the call log, stdout+stderr, the exit status and the
# body last sent to gh in $stub.
runner() {
  : > "$STUB_LOG"; : > "$STUB_SENT_BODY"
  PATH="$stub/bin:$PATH" REPO=o/r PR_NUMBER=5 GITHUB_STEP_SUMMARY="$stub/summary" \
    bash "$S/$1" > "$stub/out" 2>&1
  echo $? > "$stub/rc"
}
logged()     { grep -qF -- "$1" "$STUB_LOG"; }
said()       { grep -qF -- "$1" "$stub/out"; }
exited()     { [[ "$(cat "$stub/rc")" == "$1" ]]; }
check() {  # name condition... : the condition is a shell expression in a string
  if eval "$2"; then ok "$1"; else bad "$1"; sed 's/^/          /' "$stub/out" | head -6; sed 's/^/          gh /' "$STUB_LOG" | head -6; fi
}

POLICY=quarter CREATED_AT=2026-09-17T00:00:00Z runner milestone.sh
check "milestone runner creates Q3 2026 with its due date, then assigns it" \
  'exited 0 && logged "api -X POST repos/o/r/milestones -f title=Q3 2026 -f due_on=2026-09-30T07:00:00Z" && logged "pr edit 5 --repo o/r --milestone Q3 2026"'
STUB_MILESTONE="Launch" POLICY=quarter CREATED_AT=2026-09-17T00:00:00Z runner milestone.sh
check "milestone runner leaves a pull request that already has one alone" \
  'exited 0 && ! logged "pr edit" && ! logged "api -X POST" && said "already on milestone"'

HEAD_REF=feat/12-passkeys runner link-issue.sh
check "link runner appends Closes #12 to the body, and only appends" \
  'exited 0 && logged "pr edit 5 --repo o/r --body-file -" && [[ "$(cat "$STUB_SENT_BODY")" == $'"'"'Summary.\n\nCloses #12'"'"' ]]'
STUB_BODY="" HEAD_REF=feat/12-passkeys runner link-issue.sh
check "link runner writes just Closes #12 into an empty body" \
  'exited 0 && [[ "$(cat "$STUB_SENT_BODY")" == "Closes #12" ]]'
STUB_BODY="Closes #12" HEAD_REF=feat/12-passkeys runner link-issue.sh
check "link runner leaves a body that already closes an issue alone" \
  'exited 0 && ! logged "pr edit" && ! logged "api repos/o/r/issues" && said "already closes"'
STUB_BODY='See `closes #12` for the syntax.' HEAD_REF=feat/12-passkeys runner link-issue.sh
check "link runner is not fooled by a keyword in a code span" \
  'exited 0 && logged "pr edit 5 --repo o/r --body-file -" && [[ "$(cat "$STUB_SENT_BODY")" == *"Closes #12" ]]'
STUB_ISSUE_12='{"number":12,"state":"open","title":"Not an issue","pull_request":{"url":"x"}}' HEAD_REF=feat/12-passkeys runner link-issue.sh
check "link runner leaves a number that is a pull request alone" \
  'exited 0 && ! logged "pr edit" && said "pull request"'
HEAD_REF=feat/13-old runner link-issue.sh
check "link runner leaves a closed issue alone" 'exited 0 && ! logged "pr edit" && said "closed"'
HEAD_REF=feat/77-ghost runner link-issue.sh
check "link runner leaves a number that is not an issue alone" 'exited 0 && ! logged "pr edit" && said "no such issue"'
HEAD_REF=feat/no-number runner link-issue.sh
check "link runner makes no call at all when the branch has no number" 'exited 0 && [[ ! -s "$STUB_LOG" ]]'
HEAD_REF=chore/2026-09-17-cleanup runner link-issue.sh
check "link runner makes no call for a date-shaped branch" 'exited 0 && [[ ! -s "$STUB_LOG" ]]'

AUTHOR=ShootJackal REVIEWERS=shootjackal,alice COPILOT=false runner reviewers.sh
check "reviewers runner skips the author whatever the case, requests the rest" \
  'exited 0 && logged "pr edit 5 --repo o/r --add-reviewer alice" && ! logged "shootjackal" && said "requested alice"'
AUTHOR=keith REVIEWERS=ghost,alice,bob COPILOT=false runner reviewers.sh
check "reviewers runner requests one at a time, so a bad login drops nobody else" \
  'exited 0 && logged "--add-reviewer alice" && logged "--add-reviewer bob" && said "could not request ghost" && said "requested alice bob"'
AUTHOR=keith REVIEWERS="" COPILOT=true runner reviewers.sh
check "reviewers runner asks for Copilot when enabled and nothing else" \
  'exited 0 && logged "api -X POST repos/o/r/pulls/5/requested_reviewers -f reviewers[]=copilot-pull-request-reviewer[bot]" && ! logged "pr edit"'

STUB_LABELS='[]' STUB_EVENTS='' runner labels-apply.sh
check "labels runner adds type/feat and size/XS, one flag each" \
  'exited 0 && logged "pr edit 5 --repo o/r --add-label type/feat --add-label size/XS"'
STUB_LABELS='[{"name":"type/fix"},{"name":"size/XS"}]' STUB_EVENTS=$'labeled\ttype/fix\tgithub-actions[bot]\nlabeled\tsize/XS\tgithub-actions[bot]\n' runner labels-apply.sh
check "labels runner swaps its own stale type/* and keeps a right size/*" \
  'exited 0 && logged "pr edit 5 --repo o/r --add-label type/feat --remove-label type/fix"'
STUB_LABELS='[{"name":"type/docs"},{"name":"size/XS"}]' STUB_EVENTS=$'labeled\ttype/docs\tkeith\n' runner labels-apply.sh
check "labels runner never removes a person's label, makes no edit" \
  'exited 0 && ! logged "pr edit" && said "set by a person"'
if have_yq; then
  STUB_LABELS='[{"name":"type/docs"}]' STUB_EVENTS=$'labeled\ttype/docs\tgithub-actions[bot]\n' \
    STUB_LABELER=$'type/docs:\n  - changed-files:\n      - any-glob-to-any-file: "docs/**"\n' runner labels-apply.sh
  check "labels runner leaves a label that labeler.yml owns, though the bot set it" \
    'exited 0 && logged "api repos/o/r/contents/.github/labeler.yml" && logged "pr edit 5 --repo o/r --add-label size/XS" && ! logged "remove-label" && said "another tool"'
else
  echo "  skip  yq is not installed here; the labeler.yml case runs in CI"
fi

prep="$stub/prep"; rm -rf "$prep"; mkdir -p "$prep"
STUB_BODY="$tpl" OUT_DIR="$prep" GITHUB_OUTPUT="$prep/gho" runner describe-prepare.sh
check "describe-prepare says needed=true for the template and gathers the diff" \
  'exited 0 && grep -qx "needed=true" "$prep/gho" && [[ "$(cat "$prep/files.txt")" == $'"'"'a.txt\nb.bin'"'"' ]] && grep -q "^+new" "$prep/diff.patch" && cmp -s <(printf "%s\n" "$tpl") "$prep/current.md"'
rm -rf "$prep"; mkdir -p "$prep"
STUB_BODY="$tpl" STUB_DIFF_FAILS=true OUT_DIR="$prep" GITHUB_OUTPUT="$prep/gho" runner describe-prepare.sh
check "describe-prepare assembles the diff from the files API when gh pr diff answers 406" \
  'exited 0 && grep -qx "needed=true" "$prep/gho" && head -1 "$prep/diff.patch" | grep -q "could not fetch" && grep -q "^+new" "$prep/diff.patch" && grep -q "b.bin" "$prep/diff.patch"'
rm -rf "$prep"; mkdir -p "$prep"
STUB_BODY="Written by hand." OUT_DIR="$prep" GITHUB_OUTPUT="$prep/gho" runner describe-prepare.sh
check "describe-prepare says needed=false for a written body and fetches no diff" \
  'exited 0 && grep -qx "needed=false" "$prep/gho" && ! logged "pr diff" && ! logged "pulls/5/files"'

apply="$stub/apply"; rm -rf "$apply"; mkdir -p "$apply"
printf '%s\n' "$tpl" > "$apply/current.md"; printf '%s\n' "$filled" > "$apply/body.md"
STUB_BODY="$tpl" OUT_DIR="$apply" runner describe-apply.sh
check "describe-apply puts a body that passes the guard on the pull request" \
  'exited 0 && logged "pr edit 5 --repo o/r --body-file " && cmp -s <(printf "%s\n" "$filled") "$STUB_SENT_BODY" && said "filled in"'
STUB_BODY="$tpl"$'\n\nI typed this while the model was running.' OUT_DIR="$apply" runner describe-apply.sh
check "describe-apply discards the proposal when the body moved while the model ran" \
  'exited 0 && logged "pr view 5 --repo o/r --json body" && ! logged "pr edit" && said "edited while"'
printf '%s\n' "${filled//## Why/## Motivation}" > "$apply/body.md"
STUB_BODY="$tpl" OUT_DIR="$apply" runner describe-apply.sh
check "describe-apply discards a body the guard rejects" \
  'exited 0 && ! logged "pr edit" && said "discarded"'
: > "$apply/body.md"
STUB_BODY="$tpl" OUT_DIR="$apply" runner describe-apply.sh
check "describe-apply does nothing when the model wrote nothing" \
  'exited 0 && [[ ! -s "$STUB_LOG" ]] && said "no description was produced"'

# project-sync.sh against a stubbed board: Todo / In Progress / Done, the way
# GitHub's own template makes one.
psync() {  # env... -> runner project-sync.sh with the board's constants
  PROJECT_OWNER=Obelyth PROJECT_NUMBER=3 PR_NODE_ID=PR_1 ITEM_ID="" STATUS_FIELD=Status runner project-sync.sh
}
set_to() { logged "api graphql -F project=P1 -F item=I1 -F field=F1 -F option=$1 -f query="; }
removed() { logged "api graphql -F project=P1 -F item=I1 -f query="; }
EVENT_ACTION=opened MERGED=false psync
check "projects: opened with no status yet -> the default, In Progress" \
  'exited 0 && set_to O2 && said "set to '"'"'In Progress'"'"'"'
STATUS_OPENED="in progress" EVENT_ACTION=opened MERGED=false psync
check "projects: the settings and the board need not agree on case" 'exited 0 && set_to O2'
STUB_STATUS=Todo EVENT_ACTION=opened MERGED=false psync
check "projects: a status a person set is kept" 'exited 0 && ! logged "-F option=" && said "left where it is"'
STATUS_OPENED=Backlog EVENT_ACTION=opened MERGED=false psync
check "projects: a status the board does not have is a notice, not a failure" \
  'exited 0 && ! logged "-F option=" && said "no option named '"'"'Backlog'"'"'"'
STATUS_MERGED=Done EVENT_ACTION=closed MERGED=true psync
check "projects: merged -> Done" 'exited 0 && set_to O3 && ! logged "-F field=Status -f query="'
STATUS_CLOSED=remove EVENT_ACTION=closed MERGED=false psync
check "projects: closed without merging -> off the board" 'exited 0 && removed && ! logged "-F option=" && said "removed"'
STATUS_CLOSED=Cancelled EVENT_ACTION=closed MERGED=false psync
check "projects: closed -> Cancelled falls back to removal when the board has no such column" 'exited 0 && removed && ! logged "-F option="'
STUB_FIELDS='[{"id":"F1","name":"Status","options":[{"id":"O1","name":"Todo"},{"id":"O4","name":"Cancelled"}]}]' STATUS_CLOSED=Cancelled EVENT_ACTION=closed MERGED=false psync
check "projects: closed -> Cancelled when the board has that column" 'exited 0 && set_to O4 && ! removed'
STUB_ON_BOARD=false STATUS_CLOSED=remove EVENT_ACTION=closed MERGED=false psync
check "projects: closed and not on the board -> nothing to remove" 'exited 0 && ! removed && said "nothing to remove"'
STUB_ON_BOARD=false EVENT_ACTION=opened MERGED=false psync
check "projects: opened and not on the board is an error (add-to-project ran first)" 'exited 1 && ! logged "-F option="'
PROJECT_OWNER=Obelyth PROJECT_NUMBER=3 PR_NODE_ID=PR_1 ITEM_ID="" STATUS_FIELD=Stage EVENT_ACTION=opened MERGED=false runner project-sync.sh
check "projects: a status field the board does not have is an error" 'exited 1 && ! logged "-F option=" && said "no field named"'

echo
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
