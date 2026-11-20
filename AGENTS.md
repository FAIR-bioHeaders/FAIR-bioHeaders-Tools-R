# Agent instructions

## Independent review and human-only merges (maintainer direction, 2026-11-20)

The [Round 16 policy](https://github.com/FAIR-bioHeaders/FAIR-bioHeaders-Specification/issues/211#issuecomment-7042896529)
supersedes the former conditional agent-merge authorization of 2026-11-16/18 and
the #268 authority links recorded under it. **Agents must never merge pull
requests; a human performs every merge, across all repositories an agent operates
in, including external upstream repositories and personal forks.** Do not enable
auto-merge, enter a merge queue, use another agent or service as a merge proxy,
or push directly to the default branch as a substitute for merging a PR. Model
review never grants an agent merge authority; preserve platform protections and
do not forge approval or work around repository permissions.

Every PR receives independent review from another actual model. A different
model family is preferred (for example Codex or Gemini reviewing Qwen work, or
Qwen reviewing Codex work), but family diversity is a preference, not a hard
requirement; a second session of the same model is not another model. Record
actual author/reviewer model identities and never invent review provenance.

Agents keep monitoring CI and fixing failures and actionable review findings:
read the overall review and every inline finding, fix in new commits, reply with
disposition and evidence, resolve handled threads and acknowledge clean reviews.
Validate the current head after changes and hand the human exact head/base,
review, CI, dependency and remaining-risk information. Missing, failed and
NOT_RUN checks are not passes. This grants no contract adoption, curator
acceptance, release, publication or deployment authority — those gates are
unchanged. Earlier rounds' authorized merges and dated receipts remain accurate
historical facts, not future permission.

## Repository identity

This is FAIR-bioHeaders-Tools-R, the native R consumer library. Read README.md
and LICENSE before making changes; shared contracts remain owned by
FAIR-bioHeaders-Specification. Preserve repository-local validation, provenance
and licensing boundaries.
