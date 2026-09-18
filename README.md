# PR Hygiene

**Labels, milestone, linked issue, description, release notes and project board,
filled in on every pull request. One reusable workflow, called from each repo.**

[![CI](https://github.com/Obelyth/obelyth-pr-hygiene/actions/workflows/ci.yml/badge.svg)](https://github.com/Obelyth/obelyth-pr-hygiene/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

The sidebar of a pull request has eight little sections - reviewers, labels,
projects, milestone, development, notifications, release, plus the description
above it - and on a one-person estate they stay empty, because filling them in
by hand on every pull request is exactly the kind of work nobody does. This
fills them in. Deterministic shell does everything it can; a model is used for
one thing only (writing the empty sections of a description from the diff), and
its output goes through a guard that throws it away if it touched anything a
person wrote.

It holds no secrets and is public so private repositories on any account can
call it.

---

## What happens when

| Event on a pull request | labels | milestone | development | describe | projects | reviewers | release |
|---|---|---|---|---|---|---|---|
| **opened** | scheme ensured; `type/*` from the title, `size/*` from the diff, path labels if `.github/labeler.yml` exists | `Qn YYYY` for the quarter it was opened in (created if missing, due on the quarter's last day) unless it already has one | `Closes #n` appended when the branch names an open issue and the body closes nothing yet | empty sections written from the diff, unless a draft (needs a Claude credential) | added to the board, status → *In Progress* if it had none (needs `PROJECTS_TOKEN`) | the configured list, plus Copilot if enabled | - |
| **ready_for_review** | same | same | same | same (this is when a draft gets its description) | same | same | - |
| **edited** (title or body changed) | `type/*` re-read from the title; a stale one this tool set is swapped, one a person set is kept | same (no-op once set) | same | only if the body is still empty or still has placeholders | status set only if empty | - | - |
| **synchronize** (new commits) | `size/*` re-bucketed the same way | same | same | same | same | - | - |
| **reopened** | same | same | same | same | same | same | - |
| **closed, merged** | - | - | - | - | status → *Done* | - | - |
| **closed, not merged** | - | - | - | - | removed from the board (or status → *Cancelled* when the board has that column and the settings ask for it) | - | - |
| **push of a `v*` tag** | - | - | - | - | - | - | a GitHub Release with generated notes, grouped by the `type/*` labels via `.github/release.yml`, if none exists for that tag |
| **no `CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY`** | - | - | - | one-line notice in the summary, body left as it is | - | - | - |
| **no `PROJECTS_TOKEN`** | - | - | - | - | one-line notice in the summary, board untouched | - | - |

A pull request from a fork gets nothing: the token cannot edit it. Every job
that finds nothing to do says so in the run's summary, and a missing secret is a
one-line notice there, never a red check.

**Notifications** need nothing - the author is subscribed to their own pull
request by GitHub itself.

**Reviewers** - GitHub cannot show the author as a reviewer of their own pull
request, and `CODEOWNERS` auto-requests only work for *other* people. On a
one-person estate the review that exists is the Claude PR Review workflow.
What this does: request an explicit list from the settings file (`reviewers:`),
and a Copilot code review when `copilot_review: true` (a paid feature). Nothing
more is possible.

---

## Installing it

```sh
./install.sh --repo Obelyth/example             # one repository
./install.sh --owner Obelyth                    # every non-archived repository of an owner
./install.sh --repo Obelyth/.github --template-only   # the org-wide pull request template
./install.sh --owner ShootJackal --dry-run      # see what would change
```

Everything lands **by pull request** on a branch called `chore/pr-hygiene-install`
- never by a push to the default branch. What goes in:

| File | Role | On a repo that already has one |
|---|---|---|
| `.github/workflows/pr-hygiene.yml` | the caller, rendered from [`templates/caller.template.yml`](templates/caller.template.yml) | brought up to date |
| `.github/release.yml` | release-notes categories by the `type/*` labels | kept unless `--force` |
| `.github/pull_request_template.md` | Summary / Why / Test plan / Checklist, each empty section marked by a `<!-- pr-hygiene: ... -->` comment the describer fills | kept unless `--force` (a template at the repo root or in `docs/` counts) |
| `.github/pr-hygiene.yml` | the settings, all defaults | never replaced |

The installer also says which secrets the repository is missing (see below).
For `Obelyth/.github`, `--template-only` puts the pull request template in place
as the organization default, which every Obelyth repository without its own
template then picks up.

The caller is small:

```yaml
on:
  pull_request:
    types: [opened, edited, synchronize, reopened, ready_for_review, closed]
  push:
    tags: ['v*']
permissions:
  contents: write
  pull-requests: write
  issues: write
  id-token: write
jobs:
  hygiene:
    uses: Obelyth/obelyth-pr-hygiene/.github/workflows/pr-hygiene.yml@main
    secrets: inherit
    with:
      tag: ${{ github.ref_type == 'tag' && github.ref_name || '' }}
```

The toolkit is called at `@main` on purpose, unlike the third-party actions
inside it, which are pinned to commit SHAs: a fix here reaches every
repository without a reinstall, and `main` only moves by pull request with a
green `ci` check (the repository's ruleset allows nothing else - no direct
push, no force-push, no deletion). The scripts run at the same commit as the
workflow file, via `github.job_workflow_sha`. A fork that wants a fixed
version can pin the `uses:` line to a SHA; `install.sh` then keeps it there.

---

## Settings: `.github/pr-hygiene.yml`

Read from the **default branch**, so a pull request cannot change the rules for
itself. Every key is optional. Schema: [`schema/pr-hygiene.schema.json`](schema/pr-hygiene.schema.json).

```yaml
milestone: quarter        # quarter | none | a milestone title that already exists
reviewers: []             # logins to request; the author is skipped
copilot_review: false     # also request a Copilot code review (paid)
project:
  owner: Obelyth          # organization or user that owns the board
  number: 0               # the number in the board's URL; 0 switches the job off
  status_field: Status
  status:
    opened: In Progress   # set when added, only if it has no status yet
    merged: Done
    closed: remove        # or a column name such as Cancelled
```

---

## The label scheme

Created in every calling repository on first run and refreshed after (colour
and description only; a label is never deleted). From [`labels/labels.json`](labels/labels.json):

| Namespace | Labels | Set by |
|---|---|---|
| `type/` | `feat` `fix` `chore` `docs` `ci` `refactor` `test` `perf` | the title's conventional-commit prefix - `feat(auth): ...`, `fix!: ...`; anything else is `type/chore` |
| `size/` | `XS` < 10 lines, `S` < 50, `M` < 200, `L` < 500, `XL` | additions + deletions |
| - | `security` `dependencies` `needs-review` `blocked` | people (and Dependabot for `dependencies`) |

**A label a person added is never removed.** `type/*` and `size/*` are the
tool's namespaces, and it replaces a label there only when it is one of the
scheme's own names and the pull request's events show `github-actions[bot]`
put it there. If a person chose a `type/*` label, that stands and the computed
one is not added over it.

Path labels come from [`actions/labeler`](https://github.com/actions/labeler)
when the repository has a `.github/labeler.yml`, with `sync-labels: false` so it
only ever adds. It runs under the same bot, so any label named in
`labeler.yml` is treated as its, never as this tool's: a `labeler.yml` that
maps paths to `type/docs` keeps that label on the pull request, and the title's
`type/*` is not added over it.

---

## Milestones

Policy `quarter` (the default): the milestone named `Q3 2026` for the quarter
the pull request was **opened** in (UTC), created if missing with the quarter's
last day as its due date - `Mar 31`, `Jun 30`, `Sep 30`, `Dec 31`. A pull
request that already has a milestone keeps it. A closed milestone is never
reopened; the run says so and moves on. `none` leaves milestones alone; any
other value is a title assigned verbatim, and it must already exist.

## Development (linked issue)

When the head branch carries an issue number - `feat/12-passkeys`, `12-passkeys`,
`hotfix/#7-null-user`; a number at the start of the name or of a path segment,
followed by `-`, `_` or the end - and that number is an **open issue** in the
same repository, and the body has no closing keyword yet, the line `Closes #12`
is **appended** to the body. The body is never replaced. A body that already
closes something (any of GitHub's keywords, any case, `#n`, `owner/repo#n` or a
URL) is left alone, so a link a person wrote is never duplicated or overridden;
a keyword inside a code span, a code block or an HTML comment does not count,
because GitHub does not link from there either.

Two shapes are not taken as issue numbers unless the `#` is there: a number
followed by another run of digits (`chore/2026-09-17-cleanup`, `feat/1-2-3`)
and a four-digit number from 1900 to 2099 (`release/2026-Q3`). A branch named
after an HTTP status - `fix/404-page` - does name issue #404 when one is open;
write `fix/http-404-page` if that is not what you mean.

## Describe

Runs **only** when the body is empty or still contains a `<!-- pr-hygiene: ... -->`
placeholder from the template (a comment that opens a line; the marker quoted
inside a sentence, as here, is not one), never on a draft, and only for events
a person caused - an app editing the body or a Dependabot pull request does
not spend a model run. It uses
[`anthropics/claude-code-action`](https://github.com/anthropics/claude-code-action)
with `claude-sonnet-5`, a turn cap, and a tool list that can read the pull
request (`gh pr view`, `gh pr diff`, the checkout) and write **one file**. The
prompt says: replace each placeholder comment with prose from the diff, leave
every other byte identical, never claim a test was run.

The prompt is not what enforces that. [`scripts/body-guard.sh`](scripts/body-guard.sh)
splits the current body on its placeholder comments and checks that the
proposed body is exactly those pieces, in order, with anything in between - so a
reworded sentence, a renamed heading, a ticked checkbox or a paragraph appended
after the checklist is rejected and the body stays as it was. What goes into a
placeholder is checked too: an HTML comment or an unclosed code fence (either
would hide every section after it), a closing keyword such as `Closes #n`, an
`@mention`, or anything shaped like a credential is rejected, since the model
reads a diff and a diff can say anything. The body is then read again from the
pull request, and if a person edited it while the model was writing, the
proposal is dropped rather than overwrite them (the `edited` event their edit
raised is queued behind this run and looks afresh). Only then does
`gh pr edit --body-file` run, from the workflow, not from the model. A body that
was empty may become anything that passes the same content checks.

It needs `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` (an organization
secret on Obelyth; per-repository on a personal account). Without one, the run
notes it and skips.

## Release

On a push of a `v*` tag, a GitHub Release is created with
`generate_release_notes` if none exists for that tag, using
[`softprops/action-gh-release`](https://github.com/softprops/action-gh-release).
The notes follow `.github/release.yml`: Features, Fixes, Performance, Security,
Refactoring, Documentation, CI/tests/chores, Other - by the `type/*` labels,
with `dependencies` and Dependabot left out. Once a release exists, every merged
pull request in it shows that release in its sidebar on its own. **A release is
never created on a pull request event.**

## Projects

`GITHUB_TOKEN` cannot read or write Projects v2, so this job runs only when a
`PROJECTS_TOKEN` secret exists; otherwise it writes one line to the summary and
skips. It adds the pull request to the board with
[`actions/add-to-project`](https://github.com/actions/add-to-project), then
sets the status field with GraphQL (`updateProjectV2ItemFieldValue`), resolving
the field and option ids **by name on every run** - rename a column and nothing
here changes. A status a person set is kept: the opened status is only written
when the item has none.

### Making `PROJECTS_TOKEN`

A **fine-grained personal access token** is scoped to one resource owner, so a
board under the Obelyth organization and a board under the ShootJackal user
need two tokens:

| Board owner | Token | Where to store it |
|---|---|---|
| Obelyth (org boards) | Resource owner **Obelyth** → Organization permissions: **Projects: Read and write** → Repository permissions: **Pull requests: Read**, **Issues: Read**, **Metadata: Read** (automatic) | Organization secret `PROJECTS_TOKEN` on Obelyth |
| ShootJackal (user boards) | Resource owner **ShootJackal** → Account permissions: **Projects: Read and write** → same repository permissions | Repository secret `PROJECTS_TOKEN` on each ShootJackal repo |

The single-token alternative is a **classic** PAT with the `project` and
`repo` scopes, which covers both owners; store it under the same name. Either
way, no token, no job - and never a failure.

---

## What it will not do

- remove a label a person added, or add a `type/*` over one a person chose
- reopen a closed milestone, or replace a milestone that is already set
- replace a body: `Closes #n` is appended; the describer may only fill placeholders
- create a release on anything but a `v*` tag push
- touch a pull request from a fork
- fail a run because a secret is missing

## Layout

```
.github/workflows/pr-hygiene.yml   the reusable workflow (on: workflow_call)
.github/workflows/pr-hygiene-self.yml  this repo running it on its own pull requests
templates/caller.template.yml      what install.sh renders into each repo
templates/release.yml, pull_request_template.md, pr-hygiene.yml   shipped alongside
labels/labels.json                 the label scheme
schema/pr-hygiene.schema.json      the settings schema
scripts/                           pure functions (args and stdin in, stdout out):
                                     type-label, size-label, quarter, branch-issue,
                                     closing-keyword, placeholder, body-guard,
                                     label-plan, milestone-plan, project-fields, config
                                   and the thin runners that wire gh around them:
                                     labels-ensure, labels-apply, milestone, link-issue,
                                     describe-prepare, describe-apply, project-sync, reviewers
tests/hygiene_test.sh              every decision above, without a network
install.sh                         installs by pull request
```

`bash tests/hygiene_test.sh` runs in a second. CI runs shellcheck, actionlint
(on the workflows and on the rendered caller), validates the data files and the
settings against the schema, and runs the tests.


## Claude PR Review

The reviewer is a second reusable workflow in this toolkit, `.github/workflows/claude-review.yml`,
called from `templates/claude-review.caller.yml` in each repository. It reads every non-draft,
human-authored, same-repo pull request once per push and posts one summary comment plus inline
comments; it never writes to the tree (its tool list allows only comments and CI reads). It runs
on `claude-sonnet-5` with a 12-turn cap and prints **what each review cost** in the job summary.

Authentication is workload identity federation, one rule per GitHub account, created in the
Anthropic Console (Settings → Workload identity):

| field | value |
|---|---|
| provider | GitHub Actions |
| subject | `repo:Obelyth@286144193/*` (Obelyth) · `repo:ShootJackal@260789752/*` (ShootJackal) |
| `event_name` | `pull_request` |
| `job_workflow_ref` | `Obelyth/obelyth-pr-hygiene/.github/workflows/claude-review.yml@refs/heads/main` |
| workspace | `wrkspc_01X3oWfERuSwC2LsE5jzG8P1` · service account `svac_018dtjjur2szezYx3BARMvKg` |

Every repository that calls the workflow needs the **immutable OIDC subject** setting on
(`PUT /repos/{owner}/{repo}/actions/oidc/customization/sub` with `use_immutable_subject: true`),
which is what puts the numeric ids into the subject the rule matches. Put the rule id into the
caller's `federation_rule_id` and the review runs. The Console's *Authentication events* tab names
the failing condition on every rejected exchange — check it first.

The rule id and its service account are **Actions variables**, `CLAUDE_REVIEW_FEDERATION_RULE_ID`
and `ANTHROPIC_SERVICE_ACCOUNT_ID` — organization variables on Obelyth, repository variables on
each ShootJackal repository — and the caller passes them through, so the caller file is identical
everywhere and names no account. **Leave the rule variable unset and the review runs on the
`CLAUDE_CODE_OAUTH_TOKEN` secret instead** (a subscription token from `claude setup-token`, passed
with `secrets: inherit`), billing the subscription rather than the Console. One variable per
account is therefore the switch between the two. When the chosen credential is dead the action
ends without running Claude and the job summary says **not reviewed** — a green tick there is not
a clean review.
