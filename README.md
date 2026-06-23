# Master Hand

<p align="center">
  <img src=".github/social-preview.png" alt="Master Hand project artwork" width="640">
</p>

Master Hand is a Neovim assistant that infers your current coding goal, reads repo context, and suggests safe next steps. It never edits files or runs commands unless you approve the pending action.

> [!WARNING]
> **This project is currently vibe-coded and lightly reviewed. Treat it as experimental until I have more time to harden and audit it.**

## Features

- Repo-aware context: buffers, diagnostics, git status/diffs, ripgrep, tree-sitter, local index.
- Goal-based suggestions: local heuristics plus OpenAI-compatible, OpenRouter, Ollama, or Anthropic models.
- Sidebar: review suggestions, feedback, searches, context snapshots, pending approvals.
- Safety-first: no edits or commands without approval; proposed diffs must pass `git apply --check`.

## Installation

Example `lazy.nvim` config:

```lua
{
  "artie-mortus/Master-Hand",
  name = "master-hand",
  config = function()
    require("master-hand").setup({
      proactivity = "advisory",
      model = { provider = "auto" },
    })
  end,
}
```

## Goal inference

Master Hand always keeps a current goal:

- Local heuristics infer an initial goal from recent edited lines, changed files, diagnostics, and repo state.
- The configured model refines that goal by reading recent edited lines and selected code excerpts like a human code reviewer.
- `:MasterHandGoal <goal>` overrides inference when the detected goal is wrong.

## Suggestions

Suggestions run in two stages:

1. Local heuristics inspect the current goal, diagnostics, git diff, related files, recent edits, and repo index.
2. The configured model reviews those local suggestions plus read-only code context and returns additional suggestions.

Model-backed suggestions can propose an edit or command, but nothing is applied or executed until you approve a pending action.

## Model providers

With `provider = "auto"`, Master Hand uses the first locally available Ollama model.

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

### OpenRouter

```lua
require("master-hand").setup({
  model = {
    provider = "openrouter",
    name = "anthropic/claude-3.5-sonnet",
    api_key_env = "OPENROUTER_API_KEY", -- optional default
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

## Safety

- No automatic edits or command execution
- Diffs must pass `git apply --check` before approval and before apply
- Commands use argv arrays, not shell strings
- Shell metacharacters and dangerous commands blocked
- Pending diffs kept in memory, not written to disk

## Testing

```sh
nvim --headless -u NONE -l tests/run.lua
```

