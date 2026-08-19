---
name: lofiatc-install-test
description: Produce and validate traditional non-Git user testing instructions for a LofiATC branch or pull request through install.ps1. Use when asked how to test a change as an end user, install a feature branch, verify installed command behavior, exercise updater or rollback behavior, or retest after a PR update. Do not perform a real installation into the agent host during routine automated validation.
---

# Test through the install script

## Build the installation command

1. Resolve the exact repository and remote branch backing the PR; do not use an unpushed local branch.
2. Use the branch's raw `install.ps1` and pass the same branch through `-Ref`:

```powershell
$Repository = 'RoMinjun/lofiatc.ps1'
$Ref = '<branch-name>'
$InstallerUri = "https://raw.githubusercontent.com/$Repository/$Ref/install.ps1"
& ([scriptblock]::Create((Invoke-RestMethod $InstallerUri))) -Repository $Repository -Ref $Ref
```

3. Tell the user to open a new PowerShell session after installation.
4. Include `lofiatc -Version` so the user can confirm repository, ref, and commit before testing.

## Create a feature-specific smoke test

1. Test through the installed `lofiatc` command, not a checkout path.
2. Give exact commands, expected visible behavior, and a failure signal.
3. Exercise both the new behavior and the nearest existing behavior that must remain unchanged.
4. Include Windows/macOS/Linux notes only when behavior differs.
5. For caches or persisted state, identify the user-data file and define warm, cold, malformed, or fallback setup safely.
6. For player or browser features, mention required optional programs and cleanup expectations.

## Reinstall and report

After new commits, rerun the branch installer to update the installed copy, then recheck `lofiatc -Version`. Ask the user to report the command, platform, PowerShell version, selected player, expected result, actual result, and any verbose output.
