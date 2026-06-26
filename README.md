# Master Hand

<p align="center">
  <img src=".github/social-preview.png" alt="Master Hand project artwork" width="640">
</p>

Master Hand is an experimental Neovim assistant that watches repo/editor context, infers long-term steering plus short-term next work, and suggests safe next steps. Local heuristics run first; model calls add optional review. It never edits files or runs commands unless you approve an explicit pending action.

> [!WARNING]
> **This project is vibe-coded and lightly reviewed. Treat it as experimental until hardened.**

## Features

- **Repo-aware suggestions** — uses open buffers, diagnostics, git changes, recent edits, ripgrep hits, tree-sitter symbols, and a bounded repo index.
- **Model-backed review** — combines local heuristics with Ollama, Ollama Cloud, OpenAI-compatible APIs, OpenRouter, or Anthropic.
- **Non-blocking sidebar** — `:MH` opens immediately; model suggestions load async with a spinner.
- **In-editor model switching** — change providers/models at runtime with `:MHModel`.
- **Approval-first safety** — model diffs, commands, and agent handoffs wait behind pending actions or explicit suggestion approval.
- **Agent handoff** — approved suggestions can be sent to pi, Codex, tmux, Zellij, a Neovim terminal, or a custom argv command, then buffers refresh with `:checktime`.

## Requirements

- Neovim 0.10+.
- `git` for repo status/diff context.
- Optional: `rg` for repo search, tree-sitter parsers for symbols, `curl` for remote model providers, `ollama` for local auto-provider, `pi`/`codex`/`tmux`/`zellij` for agent handoff.

<details open>
<summary><h2>Installation</h2></summary>


Minimal safe `lazy.nvim` config:

```lua
{
  "artie-mortus/Master-Hand",
  name = "master-hand",
  config = function()
    require("master-hand").setup()
  end,
}
```

### Configure sidebar from lazy.nvim

Put sidebar size, side, and colors in `setup()`:

```lua
{
  "artie-mortus/Master-Hand",
  name = "master-hand",
  config = function()
    require("master-hand").setup({
      ui = {
        width = 46,
        max_width_ratio = 0.45,
        side = "right", -- "left" also works
        highlights = {
          MasterHandTitle = { fg = "#89b4fa", bold = true },
          MasterHandSection = { fg = "#cba6f7", bold = true },
          MasterHandSuggestionTitle = { fg = "#fab387" },
          MasterHandApproval = { fg = "#f38ba8", bold = true },
          MasterHandNext = { fg = "#a6e3a1" },
          MasterHandKeys = { link = "Question" },
        },
      },
    })
  end,
}
```

Default `proactivity = "passive"`: no typing-triggered model work. Use advisory mode if you want debounced refreshes after edits/diagnostics:

```lua
require("master-hand").setup({
  proactivity = "advisory",
  suggestion_frequency_ms = 5000,
  model = { provider = "auto" },
})
```


</details>

## Quick start

```vim
:MH                         " open sidebar; starts async suggestions if empty
:MHSuggest                  " refresh model-backed suggestions
:MHGoal Fix login redirect  " steer long-term goal
:MHModel                    " show active model
:MHModel qwen3-coder-local:latest
:MHModelStatus              " test model connection
:MHSend 1                   " send suggestion #1 to configured external agent
:MHSync                     " refresh buffers after external agent edits
```

Inside sidebar:

| Key | Action |
| --- | --- |
| `a` | Mark suggestion accepted/useful; if `agent.enabled`, approve/send to external agent |
| `d` | Dismiss suggestion |
| `p` | Postpone suggestion |
| `v` | View details |
| `r` | Refresh suggestions |
| `q` | Close |

By default, `a` records feedback only. With `agent.enabled = true`, `a` approves the selected suggestion, sends it to your configured external coding agent, and polls `:checktime` so Neovim sees saved edits. Local diffs and commands still go through pending actions plus `:MHApprove`.

<details>
<summary><h2>Proactivity modes</h2></summary>


- `passive` — default. Only explicit commands such as `:MH`, `:MHSuggest`, or `:MHPlan` generate suggestions.
- `advisory`, `proactive`, `high_initiative` — currently share same safe behavior: editor events debounce suggestion refreshes, but still never edit files or run commands automatically.

Editor autocmds track edits/diagnostics and start suggestion refreshes only when proactivity is not `passive`.


</details>

<details>
<summary><h2>How suggestions work</h2></summary>


Suggestions run in two stages:

1. Local heuristics inspect steering goals, diagnostics, git diff, related files, recent edits, and repo index.
2. Configured model reviews those local suggestions plus read-only code context and returns extra suggestions.

`:MH` shows the sidebar immediately. If suggestions are empty, Master Hand starts model-backed suggestion generation in the background and shows a loading spinner instead of blocking Neovim.


</details>

<details>
<summary><h2>Goal steering</h2></summary>


Master Hand keeps steering intent instead of one hard task:

- Long-term goal captures user/project direction.
- Short-term goal captures immediate repo-aware work from recent edits, changed files, diagnostics, and repo state.
- The model can refine both goals from read-only context.
- `:MHGoal <goal>` sets long-term steering when inferred direction is wrong.


</details>

<details>
<summary><h2>Model providers</h2></summary>


With `provider = "auto"`, Master Hand uses a local Ollama model when available, preferring coder/code/Qwen models. If no model is reachable, local heuristic suggestions still work. Use `provider = "none"` to disable model calls.

Cold local models can take time to load, so default model timeout is 60 seconds. Run `:MHModelStatus` to test provider connectivity.

### Change model in Neovim

```vim
:MHModel                  " show current model
:MHModel gpt-5.5          " OpenAI (sets endpoint + OPENAI_API_KEY)
:MHModel openai gpt-5.5
:MHModel qwen3-coder-local:latest
:MHModel ollama qwen3-coder-local:latest
:MHModel ollama-cloud gpt-oss:120b " Ollama Cloud (sets OLLAMA_API_KEY)
:MHModel openrouter anthropic/claude-3.5-sonnet
:MHModel anthropic claude-sonnet-4-20250514
:MHModel auto
:MHModel none
```

Model name alone is inferred: `gpt-4*`/`gpt-5*`/`o*` uses OpenAI; everything else uses local Ollama. For Ollama Cloud, use `ollama-cloud <model>` so Master Hand sets `https://ollama.com/api/chat` and `OLLAMA_API_KEY`. Advanced `key=value` form still works when needed:

```vim
:MHModel provider=openai model=gpt-5.5 endpoint=https://api.openai.com/v1/chat/completions api_key_env=OPENAI_API_KEY
:MHModel provider=ollama-cloud model=gpt-oss:120b
```

`:MHModel` changes runtime config for the current Neovim session. Add same model to `setup()` for permanent default.

### Agent handoff

Keep default disabled for safety. Enable it when you want approved suggestions to leave Neovim and go to another coding agent:

```lua
require("master-hand").setup({
  agent = {
    enabled = true,
    adapter = "codex", -- codex exec <prompt>
  },
})
```

Adapters:

- `auto` — tmux target if available, else Zellij pane if inside Zellij, else Neovim terminal split.
- `pi` — runs `pi <prompt>` or `executable <prompt>`.
- `codex` — runs `codex exec <prompt>`.
- `tmux` — sends prompt to `agent.target` or `MASTER_HAND_TMUX_TARGET`.
- `zellij` — starts a pane named `Master Hand Agent`.
- `terminal` — opens a Neovim terminal split.

Custom command template:

```lua
require("master-hand").setup({
  agent = {
    enabled = true,
    command = { "pi", "{prompt}" }, -- argv only; no shell string
  },
})
```

Template variables: `{prompt}`, `{root}`, `{prompt_q}`, `{root_q}`.

Tmux target pane/window:

```lua
require("master-hand").setup({
  agent = {
    enabled = true,
    adapter = "tmux",
    target = "master-hand-agent", -- or MASTER_HAND_TMUX_TARGET
  },
})
```

Zellij starts a new pane with `pi` by default:

```lua
require("master-hand").setup({
  agent = { enabled = true, adapter = "zellij", executable = "pi" },
})
```

After handoff, Master Hand runs `:checktime` for a short window so saved external edits reload into Neovim. Use `:MHSync` to refresh manually.

### Config examples

OpenAI API:

```lua
require("master-hand").setup({
  model = {
    provider = "openai_compatible", -- OpenAI chat-completions wire format
    endpoint = "https://api.openai.com/v1/chat/completions",
    name = "gpt-5.5",
    api_key_env = "OPENAI_API_KEY",
  },
})
```

`openai_compatible` means API shape, not model vendor. For Qwen or `gpt-oss` via Ollama, use the native Ollama provider below.

Local Ollama:

```lua
require("master-hand").setup({
  model = {
    provider = "ollama",
    endpoint = "http://localhost:11434/api/chat", -- optional default
    name = "qwen3-coder-local:latest",
  },
})
```

Ollama Cloud:

```lua
require("master-hand").setup({
  model = {
    provider = "ollama",
    endpoint = "https://ollama.com/api/chat",
    name = "gpt-oss:120b",
    api_key_env = "OLLAMA_API_KEY",
  },
})
```

OpenRouter:

```lua
require("master-hand").setup({
  model = {
    provider = "openrouter",
    name = "anthropic/claude-3.5-sonnet",
    api_key_env = "OPENROUTER_API_KEY",
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


</details>

<details>
<summary><h2>Commands</h2></summary>


| Command | Alias | Description |
| --- | --- | --- |
| `:MasterHand` | `:MH` | Open sidebar; async-load suggestions if empty |
| `:MasterHandClose` | `:MHClose` | Close sidebar |
| `:MasterHandGoal <goal>` | `:MHGoal <goal>` | Set long-term steering goal |
| `:MasterHandPlan` | `:MHPlan` | Generate model-backed plan suggestions |
| `:MasterHandSuggest` | `:MHSuggest` | Refresh model-backed suggestions asynchronously |
| `:MasterHandModelSuggest` | `:MHModelSuggest` | Alias for `:MHSuggest` |
| `:MasterHandStatus` | `:MHStatus` | Print cached context summary |
| `:MasterHandModel [args]` | `:MHModel [args]` | Show/change runtime model config |
| `:MasterHandModelStatus` | `:MHModelStatus` | Test configured model connection |
| `:MasterHandContext` | `:MHContext` | Show cached context snapshot |
| `:MasterHandIndex` | `:MHIndex` | Show cached local repo index |
| `:MasterHandDiff [request]` | `:MHDiff [request]` | Prepare model-proposed diff |
| `:MasterHandApprove [id]` | `:MHApprove [id]` | Approve pending action |
| `:MasterHandReject [id]` | `:MHReject [id]` | Reject pending action |
| `:MasterHandRun <argv...>` | `:MHRun <argv...>` | Queue command for approval |
| `:MasterHandPending` | `:MHPending` | Show pending actions |
| `:MasterHandApproveSuggestion [n]` | `:MHSend [n]` | Send approved suggestion to configured external agent |
| `:MasterHandSync` | `:MHSync` | Refresh buffers after external edits |
| `:MasterHandSearch <query>` | `:MHSearch <query>` | Search repo with ripgrep |


</details>

<details>
<summary><h2>Configuration reference</h2></summary>


Defaults live in `lua/master-hand/config.lua`. Common options:

```lua
require("master-hand").setup({
  proactivity = "passive", -- passive | advisory | proactive | high_initiative
  suggestion_frequency_ms = 5000,
  ignore = { ".git/", "node_modules/", "dist/", "build/", ".env", ".env.*" },
  model = {
    provider = "auto", -- none | auto | openai_compatible | openrouter | ollama | anthropic
    timeout_ms = 60000,
    temperature = 0.2,
    max_tokens = 1200,
  },
  context = {
    max_files = 80,
    max_diff_bytes = 24000,
    max_search_results = 40,
    include_related_files = true,
    include_symbols = true,
    include_index = true,
  },
  commands = {
    allowlist = { "git", "make", "npm", "pnpm", "yarn", "cargo", "go", "pytest", "python", "lua", "nvim" },
    blocklist = { "rm", "sudo", "git reset", "git clean" },
    timeout_ms = 10000,
  },
  storage = { enabled = true },
  ui = {
    width = 46,
    max_width_ratio = 0.45,
    side = "right",
    highlights = {
      MasterHandTitle = { fg = "#89b4fa", bold = true },
      MasterHandSection = { fg = "#cba6f7", bold = true },
      MasterHandApproval = { fg = "#f38ba8", bold = true },
      MasterHandNext = { fg = "#a6e3a1" },
    },
  },
})
```

Long-term goal and feedback persist to `stdpath("state") .. "/master-hand/state.json"` when storage is enabled.


</details>

<details>
<summary><h2>Sidebar config</h2></summary>


```lua
require("master-hand").setup({
  ui = {
    width = 46,
    max_width_ratio = 0.45,
    side = "right",
    highlights = {
      MasterHandTitle = { fg = "#89b4fa", bold = true },
      MasterHandSection = { link = "Statement" },
      MasterHandSuggestionTitle = { fg = "#fab387" },
      MasterHandKeys = { link = "Question" },
    },
  },
})
```

The sidebar uses `winfixwidth` and reapplies width on `VimResized`, so i3/fullscreen terminal resizes should not stretch it across the editor.

Configurable sidebar highlight groups: `MasterHandTitle`, `MasterHandRule`, `MasterHandSection`, `MasterHandContext`, `MasterHandModel`, `MasterHandLoading`, `MasterHandSuggestionIndex`, `MasterHandSuggestionTitle`, `MasterHandReason`, `MasterHandMeta`, `MasterHandApproval`, `MasterHandFiles`, `MasterHandNext`, `MasterHandPending`, `MasterHandKeys`.


</details>

<details>
<summary><h2>Safety model</h2></summary>


- No automatic edits or command execution.
- Accepting a suggestion records feedback only unless `agent.enabled` is explicitly set.
- Diffs must pass `git apply --check` before approval and before apply.
- Commands use argv arrays, not shell strings.
- Shell metacharacters and dangerous commands are blocked.
- Pending diffs live in memory, not on disk.


</details>

<details>
<summary><h2>Testing</h2></summary>


```sh
nvim --headless -u NONE -l tests/run.lua
```

</details>
