# Master Hand

Neovim-first AI coding assistant between tab completion and autonomous agents.

Master Hand observes repository activity, tracks an optional development goal, and surfaces advisory next steps. It never edits files or runs commands without explicit approval.

## Features

- Neovim Lua plugin
- repo context: buffers, edits, diagnostics, git status/diff, branch, tracked files
- goal-driven suggestions via `:MHGoal`
- observer-mode heuristic suggestions
- optional OpenAI-compatible model provider
- structured suggestions: title, reason, files, confidence, next action, approval flag
- sidebar UI with accept/dismiss/postpone feedback
- persisted goal/feedback in Neovim state dir
- pending action registry
- approved command runner with blocklist/allowlist
- proposed diff generation/preview/apply after approval
- ignored paths for privacy: `.git/`, `node_modules/`, `.env*`, build dirs

## Install with lazy.nvim

```lua
{
  dir = "/home/artemis/projects/Master Hand",
  name = "master-hand",
  config = function()
    require("master-hand").setup({
      proactivity = "advisory",
      model = { provider = "none" },
    })
  end,
}
```

## Optional model provider

OpenAI-compatible endpoint:

```lua
require("master-hand").setup({
  model = {
    provider = "openai_compatible",
    endpoint = "http://localhost:11434/v1/chat/completions",
    name = "qwen2.5-coder",
    api_key_env = nil,
  },
})
```

## Commands

- `:MasterHand` / `:MH` open sidebar
- `:MasterHandClose` / `:MHClose` close sidebar
- `:MasterHandGoal <goal>` / `:MHGoal <goal>` set active goal
- `:MasterHandPlan` / `:MHPlan` generate plan suggestions
- `:MasterHandSuggest` / `:MHSuggest` refresh suggestions
- `:MasterHandStatus` / `:MHStatus` print context summary
- `:MasterHandContext` / `:MHContext` show context snapshot
- `:MasterHandDiff [request]` / `:MHDiff [request]` prepare proposed diff via model
- `:MasterHandApprove [id]` / `:MHApprove [id]` approve pending action
- `:MasterHandReject [id]` / `:MHReject [id]` reject pending action
- `:MasterHandRun <argv...>` / `:MHRun <argv...>` create approved command action
- `:MasterHandPending` / `:MHPending` show pending actions

## Safety model

Default behavior:

- reads repo context only, respecting ignored paths
- no automatic edits
- no automatic command execution
- proposed diffs run `git apply --check` before approval and before apply
- commands are argv-only, no shell metacharacters, dangerous commands blocked
- feedback is persisted; pending diffs are not persisted

## Test

```sh
nvim --headless -u NONE +'set rtp+=.' +'lua require("master-hand").setup({ model = { provider = "none" }, storage = { enabled = false } })' +'lua require("master-hand").suggest()' +qa
nvim --headless -u NONE +'set rtp+=.' +'luafile tests/run.lua' +qa
```

## MVP exclusions

Master Hand remains advisory. It does not autonomously implement features, run destructive commands, or make broad architecture changes without explicit approval.
