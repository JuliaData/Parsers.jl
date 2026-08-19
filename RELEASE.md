# Maintainer release checklist

This checklist separates rewrite review from the immutable registered release.

## One-time repository settings

Before the final merge, configure settings that cannot be stored in this
repository:

1. Set the default workflow token to read-only and prevent workflows from
   approving pull requests. The workflows in this repository request their
   required permissions explicitly.
2. Require full commit-SHA pins for actions, or restrict actions to the trusted
   owners used here. Keep Dependabot enabled for action updates.
3. After the new checks have run once, require the selected CI, integration,
   and documentation checks on `main`. Keep the required review, require
   resolved conversations, and disable force pushes.
4. Enable private vulnerability reporting and Dependabot security updates.
   Enable secret scanning, push protection, and Actions workflow scanning when
   the organization plan permits them.
5. Set Codecov's default branch to `main`. Confirm that the repository accepts
   the workflow's OIDC upload before making coverage a required check.
6. After the first documentation deployment creates `gh-pages`, publish that
   branch from its root with GitHub Pages. Set the repository homepage to the
   stable documentation URL.

## Rewrite pull request

1. Keep `Project.toml` at `3.0.0-DEV` during review.
2. Link the migration guide and summarize every breaking change in the pull
   request body.
3. Invite important downstream maintainers to test the branch. Downstream
   compat caps are an outreach item; they do not by themselves block a correct
   major release.
4. Require the unit, integration, documentation, and coverage checks.
5. Confirm that the exact pull-request head passes on Julia 1.10, latest,
   nightly, 32-bit Julia, Windows, and macOS.
6. Merge only after review threads are resolved.

## Release pull request

After the rewrite is merged, use a separate release pull request:

1. Change the project version from `3.0.0-DEV` to exactly `3.0.0`.
2. Rename the changelog's `Unreleased` section to `3.0.0` with the release
   date. Add a new empty `Unreleased` section.
3. Confirm that all release notes are accurate and that no benchmark number is
   stated without reproducible evidence.
4. Run the complete CI and documentation suite on the exact release commit.
5. Record that commit SHA. Do not register a different commit.

The General registry does not accept a version with prerelease metadata such as
`-DEV`.

## Register and verify

1. On the exact release commit, comment:

   ```text
   @JuliaRegistrator register
   ```

2. Add explicit `Release notes:` text with the breaking changes, Julia 1.10
   minimum, migration guide, and documentation link.
3. Monitor the General registry pull request and resolve any AutoMerge failure.
4. Monitor TagBot. Confirm that tag `v3.0.0` points to the recorded commit.
5. Confirm the GitHub release body and stable documentation deployment.
6. In a clean environment, run:

   ```julia
   import Pkg
   Pkg.add(name="Parsers", version="3")
   import Parsers
   @assert Parsers.parse(Int, "42") == 42
   ```

7. Confirm that the Codecov report and documentation links refer to the release
   commit.

Registered versions are immutable. Publish `3.0.1` for a post-release fix; do
not move or replace the `v3.0.0` tag.
