# `merge-commit` Buildkite plugin

[![Continuous Integration][ci-img]][ci-url]

[ci-img]: https://github.com/JuliaCI/merge-commit-buildkite-plugin/actions/workflows/ci.yml/badge.svg "Continuous Integration"
[ci-url]: https://github.com/JuliaCI/merge-commit-buildkite-plugin/actions/workflows/ci.yml

If the build is a pull request, check out the merge commit.

## Example

To use this plugin, add the following YAML snippet to your `pipeline.yml` file:

```yml
steps:
  - plugins:
    - JuliaCI/merge-commit#v1: ~
```
