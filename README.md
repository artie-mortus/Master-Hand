# Master Hand

<p align="center">
  <img src=".github/social-preview.png" alt="Master Hand project artwork" width="640">
</p>

<p align="center">
  <strong>Models as helpers, not autopilot.</strong><br>
  Ask for context-aware suggestions, review the help, then approve what should happen.
</p>

> [!WARNING]
> Experimental plugin. Vibe-coded, lightly reviewed, and not yet hardened. Keep backups and review every approved action.

## What Master Hand is

Master Hand is not an autonomous coding agent by default. It is a **deliberate helper layer for model use**: open it when you want a second set of eyes, give it a goal, let local context and optional models suggest next steps, then choose what to do.

Think of it as an assistant that sits beside your editor and says: "here is likely useful help; want to act on it?" It keeps you in control.

## Why use it?

| Strength | What it does |
| --- | --- |
| **Repo-aware next steps** | Combines buffers, diagnostics, git changes, recent edits, ripgrep hits, tree-sitter symbols, and a bounded repo index. |
| **Fast sidebar UX** | `:MH` opens immediately; model-backed suggestions load async with a spinner. |
| **Intentional model use** | Built for times when you want AI help, not background autonomy. You open it, ask, review, then approve. |
| **Safe automation boundary** | Suggestions are advisory by default; diffs, commands, and agent handoffs require explicit approval. |
| **Model optional** | Works with local heuristics only, local Ollama, Ollama Cloud, OpenAI-compatible APIs, OpenRouter, or Anthropic. |
| **Goal steering** | `:MHGoal` tells the helper what you are trying to do and blends it with short-term repo state. |
| **Agent handoff** | Approved suggestions can go to pi, Codex, tmux, Zellij, a Neovim terminal, or custom argv command. |

---

<details open>
<summary><strong>🚀 Quick start</strong></summary>

```vim
:MH                         " open sidebar; starts async suggestions if empty
:MHSuggest                  " refresh suggestions
:MHPlan                     " ask for plan-style suggestions
:MHGoal Fix login redirect  " set long-term steering goal
:MHModel                    " show active model config
:MHModelStatus              " test model connection
:MHSend 1                   " send suggestion #1 to configured external agent
:MHSync                     " refresh buffers after external edits
```

Sidebar keys:

| Key | Action |
| --- | --- |
| `a` | Accept/useful feedback; if `agent.enabled`, approve/send selected suggestion |
| `d` | Dismiss suggestion |
| `p` | Postpone suggestion |
| `v` | View details |
| `r` | Refresh suggestions |
| `q` | Close sidebar |

By default, `a` records feedback only. With `agent.enabled = true`, `a` sends the selected suggestion to the configured external coding agent and starts short-lived `:checktime` polling so Neovim notices saved edits.

Intentional flow: **open → ask/goal → read suggestions → approve only useful help**.

</details>

<details>
<summary><strong>📦 Requirements</strong></summary>

- Neovim 0.10+
- `git` for status/diff context
- Optional tools:
  - `rg` for repo search
  - tree-sitter parsers for symbol context
  - `curl` for remote model providers
  - `ollama` for local `provider = "auto"` / `provider = "ollama"`
  - `pi`, `codex`, `tmux`, or `zellij` for external agent handoff

</details>

<details open>
<summary><strong>🧩 Installation</strong></summary>

Minimal `lazy.nvim` setup:

```lua
{
  "artie-mortus/Master-Hand",
  name = "master-hand",
  config = function()
    require("master-hand").setup()
  end,
}
```

Default mode is intentionally quiet:

```lua
require("master-hand").setup({
  proactivity = "passive", -- suggestions only when you run :MH, :MHSuggest, or :MHPlan
})
```

Enable debounced suggestion refreshes after edits/diagnostics:

```lua
require("master-hand").setup({
  proactivity = "advisory",
  suggestion_frequency_ms = 5000,
  model = { provider = "auto" },
})
```

</details>

<details>
<summary><strong>🎛️ Configuration recipes</strong></summary>

### Sidebar layout and colors

```lua
require("master-hand").setup({
  ui = {
    width = 46,
    max_width_ratio = 0.45,
    side = "right", -- or "left"
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
```

The sidebar uses `winfixwidth` and reapplies width on `VimResized`, so terminal/i3/fullscreen resizes should not stretch it across the editor.

### Local-only suggestions

```lua
require("master-hand").setup({
  model = { provider = "none" },
})
```

### Local Ollama auto-pick

```lua
require("master-hand").setup({
  model = { provider = "auto" }, -- picks local coder/code/Qwen model when available
})
```

### OpenAI-compatible API

```lua
require("master-hand").setup({
  model = {
    provider = "openai_compatible",
    endpoint = "https://api.openai.com/v1/chat/completions",
    name = "gpt-4.1-mini",
    api_key_env = "OPENAI_API_KEY",
  },
})
```

### Ollama Cloud

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

</details>

<details>
<summary><strong>⌨️ Commands</strong></summary>

| Command | Alias | Description |
| --- | --- | --- |
| `:MasterHand` | `:MH` | Open sidebar; async-load suggestions if empty |
| `:MasterHandClose` | `:MHClose` | Close sidebar |
| `:MasterHandGoal <goal>` | `:MHGoal <goal>` | Set long-term steering goal |
| `:MasterHandPlan` | `:MHPlan` | Generate plan-style suggestions |
| `:MasterHandSuggest` | `:MHSuggest` | Refresh suggestions asynchronously |
| `:MasterHandModelSuggest` | `:MHModelSuggest` | Alias for `:MHSuggest` |
| `:MasterHandStatus` | `:MHStatus` | Print cached context summary |
| `:MasterHandModel [args]` | `:MHModel [args]` | Show/change runtime model config |
| `:MasterHandModelStatus` | `:MHModelStatus` | Test configured model connection |
| `:MasterHandContext` | `:MHContext` | Show cached context snapshot |
| `:MasterHandIndex` | `:MHIndex` | Show cached repo index |
| `:MasterHandDiff [request]` | `:MHDiff [request]` | Prepare model-proposed diff for approval |
| `:MasterHandApprove [id]` | `:MHApprove [id]` | Approve pending action |
| `:MasterHandReject [id]` | `:MHReject [id]` | Reject pending action |
| `:MasterHandRun <argv...>` | `:MHRun <argv...>` | Queue command for approval |
| `:MasterHandPending` | `:MHPending` | Show pending actions |
| `:MasterHandApproveSuggestion [n]` | `:MHSend [n]` | Send approved suggestion to external agent |
| `:MasterHandSync` | `:MHSync` | Refresh buffers after external edits |
| `:MasterHandSearch <query>` | `:MHSearch <query>` | Search repo with ripgrep |

</details>

<details>
<summary><strong>🧠 Suggestion workflow</strong></summary>

Suggestions are meant to support intentional model use, not replace judgment. You decide when to ask, what context to provide through goals, and which suggestions deserve action.

Suggestions run in two stages:

1. **Local heuristics** inspect steering goals, diagnostics, git diff, related files, recent edits, and repo index.
2. **Optional model review** reads bounded, read-only context and returns extra suggestions.

Proactivity modes:

- `passive` — default. Only explicit commands generate suggestions.
- `advisory`, `proactive`, `high_initiative` — currently share same safe behavior: editor events debounce suggestion refreshes, but still never edit files or run commands automatically.

Goal steering:

- Long-term goal captures user/project direction.
- Short-term goal comes from recent edits, changed files, diagnostics, and repo state.
- `:MHGoal <goal>` overrides long-term steering when inferred direction is wrong.

</details>

<details>
<summary><strong>🤖 Models</strong></summary>

With `provider = "auto"`, Master Hand uses local Ollama when available, preferring coder/code/Qwen models. If no model is reachable, local heuristic suggestions still work. Use `provider = "none"` to disable model calls.

Runtime model switching:

```vim
:MHModel                         " show current model
:MHModel auto                    " local Ollama auto-pick
:MHModel none                    " disable model calls
:MHModel qwen3-coder:latest      " infer local Ollama
:MHModel ollama qwen3-coder:latest
:MHModel ollama-cloud gpt-oss:120b
:MHModel openai gpt-4.1-mini
:MHModel openrouter anthropic/claude-3.5-sonnet
:MHModel anthropic claude-sonnet-4-20250514
```

Advanced key/value form:

```vim
:MHModel provider=openai model=gpt-4.1-mini endpoint=https://api.openai.com/v1/chat/completions api_key_env=OPENAI_API_KEY
:MHModel provider=ollama-cloud model=gpt-oss:120b
```

`:MHModel` changes runtime config for current Neovim session. Put the same config in `setup()` for persistent defaults.

</details>

<details>
<summary><strong>🛫 Agent handoff</strong></summary>

Agent handoff is disabled by default. Enable only when you want approved suggestions to leave Neovim and go to another coding agent.

```lua
require("master-hand").setup({
  agent = {
    enabled = true,
    adapter = "codex", -- codex exec <prompt>
  },
})
```

Adapters:

- `auto` — tmux target if available, else Zellij pane if inside Zellij, else Neovim terminal split
- `pi` — runs `pi <prompt>` or `executable <prompt>`
- `codex` — runs `codex exec <prompt>`
- `tmux` — sends prompt to `agent.target` or `MASTER_HAND_TMUX_TARGET`
- `zellij` — starts a pane named `Master Hand Agent`
- `terminal` — opens a Neovim terminal split

Custom argv template:

```lua
require("master-hand").setup({
  agent = {
    enabled = true,
    command = { "pi", "{prompt}" }, -- argv only; no shell string
  },
})
```

Template variables: `{prompt}`, `{root}`, `{prompt_q}`, `{root_q}`.

Tmux target example:

```lua
require("master-hand").setup({
  agent = {
    enabled = true,
    adapter = "tmux",
    target = "master-hand-agent", -- or MASTER_HAND_TMUX_TARGET
  },
})
```

Zellij example:

```lua
require("master-hand").setup({
  agent = { enabled = true, adapter = "zellij", executable = "pi" },
})
```

After handoff, Master Hand runs `:checktime` for a short window so saved external edits reload into Neovim. Use `:MHSync` to refresh manually.

</details>

<details>
<summary><strong>🧾 Configuration reference</strong></summary>

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
    max_file_bytes = 12000,
    max_search_results = 40,
    max_model_code_files = 8,
    max_model_file_bytes = 12000,
    include_related_files = true,
    include_symbols = true,
    include_index = true,
  },
  commands = {
    allowlist = { "git", "make", "npm", "pnpm", "yarn", "cargo", "go", "pytest", "python", "lua", "nvim" },
    blocklist = { "rm", "sudo", "git reset", "git clean" },
    timeout_ms = 10000,
  },
  agent = {
    enabled = false,
    adapter = "auto",
    auto_checktime = true,
  },
  storage = { enabled = true },
  ui = {
    width = 46,
    max_width_ratio = 0.45,
    side = "right",
    show_diff_preview = true,
    highlights = {},
  },
})
```

Long-term goal and feedback persist to:

```text
stdpath("state") .. "/master-hand/state.json"
```

Configurable sidebar highlight groups:

```text
MasterHandTitle MasterHandRule MasterHandSection MasterHandContext
MasterHandModel MasterHandLoading MasterHandSuggestionIndex
MasterHandSuggestionTitle MasterHandReason MasterHandMeta
MasterHandApproval MasterHandFiles MasterHandNext MasterHandPending
MasterHandKeys
```

</details>

<details>
<summary><strong>🔒 Safety model</strong></summary>

- No automatic edits or command execution.
- Accepting a suggestion records feedback only unless `agent.enabled = true`.
- Diffs must pass `git apply --check` before approval and before apply.
- Commands use argv arrays, not shell strings.
- Shell metacharacters and dangerous commands are blocked.
- Pending diffs live in memory, not on disk.
- Model/provider failures degrade to local heuristic suggestions.

</details>

<details>
<summary><strong>✅ Testing</strong></summary>

From repo root:

```sh
nvim --headless -u NONE +'set rtp+=.' -l tests/run.lua
```

</details>
