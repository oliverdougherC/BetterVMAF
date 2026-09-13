# Working on BetterVMAF

BetterVMAF is a free native macOS app for understanding quality lost during video encoding. Keep the SwiftUI app small, responsive, local, and easy to use.

## Start here

- Read `README.md`, `CONTRIBUTING.md`, and the relevant document in `docs/`.
- Linear is the development backlog for this project. GitHub issues remain a public feedback channel; link them from Linear instead of creating competing implementation plans.
- Work from current `main` on short-lived task branches. Keep changes focused and preserve unrelated work. Use the user's current authorization when deciding whether to merge or delete a branch.

## Product rules

Ask of every visible element: **Does the user need to see this? Is this the most effective and efficient presentation?**

- Start with source, encode, and comparison. Reveal advanced metrics and implementation details only when useful.
- Clicking a quality concern must eventually seek to its exact interval and visual evidence.
- Do not describe any metric as a percentage of retained quality or proof of transparency. Do not average unrelated metric scales into an invented score.
- Preserve disagreements between metrics; clearly label sampling and unsupported comparisons.

## Engineering rules

- Correct correspondence, timestamps, color handling, and input provenance come before additional metrics.
- Launch tools with `Process.executableURL` and an argument array. Never turn filenames into shell code.
- A cancel action must stop owned processes and suppress stale callbacks. Use stable job IDs, not mutable array indices.
- Keep decoding, metric work, parsing, and large chart preparation off the main actor. Bound worker counts, logs, and retained frames.
- Save engine versions, model hashes, preprocessing choices, frame timestamps, and immutable source identity with results.
- Prefer small extraction seams around the current implementation over an app-wide rewrite.
- Test changed behavior with meaningful fixtures. Empty launch/template tests are not metric correctness evidence.
- Use the shared Xcode scheme and CI commands documented in `CONTRIBUTING.md`. Report explicitly when macOS execution was unavailable.
- Keep native helper binaries pinned, checksummed, and accompanied by their source/build/license provenance. Do not silently substitute a different system engine.

## Scope

The current cleanup establishes the development foundation and roadmap. Multi-metric scoring, player replacement, and the engine refactor are planned work, not existing app capabilities.
