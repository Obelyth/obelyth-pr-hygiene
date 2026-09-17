#!/usr/bin/env bash
# Tests for every script that decides something: the title-to-label mapping,
# the size buckets, quarter milestone naming and due dates, the issue number a
# branch carries, closing-keyword detection, the placeholder gate that decides
# whether the describer runs, the guard that decides whether its output is
# applied, the label plan, the milestone plan and the project field lookup.
#
# No network: every script under test is a pure function of its arguments and
# its stdin, and the two runner cases stub gh with a script on PATH.
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

echo "title -> type label"
expect "feat:"                       type/feat     bash "$S/type-label.sh" "feat: add passkeys"
expect "fix(scope):"                 type/fix      bash "$S/type-label.sh" "fix(auth): null user"
expect "chore!: (breaking)"          type/chore    bash "$S/type-label.sh" "chore!: drop node 18"
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
status "garbage is refused"  2 bash "$S/quarter.sh" yesterday

echo "branch -> issue number"
expect "feat/12-passkeys"      12 bash "$S/branch-issue.sh" feat/12-passkeys
expect "12-passkeys"           12 bash "$S/branch-issue.sh" 12-passkeys
expect "hotfix/#7-null-user"   7  bash "$S/branch-issue.sh" "hotfix/#7-null-user"
expect "fix/12_underscore"     12 bash "$S/branch-issue.sh" fix/12_underscore
expect "a bare number"         42 bash "$S/branch-issue.sh" 42
expect "deep path feat/a/9-x"  9  bash "$S/branch-issue.sh" feat/a/9-x
expect "leading zeros 007-x"   7  bash "$S/branch-issue.sh" 007-x
status "no number"             1 bash "$S/branch-issue.sh" feature/no-number
status "release/v1.2"          1 bash "$S/branch-issue.sh" release/v1.2
status "number mid-segment"    1 bash "$S/branch-issue.sh" feat/v2-launch
status "dependabot version"    1 bash "$S/branch-issue.sh" dependabot/npm_and_yarn/lodash-4.17.21
status "zero is not an issue"  1 bash "$S/branch-issue.sh" 0-nothing
status "empty"                 1 bash "$S/branch-issue.sh" ""

echo "body -> closing keyword"
status_in "Closes #12"                     0 "Closes #12"                        bash "$S/closing-keyword.sh"
status_in "fixes #12 lower case"           0 "This fixes #12 for good"           bash "$S/closing-keyword.sh"
status_in "RESOLVES #12 upper case"        0 "RESOLVES #12"                      bash "$S/closing-keyword.sh"
status_in "Fixed #12 past tense"           0 "Fixed #12"                         bash "$S/closing-keyword.sh"
status_in "Close: #12 with a colon"        0 "Close: #12"                        bash "$S/closing-keyword.sh"
status_in "owner/repo#12"                  0 "Fixes Obelyth/aaa#12"              bash "$S/closing-keyword.sh"
status_in "issue URL"                      0 "Resolves https://github.com/Obelyth/aaa/issues/12" bash "$S/closing-keyword.sh"
status_in "mid-paragraph, after newline"   0 $'Summary.\n\ncloses #3\nmore'      bash "$S/closing-keyword.sh"
status_in "keyword without a number"       1 "This fixes the bug"                bash "$S/closing-keyword.sh"
status_in "number without a keyword"       1 "See #12"                           bash "$S/closing-keyword.sh"
status_in "prefixes is not a keyword"      1 "prefixes #12"                      bash "$S/closing-keyword.sh"
status_in "empty body"                     1 ""                                  bash "$S/closing-keyword.sh"
status_in "for #12: Closes #12"            0 "Closes #12"                        bash "$S/closing-keyword.sh" 12
status_in "for #12: Closes #120 is not it" 1 "Closes #120"                       bash "$S/closing-keyword.sh" 12
status_in "for #12: Closes #13 is not it"  1 "Closes #13"                        bash "$S/closing-keyword.sh" 12
status_in "for #12: closes #12, then more" 0 "closes #12, and #13"               bash "$S/closing-keyword.sh" 12
status_in "for #12: URL form"              0 "Fixes https://github.com/o/r/issues/12" bash "$S/closing-keyword.sh" 12
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
status_in "the app-starter template has no markers" 1 $'## What & why\n\n## How to test\n\n- **Steps:** 1.' bash "$S/placeholder.sh"

echo "body guard (exit 0 = apply, 3 = unchanged, 1 = rejected)"
guard() {  # name expected_rc old new
  local d; d="$(mktemp -d)"
  printf '%s' "$3" > "$d/old"; printf '%s' "$4" > "$d/new"
  status "$1" "$2" bash "$S/body-guard.sh" "$d/old" "$d/new"
}
filled="${tpl//<!-- pr-hygiene: summary. What this changes, in a sentence or two. Leave this comment in place and PR Hygiene writes it from the diff. -->/Adds passkey sign-in next to passwords.}"
filled="${filled//<!-- pr-hygiene: why. The problem or request this answers. -->/Passwords alone were the top support ticket.}"
filled="${filled//<!-- pr-hygiene: test-plan. How it was verified: commands run, what was checked by hand, what was not. -->/- unit tests for the WebAuthn flow are in the diff
- the browser flow has not been exercised here}"
guard "all three placeholders filled"            0 "$tpl" "$filled"
guard "one placeholder left in place"            0 "$tpl" "${tpl//<!-- pr-hygiene: summary. What this changes, in a sentence or two. Leave this comment in place and PR Hygiene writes it from the diff. -->/Adds passkeys.}"
guard "nothing changed"                          3 "$tpl" "$tpl"
guard "a heading was renamed"                    1 "$tpl" "${filled//## Why/## Motivation}"
guard "a heading was deleted"                    1 "$tpl" "${filled//## Test plan/}"
guard "a checklist item was ticked"              1 "$tpl" "${filled//- \[ \] CI is green/- [x] CI is green}"
guard "text appended after the checklist"        1 "$tpl" "$filled"$'\n\nAlso rewrote the roadmap.'
guard "text inserted before the first heading"   1 "$tpl" "Hi! $filled"
guard "a human sentence was reworded"            1 $'## Summary\n\nWe use OAuth.\n\n## Why\n\n<!-- pr-hygiene: why. -->' $'## Summary\n\nWe use OIDC.\n\n## Why\n\nBecause.'
guard "a human sentence kept, placeholder filled" 0 $'## Summary\n\nWe use OAuth.\n\n## Why\n\n<!-- pr-hygiene: why. -->' $'## Summary\n\nWe use OAuth.\n\n## Why\n\nBecause.'
guard "a human HTML comment is kept"             0 $'<!-- keep me -->\n<!-- pr-hygiene: summary. -->\n\nEnd' $'<!-- keep me -->\nWritten.\n\nEnd'
guard "a human HTML comment removed"             1 $'<!-- keep me -->\n<!-- pr-hygiene: summary. -->\n\nEnd' $'Written.\n\nEnd'
guard "empty body may become anything"           0 "" "Adds passkeys."
guard "empty body may not stay empty"            1 "" $'  \n'
guard "CRLF current body, LF new body"           0 "${tpl//$'\n'/$'\r\n'}" "$filled"
guard "a body with no placeholder is not touched" 1 "Written by hand." "Rewritten by a model."

echo "label plan"
plan2() {  # name expected ns want labels events
  local d; d="$(mktemp -d)"
  printf '%s\n' "$5" > "$d/labels"; printf '%s\n' "$6" > "$d/events"
  expect "$1" "$2" bash "$S/label-plan.sh" "$3" "$4" "$d/labels" "$d/events"
}
plan2 "no labels yet -> add"                          "add=type/feat"                type type/feat "" ""
plan2 "already right -> nothing"                      ""                             type type/feat "type/feat" $'labeled\ttype/feat\tgithub-actions[bot]'
plan2 "bot's stale label -> replaced"                 $'remove=type/fix\nadd=type/feat' type type/feat "type/fix" $'labeled\ttype/fix\tgithub-actions[bot]'
plan2 "person's label -> kept, ours not added"        "note=type/docs was set by a person, so type/feat was not added over it" type type/feat "type/docs" $'labeled\ttype/docs\tkeith'
plan2 "label with no event history -> treated as a person's" "note=type/docs was set by a person, so type/feat was not added over it" type type/feat "type/docs" ""
plan2 "person's and bot's stale together"             $'remove=size/S\nnote=size/XL was set by a person, so size/M was not added over it' size size/M $'size/S\nsize/XL' $'labeled\tsize/S\tgithub-actions[bot]\nlabeled\tsize/XL\tkeith'
plan2 "other namespaces are ignored"                  "add=size/M"                   size size/M $'type/feat\nsecurity' $'labeled\ttype/feat\tgithub-actions[bot]\nlabeled\tsecurity\tkeith'
plan2 "the last labeled event wins"                   $'remove=type/fix\nadd=type/feat' type type/feat "type/fix" $'labeled\ttype/fix\tkeith\nunlabeled\ttype/fix\tkeith\nlabeled\ttype/fix\tgithub-actions[bot]'

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
fields='[{"id":"F1","name":"Status","options":[{"id":"O1","name":"Todo"},{"id":"O2","name":"In progress"},{"id":"O3","name":"Done"}]},{"id":"F2","name":"Priority","options":[{"id":"P1","name":"High"}]}]'
expect "Status / In progress"        $'field_id=F1\noption_id=O2' bash "$S/project-fields.sh" Status "In progress" <<< "$fields"
expect "Status / Done"               $'field_id=F1\noption_id=O3' bash "$S/project-fields.sh" Status Done <<< "$fields"
status_in "missing option -> exit 4" 4 "$fields" bash "$S/project-fields.sh" Status Cancelled
status_in "missing field -> exit 1"  1 "$fields" bash "$S/project-fields.sh" Stage Done

echo "settings file"
if command -v yq > /dev/null 2>&1; then
  cfg() { bash "$S/config.sh" "$1" | paste -sd' '; }
  expect "the shipped template is all defaults" \
    "milestone=quarter reviewers= copilot_review=false project_owner=Obelyth project_number=0 project_status_field=Status project_status_opened=In progress project_status_merged=Done project_status_closed=remove" \
    cfg "$ROOT/templates/pr-hygiene.yml"
  expect "no file is all defaults" \
    "milestone=quarter reviewers= copilot_review=false project_owner= project_number=0 project_status_field=Status project_status_opened=In progress project_status_merged=Done project_status_closed=remove" \
    cfg "$SUITE_TMP/does-not-exist.yml"
  printf 'milestone: Q4 2026\nreviewers: [alice, bob]\ncopilot_review: true\nproject:\n  owner: ShootJackal\n  number: 3\n  status:\n    closed: Cancelled\n' > "$SUITE_TMP/cfg.yml"
  expect "every key read, the rest defaulted" \
    "milestone=Q4 2026 reviewers=alice,bob copilot_review=true project_owner=ShootJackal project_number=3 project_status_field=Status project_status_opened=In progress project_status_merged=Done project_status_closed=Cancelled" \
    cfg "$SUITE_TMP/cfg.yml"
  printf 'project:\n  number: three\n' > "$SUITE_TMP/bad.yml"
  status "a non-numeric project number is refused" 2 bash "$S/config.sh" "$SUITE_TMP/bad.yml"
else
  echo "  skip  yq is not installed here; the settings cases run in CI"
fi

# --- two runners against a stubbed gh, so the wiring is exercised too ------
echo "runners with a stubbed gh"
stub="$(mktemp -d)"; mkdir -p "$stub/bin"
cat > "$stub/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Records every call; answers the reads the runners make.
printf '%s\n' "$*" >> "$STUB_LOG"
case "$*" in
  "pr view 5 --repo o/r --json milestone --jq .milestone.title // empty") echo "" ;;
  "api --paginate repos/o/r/milestones?state=all&per_page=100 --jq .[] | {title, state, number}") echo '{"title":"Q1 2026","state":"closed","number":1}' ;;
  "pr view 5 --repo o/r --json body --jq .body") printf 'Summary.\n' ;;
  "api repos/o/r/issues/12") echo '{"number":12,"state":"open","title":"Passkeys"}' ;;
  "api repos/o/r/issues/13") echo '{"number":13,"state":"closed","title":"Old"}' ;;
  "api repos/o/r/issues/77") exit 1 ;;
  pr\ edit*--body-file\ -) cat > /dev/null ;;
  pr\ edit*) : ;;
  api\ -X\ POST*) : ;;
esac
exit 0
STUB
chmod +x "$stub/bin/gh"

export STUB_LOG="$stub/log"
: > "$STUB_LOG"
PATH="$stub/bin:$PATH" REPO=o/r PR_NUMBER=5 POLICY=quarter CREATED_AT=2026-09-17T00:00:00Z GITHUB_STEP_SUMMARY="$stub/summary" \
  bash "$S/milestone.sh" > "$stub/out" 2>&1
if grep -q 'api -X POST repos/o/r/milestones -f title=Q3 2026 -f due_on=2026-09-30T07:00:00Z' "$STUB_LOG" \
   && grep -q 'pr edit 5 --repo o/r --milestone Q3 2026' "$STUB_LOG"; then
  ok "milestone runner creates Q3 2026 with its due date, then assigns it"
else
  bad "milestone runner creates Q3 2026 with its due date, then assigns it"; sed 's/^/          /' "$STUB_LOG" | head -6
fi

: > "$STUB_LOG"
PATH="$stub/bin:$PATH" REPO=o/r PR_NUMBER=5 HEAD_REF=feat/12-passkeys GITHUB_STEP_SUMMARY="$stub/summary" \
  bash "$S/link-issue.sh" > "$stub/out" 2>&1
if grep -q 'pr edit 5 --repo o/r --body-file -' "$STUB_LOG"; then
  ok "link runner appends Closes #12 for an open issue named by the branch"
else
  bad "link runner appends Closes #12 for an open issue named by the branch"; sed 's/^/          /' "$stub/out" | head -4
fi

: > "$STUB_LOG"
PATH="$stub/bin:$PATH" REPO=o/r PR_NUMBER=5 HEAD_REF=feat/13-old GITHUB_STEP_SUMMARY="$stub/summary" \
  bash "$S/link-issue.sh" > "$stub/out" 2>&1
if ! grep -q 'pr edit' "$STUB_LOG" && grep -q 'closed' "$stub/out"; then
  ok "link runner leaves a closed issue alone"
else
  bad "link runner leaves a closed issue alone"
fi

: > "$STUB_LOG"
PATH="$stub/bin:$PATH" REPO=o/r PR_NUMBER=5 HEAD_REF=feat/77-ghost GITHUB_STEP_SUMMARY="$stub/summary" \
  bash "$S/link-issue.sh" > "$stub/out" 2>&1
if ! grep -q 'pr edit' "$STUB_LOG" && grep -q 'no such issue' "$stub/out"; then
  ok "link runner leaves a number that is not an issue alone"
else
  bad "link runner leaves a number that is not an issue alone"
fi

: > "$STUB_LOG"
PATH="$stub/bin:$PATH" REPO=o/r PR_NUMBER=5 HEAD_REF=feat/no-number GITHUB_STEP_SUMMARY="$stub/summary" \
  bash "$S/link-issue.sh" > "$stub/out" 2>&1
if [[ ! -s "$STUB_LOG" ]]; then
  ok "link runner makes no call at all when the branch has no number"
else
  bad "link runner makes no call at all when the branch has no number"
fi

echo
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
