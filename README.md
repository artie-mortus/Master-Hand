# Master Hand

Neovim plugin for repo-aware coding suggestions.

It watches basic editor/repo state, keeps an optional goal, and shows suggested next steps. It does not edit files or run commands unless you approve the pending action.

## What works

- Neovim Lua plugin
- sidebar UI
- open buffer / recent edit tracking
- diagnostics summary
- git branch/status/diff context
- ripgrep related-file search for goal terms
- tree-sitter symbols for current buffer when available
- `:MHGoal` for a current task
- local heuristic suggestions
- optional model providers: OpenAI-compatible, Ollama, Anthropic
- accept / dismiss / postpone feedback
- persisted goal and feedback
- pending command approval
- proposed diff preview/apply after approval
- ignore list for `.git/`, `node_modules/`, `.env*`, build dirs

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

Ollama native API:

```lua
require("master-hand").setup({
  model = {
    provider = "ollama",
    endpoint = "http://localhost:11434/api/chat", -- optional default
    name = "qwen2.5-coder",
  },
})
```

Anthropic:

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
| `:MasterHand` | `:MH` | open sidebar |
| `:MasterHandClose` | `:MHClose` | close sidebar |
| `:MasterHandGoal <goal>` | `:MHGoal <goal>` | set goal |
| `:MasterHandPlan` | `:MHPlan` | generate plan suggestions |
| `:MasterHandSuggest` | `:MHSuggest` | refresh suggestions |
| `:MasterHandStatus` | `:MHStatus` | print context summary |
| `:MasterHandContext` | `:MHContext` | show context snapshot |
| `:MasterHandDiff [request]` | `:MHDiff [request]` | prepare proposed diff via model |
| `:MasterHandApprove [id]` | `:MHApprove [id]` | approve pending action |
| `:MasterHandReject [id]` | `:MHReject [id]` | reject pending action |
| `:MasterHandRun <argv...>` | `:MHRun <argv...>` | queue command for approval |
| `:MasterHandPending` | `:MHPending` | show pending actions |
| `:MasterHandSearch <query>` | `:MHSearch <query>` | run repo search |

## Sidebar keys

- `a` accept suggestion
- `d` dismiss suggestion
- `p` postpone suggestion
- `v` view details
- `r` refresh
- `q` close

## Safety

- No automatic edits.
- No automatic command execution.
- Diffs must pass `git apply --check` before approval and again before apply.
- Commands use argv, not shell strings.
- Shell metacharacters and dangerous commands are blocked.
- Pending diffs are not saved to disk.

## Test

```sh
nvim --headless -u NONE +'set rtp+=.' +'lua require("master-hand").setup({ model = { provider = "none" }, storage = { enabled = false } })' +'lua require("master-hand").suggest()' +qa
nvim --headless -u NONE +'set rtp+=.' +'luafile tests/run.lua' +qa
```

## Non-goals

- no autonomous feature implementation
- no background shell agent
- no destructive commands
- no broad architecture changes without explicit approval
