# Contributing

Thanks for considering a contribution. This is a small, personal collection
of sysadmin scripts and docs, kept simple on purpose — contributions are
welcome but should fit that spirit.

## Reporting a bug or suggesting a change

Open an issue describing:
- What script or doc is affected.
- What you expected vs. what actually happened (for a script, include the
  Windows version and PowerShell version if relevant — `$PSVersionTable`).
- Any error output.

## Submitting a change

1. Fork the repo and create a branch for your change.
2. Keep changes focused — one script/doc per pull request is easier to
   review than a bundle of unrelated fixes.
3. For scripts:
   - Match the existing style: comment-based help (`.SYNOPSIS`,
     `.PARAMETER`, `.EXAMPLE`), `[CmdletBinding()]`, and named parameters
     rather than positional ones.
   - Use `SupportsShouldProcess`/`-WhatIf` for anything that changes
     system state.
   - Scripts should fail safely — prefer erroring out over guessing, and
     avoid destructive actions without a clear opt-in flag.
   - Run PSScriptAnalyzer locally before submitting — CI runs the same
     check (`Invoke-ScriptAnalyzer -Path .\scripts -Recurse`).
4. For docs:
   - Keep the same tone: practical, concrete commands over abstract
     advice. Prefer real command examples to prose descriptions.
   - Note any assumptions (elevated session required, RSAT installed,
     domain-joined, specific Windows Server version, etc.).
5. Update the relevant README's file listing if you add a new script or
   doc.

## What's out of scope

- Anything that requires a specific commercial product or vendor-specific
  API to be useful to most readers.
- Scripts that make destructive changes with no dry-run (`-WhatIf`) or
  confirmation option.
- Content that only makes sense for one very specific environment rather
  than general server administration.

## Code of conduct

Be respectful and constructive in issues and pull requests. Disagreement
about approach is fine and expected; personal attacks are not.
