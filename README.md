# `merge-commit` Buildkite plugin

If the build is a pull request, check out the merge commit.

## Example

To use this plugin, add the following YAML snippet to your `pipeline.yml` file:

```yml
steps:
  - plugins:
    - JuliaCI/merge-commit#v1: ~
```
