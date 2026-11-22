---
name: mac-janitor
description: Review and free disk space on a Mac with Mac Janitor's CLI. Use when the user says the disk is full, asks to clean their Mac or free space, asks what takes up space, or asks why Mac Janitor did not clean something (a worktree, node_modules, a simulator, a cache).
---

# Mac Janitor disk review

Mac Janitor's rules remove dev leftovers they can prove are safe. Your job is the rest: items a
guard kept, folders no rule covers, and things only the user can decide. You look, sort and ask.
Mac Janitor does every deletion.

## The CLI

```sh
J="/Applications/Mac Janitor.app/Contents/MacOS/MacJanitor"
[ -x "$J" ] || J="$(command -v janitor)"
```

Every command takes `--json`. Planning commands take about a minute (they fetch git remotes and ask
`gh` about PRs); run them once and reuse the output.

| Command | What it gives |
|---|---|
| `"$J" skips --json` | items a run keeps, the reason, holders (process, pid, kind: `cwd`, `open-file`, `executable`, `launch-agent`) and worktree git/PR facts |
| `"$J" unknown --min-gb 1 --json` | large folders no category covers, with size and last change |
| `"$J" plan --json` | what the next run removes anyway; no need to review these |
| `"$J" inspect <path> --json` | one path: category, verdict, pinned, holders, git/PR state, matched items inside |
| `"$J" remove <path> --yes --json` | removes one item through the run's guards, salvage and log |
| `"$J" pin <path>` / `unpin <path>` | keep a path for good, or stop keeping it |

## Steps

1. Run `df -h ~`, then `skips --json` and `unknown --min-gb 1 --json`.
2. Check each candidate with the tool that knows it:
   - Holders: `ps -o pid,etime,command -p <pid>`. An idle shell or a dead dev server differs from an
     editor with unsaved work.
   - Worktrees and checkouts: `git -C <path> status --short`, `git -C <path> log -1 --format=%cr`,
     `git -C <path> rev-list --count @{u}..` and `gh pr view <branch> --json state,mergedAt`.
   - Simulators: `xcrun simctl list devices booted`. A booted, idle simulator is never removed while
     booted.
   - Unknown folders: `ls -la`, `du -sh <path>/* | sort -h | tail`, and what made it (a tool's
     cache, a download, a project).
3. Sort every item into one of three lists, one line each with size and reason:
   - **Safe**: a rule would take it once the holder is gone, or it is plainly regenerable.
   - **Needs the user**: unpushed work, open PRs, media, anything you cannot prove is regenerable.
   - **Keep**: in active use, or the user's own data.
4. Show the lists and ask which to act on. Act only on what the user confirms:
   - Item in a category: `"$J" remove <path> --yes --json`. If it refuses, report the reason; do
     not work around it.
   - Booted simulator: ask, then `xcrun simctl shutdown <udid>`; a later run or `remove` takes it
     once it is idle long enough.
   - Holder process: ask before stopping anything; name the pid and command.
   - Something the user wants kept: `"$J" pin <path>`.
5. End with what was freed (`df -h ~` again) and a short list of repeated patterns that could
   become rules (for example "`~/.t3/projects/*/out/DerivedData` older than 7 days").

## Rules

- Never delete with `rm`, `trash`, `git worktree remove` or `simctl delete`. Only `janitor remove`,
  and only after the user confirms that item.
- Never stop a process or shut down a simulator without asking.
- `unknown` folders match no category, so `remove` refuses them. Tell the user what they are and
  let them delete by hand if they want.
- Without Full Disk Access for the terminal, Desktop, Documents and Downloads are skipped; the
  `issues` list says so.
