# Agent instructions

## Independent review and merge authorization (2026-11-18)

Never push directly to the default branch. Use a PR under this authorization.

The maintainer's independent-review rule (2026-11-18) applies only to
FAIR-bioHeaders repositories and agents operated by David Molik (`molikd`) or
Adam Wright (`adamjohnwright`). A PR submitted by either maintainer or their
agents may satisfy the approval gate through an independent **different model**:
Copilot, or a model operated by David or Adam. The approving model/agent must be
other than the submitter; an agent must not self-approve its PR, and another
instance of the same model does not satisfy the different-model requirement.
Record author/reviewer model provenance when needed to establish independence.
David and Adam themselves may self-approve their PRs; this exception does not
apply to their agents.

An eligible agent may merge only after that approval requirement is met, all
applicable CI checks are green, and its own validation of the current changes
passes, including changes after review. Recheck the exact head, base branch,
findings and dependencies immediately before merging. Missing checks are not
passing checks, and branch protection must not be bypassed. Read every overall
review and inline finding, reply with its disposition and fix/evidence, resolve
handled threads, and post an overall response. Merge authorization does not grant
contract adoption, curator acceptance, release, publication or deployment
authority; those retain their separate maintainer gates.

Authority: [approval by another, different model](https://github.com/FAIR-bioHeaders/FAIR-bioHeaders-Specification/issues/268#issuecomment-6984337685)
and [human self-approval exception](https://github.com/FAIR-bioHeaders/FAIR-bioHeaders-Specification/issues/268#issuecomment-6984418624).

Port source: FAIR-bioHeaders-Specification commit
`0d0d6b43efdee96bc7548f1f7c65fdafb2a31f32` ([specification PR #269](https://github.com/FAIR-bioHeaders/FAIR-bioHeaders-Specification/pull/269)).

## Repository identity

This is FAIR-bioHeaders-Tools-R, the native R consumer library. Read README.md
and LICENSE before making changes; shared contracts remain owned by
FAIR-bioHeaders-Specification. Preserve repository-local validation, provenance
and licensing boundaries.
