# craft-libs-adoption

Every six hours, this automation scans the Craft Apps suite for merged
pull requests that matter to [craft-libs](https://github.com/ahmedhosnypro/craft-libs) —
the shared Rust library collection — and files evidence-backed findings
as issues on its fork of craft-libs.

A run is one bounded agent session on a GitHub runner:

1. **Collect** the last 6 hours of merged pull requests across the
   suite (the list and each repo's watch-paths live in
   [`config/repo-list.txt`](config/repo-list.txt)).
2. **Classify** each merge: a craft-libs revision sync, a shared-crate
   hoist worth proposing, a port the apps owe each other — or just an
   app feature, which is most of them.
3. **Propose** at most three findings — issues on the craft-libs fork,
   each citing the merged pull requests that justify it, and honoring
   the target repository's own scope policy and conventions.
4. **Deliver** — every run leaves a visible trace: its findings, or a
   rollup comment on the tracking issue when the window was quiet.

The scan runs headless through the
[craft-agent](https://github.com/ahmedhosnypro/craft-agent) action
against a private, bring-your-own-key model gateway. The suite
repositories are examined read-only; the automation writes only on its
own fork of craft-libs — finding issues and the tracking issue — and
may attempt pin-bump branches on the app repositories' forks where the
run has push rights, parking the attempt otherwise. The upstream
craft-libs repository receives nothing from it.

## Operating

- Trigger manually: Actions → "Craft libs adoption scan" → Run
  workflow, or `gh workflow run adopt-libs.yml`.
- The schedule runs at 00:20, 06:20, 12:20, and 18:20 UTC — the
  first slot lands right after the suite's late-night merge burst.
- Configuration is data: the repo list and each repository's
  watch-paths live in `config/repo-list.txt`.
- Rules for agent runs and humans live in
  [AGENTS.md](AGENTS.md).
