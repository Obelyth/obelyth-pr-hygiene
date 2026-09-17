# Security

## What this software is allowed to do

Installed, PR Hygiene can edit pull requests in the calling repository - labels,
milestone, body, requested reviewers - create milestones and labels, create a
release from a tag, and, with a `PROJECTS_TOKEN`, add items to a project board
and set their status. When a Claude credential is present it runs a language
model over a pull request's diff.

The blast radius is kept small on purpose:

- **Settings come from the default branch**, never from the pull request, so a
  branch cannot change the rules for itself.
- **Pull requests from forks are ignored.** The token cannot write to them, and
  nothing runs a model over a stranger's diff.
- **The model can write one file.** Its tool list is read-only against GitHub
  (`gh pr view`, `gh pr diff`) plus a single output path. It cannot edit the
  pull request, comment, push, or call the API.
- **Its output is checked before it is used.** `scripts/body-guard.sh` rejects
  any proposed body that changes a byte outside the template's placeholder
  comments. The edit is then made by the workflow with `GITHUB_TOKEN`, not by
  the model.
- **Nothing is deleted.** Labels a person added, milestones, bodies and
  releases are only ever added to.
- **A missing secret skips the job** with a notice; it never fails a check and
  never falls back to a broader credential.
- **Every action is pinned to a commit SHA**, and Dependabot proposes bumps.

## Credentials

`CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY` are used for one job
(describe). Keep them organization-level where possible and rotate on a
schedule.

`PROJECTS_TOKEN` is a fine-grained PAT with Projects read/write and read-only
repository permissions; see the README for the exact permission set. It is
used only by the projects job and only through `gh api graphql` and
`actions/add-to-project`.

## Reporting

Open an issue in this repository. It is a small, public toolkit; there is no
embargo process.
