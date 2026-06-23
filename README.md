# Master Hand

<p align="center">
  <img src=".github/social-preview.png" alt="Master Hand project artwork" width="640">
</p>

Master Hand is a Neovim plugin for repo-aware coding suggestions.

It observes editor and repository state, infers a current goal from your edits, and suggests useful next steps. When a model is configured, it can refine the inferred goal by reading recent edited lines and code excerpts. You can override the inferred goal at any time. It never edits files or runs commands unless you approve the pending action.

> [!WARNING]
> This project is currently vibe-coded and lightly reviewed. Treat it as experimental until I have more time to harden and audit it.

## Features

- Repo-aware context from buffers, diagnostics, git status/diffs, ripgrep, tree-sitter, and a local index.
- Goal-based suggestions from local heuristics, with optional OpenAI-compatible, Ollama, or Anthropic models.
- Sidebar workflow for reviewing suggestions, feedback, searches, context snapshots, and pending approvals.
- Safety-first actions: no edits or commands run without approval; proposed diffs must pass `git apply --check`.

## Installation

Example `lazy.nvim` config:

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

## Model providers

Models are optional. With `provider = "none"`, Master Hand uses local heuristics only.

### OpenAI-compatible

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

### Ollama

```lua
require("master-hand").setup({
  model = {
    provider = "ollama",
    endpoint = "http://localhost:11434/api/chat", -- optional default
    name = "qwen2.5-coder",
  },
})
```

### Anthropic

```lua
require("master-hand").setup({
  model = {
    provider = "anthropic",
    name = "claude-sonnet-4-20250514",
    api_key_env = "ANTHROPIC_API_KEY",
  },
})
```

## Commands

| Command | Alias | Description |
| --- | --- | --- |
| `:MasterHand` | `:MH` | Open sidebar |
| `:MasterHandClose` | `:MHClose` | Close sidebar |
| `:MasterHandGoal <goal>` | `:MHGoal <goal>` | Override inferred goal |
| `:MasterHandPlan` | `:MHPlan` | Generate plan suggestions |
| `:MasterHandSuggest` | `:MHSuggest` | Refresh suggestions |
| `:MasterHandStatus` | `:MHStatus` | Print context summary |
| `:MasterHandContext` | `:MHContext` | Show context snapshot |
| `:MasterHandIndex` | `:MHIndex` | Show local repo index |
| `:MasterHandDiff [request]` | `:MHDiff [request]` | Prepare model-proposed diff |
| `:MasterHandApprove [id]` | `:MHApprove [id]` | Approve pending action |
| `:MasterHandReject [id]` | `:MHReject [id]` | Reject pending action |
| `:MasterHandRun <argv...>` | `:MHRun <argv...>` | Queue command for approval |
| `:MasterHandPending` | `:MHPending` | Show pending actions |
| `:MasterHandSearch <query>` | `:MHSearch <query>` | Search repo with ripgrep |

## Sidebar keys

| Key | Action |
| --- | --- |
| `a` | Accept suggestion |
| `d` | Dismiss suggestion |
| `p` | Postpone suggestion |
| `v` | View details |
| `r` | Refresh |
| `q` | Close |

## Safety model

- No automatic edits
- No automatic command execution
- Diffs must pass `git apply --check` before approval and before apply
- Commands use argv arrays, not shell strings
- Shell metacharacters and dangerous commands are blocked
- Pending diffs are kept in memory and not written to disk

## Testing

Smoke test:

```sh
nvim --headless -u NONE +'set rtp+=.' +'lua require("master-hand").setup({ model = { provider = "none" }, storage = { enabled = false } })' +'lua require("master-hand").suggest()' +qa
```

Full test run:

```sh
nvim --headless -u NONE +'set rtp+=.' +'luafile tests/run.lua' +qa
```

