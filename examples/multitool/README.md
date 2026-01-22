# Multitool Example

Example using `rules_multitool` to manage external tool binaries.

This example includes `kubectl` configured via `multitool.lock.json`.

## Setup

```bash
bazel run //tools:dev
direnv allow
```

## Usage

Once set up, `kubectl` is available in your PATH:

```bash
kubectl version --client
```

## Adding More Tools

Edit `multitool.lock.json` to add more tools. See the [rules_multitool documentation](https://github.com/theoremlp/rules_multitool) for the lockfile format.
