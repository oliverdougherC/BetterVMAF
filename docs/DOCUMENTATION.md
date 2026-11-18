# Documentation standards

BetterVMAF’s documentation should let a contributor reproduce a task from a
fresh checkout and let a maintainer recover the context behind a decision.

## Put each kind of information in one place

| Reader’s task | Where it belongs |
| --- | --- |
| Install the app, update it, or understand a result | [Project README](../README.md) |
| Build, test, or submit a change | [Contributing guide](../CONTRIBUTING.md) |
| Package, publish, verify, or recover a release | [Release runbook](RELEASING.md) |
| Find a guide, reference, or historical record | [Documentation index](README.md) |
| Plan, prioritize, or discuss implementation work | [BetterVMAF Linear project](https://linear.app/platinum-labs/project/bettervmaf-bb52721c0728) |

Update the page that already owns the information and link to it from related
pages. Add a new page when it serves a distinct reader or task, and link it from
the index. Keep GitHub issues useful for public feedback and link related issues
from Linear.

Keep current instructions separate from dated records. For example, a release
runbook explains what to do on the next release, while an audit records which
release, commit and checks were actually exercised. Preserve earlier evidence
and mark the date or revision it applies to.

## Write instructions someone can follow

- Start with the purpose, audience and prerequisites. Name the supported
  platform, tool versions, access and working directory when they matter.
- Use ordered steps for a workflow. Include an observable result for each
  important step, such as an expected file, score or workflow status.
- Use fenced command examples with quoted paths. Explain placeholders before
  they appear and show which steps change local or remote state. Put approvals
  immediately before protected or irreversible actions.
- Reference the configuration, script or workflow that enforces a rule. Use
  relative links within the repo, descriptive link text, and primary sources
  for external technical claims.
- Use real secret names with placeholder paths or secure prompts. Keep secret
  values, exports, machine-specific personal paths and private logs out of
  published docs.
- Distinguish shipped behavior, known limitations and proposals. For quality
  metrics, follow the project’s [reporting rules](../CONTRIBUTING.md#metric-changes).

## Verify docs with the change

- Update the owning document in the same PR when behavior, setup, a command,
  or an acceptance check changes. Update links when you move or rename a
  section.
- Check that relative links and section anchors resolve. Check command
  examples from the documented working directory. Use read-only, staging or
  dry-run paths when testing examples that would publish or change protected
  state.
- In the PR, list what you tested and any remaining limits. For a release
  record, include the version, commit, workflow links, checksums, and the
  installed-app result. Specify the host and architecture, including whether
  an Intel executable ran through Rosetta.
