# `merge-commit` Buildkite plugin

[![Continuous Integration][ci-img]][ci-url]

[ci-img]: https://github.com/JuliaCI/merge-commit-buildkite-plugin/actions/workflows/ci.yml/badge.svg "Continuous Integration"
[ci-url]: https://github.com/JuliaCI/merge-commit-buildkite-plugin/actions/workflows/ci.yml

If the build is a pull request, check out the merge commit.

GitHub creates the merge commit (`refs/pull/N/merge`) asynchronously after every push,
so the plugin retries, waiting 45 seconds in total, until that ref merges the commit
being built. It does not check that the merge is against the current base branch.

The build fails when the merge commit doesn't show up in time, which usually means that
the pull request was closed or merged, has merge conflicts, or GitHub is having problems. It also fails right
away when the pull request has been pushed to since the build was created and GitHub no
longer has a merge of the build's commit; rebuilding such an old build fails the same way.

## Example

To use this plugin, add the following YAML snippet to your `pipeline.yml` file:

```yml
steps:
  - plugins:
    - JuliaCI/merge-commit#v1: ~
```
