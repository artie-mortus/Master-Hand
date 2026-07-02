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

Master Hand is not an autonomous coding agent. It is a helper layer you open when you want a second set of eyes: give it a goal, let local context and optional models suggest next steps, then choose what to do.

| Feature | What it does |
| --- | --- |
| **Repo-aware next steps** | Combines buffers, diagnostics, git changes, recent edits, ripgrep hits, tree-sitter symbols, and a bounded repo index. |
| **Approval boundary** | Suggestions are advisory; diffs, commands, and agent handoffs require explicit approval. |
| **Model optional** | Works with local heuristics only, local Ollama, Ollama Cloud, OpenAI-compatible APIs, OpenRouter, Anthropic, Pi, or login-backed CLI subscriptions (Codex/Claude/Gemini). |
| **Goal steering** | `:MHGoal` sets long-term direction; `:MHNext` pins the short-term next step, or Master Hand infers it from repo state. |
| **Agent handoff** | Approved suggestions can go to pi, Codex, tmux, Zellij, a Neovim terminal, or a custom argv command. |

## Install

lazy.nvim:

```lua
-- minimal (passive mode, agent handoff after approval)
{ "artie-mortus/Master-Hand", name = "master-hand", cmd = { "MH", "MasterHand", "MHSuggest", "MHPlan", "MHSend" }, opts = {} }

-- with explicit agent/model choices
{
  "artie-mortus/Master-Hand",
  name = "master-hand",
  cmd = { "MH", "MasterHand", "MHSuggest", "MHPlan", "MHSend" },
  keys = { { "<leader>mh", "<cmd>MH<cr>", desc = "Master Hand" } },
  opts = {
    proactivity = "passive",
    model = { provider = "auto" },  -- or cloud-ranked `ranked = { ... }`, "none", "ollama", etc
    agent = {
      enabled = true,
      adapter = "auto",  -- "pi", "codex", "tmux", "zellij", "terminal"
    },
  },
}
```

Packer.nvim:

```lua
use {
  "artie-mortus/Master-Hand",
  as = "master-hand",
  cmd = { "MH", "MasterHand" },
  config = function()
    require("master-hand").setup()
  end,
}
```

vim-plug:

```vim
Plug 'artie-mortus/Master-Hand', { 'on': ['MH', 'MasterHand'] }
```

Then `:MH` to open. Default mode is quiet: suggestions only when you run `:MH`, `:MHSuggest`, or `:MHPlan`. To refresh suggestions after edits/diagnostics instead:

```lua
require("master-hand").setup({
  proactivity = "advisory",
  suggestion_frequency_ms = 5000,
  model = { provider = "auto" },
})
```

---

<details open>
<summary><strong>Quick start</strong></summary>

```vim
:MH                         " open sidebar; starts async suggestions if empty
:MHSuggest                  " refresh suggestions
:MHPlan                     " ask for plan-style suggestions
:MHGoal Fix login redirect  " set long-term direction
:MHNext Update auth docs    " optionally pin short-term next step
:MHModel                    " show active model config
:MHModelStatus              " test model connection
:MHSend 1                   " send suggestion #1 to configured external agent
:MHSync                     " refresh buffers after external edits
```

Sidebar keys:

| Key | Action |
| --- | --- |
| `a` | Accept and send selected suggestion to external agent |
| `d` | Dismiss suggestion |
| `p` | Postpone suggestion |
| `v` | View details |
| `r` | Refresh suggestions |
| `q` | Close sidebar |

`a` sends the selected suggestion to the configured external coding agent and starts short-lived `:checktime` polling so Neovim notices saved edits. Set `agent.enabled = false` for feedback-only mode.

Flow: **open → ask/goal → read suggestions → approve only useful help**.

</details>

<details>
<summary><strong>Requirements</strong></summary>

- Neovim 0.10+
- `git` for status/diff context
- Optional tools:
  - `rg` for repo search
  - tree-sitter parsers for symbol context
  - `curl` for remote model providers
  - `ollama` for local `provider = "auto"` / `provider = "ollama"`
  - Login-backed CLIs (`pi`, `codex`, `claude`, or `gemini`) when using account login instead of API keys
  - `pi`, `codex`, `tmux`, or `zellij` for external agent handoff

</details>

<details>
<summary><strong>Configuration recipes</strong></summary>

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

### Cloud-ranked local/cloud routing

See [Models](#models) for the routing knobs and a full example.

### Account/subscription login (no API key)

Master Hand can use logged-in CLI tools instead of provider API keys:

```vim
:MHModel pi           " model calls use background pi --no-tools --no-session -p

:MHModel codex        " model calls use headless codex exec after login
:MHAuth codex login   " runs codex login in background; browser may open

:MHModel claude       " model calls use headless claude -p after login
:MHAuth claude login

:MHModel gemini       " model calls use headless gemini -p after login
:MHAuth gemini login
```

Login runs in the background and lets the provider CLI open a browser if needed. Later model suggestions call the CLI headless; no Pi/Codex/Claude/Gemini UI opens during suggestion generation. Pi model calls use `--no-tools --no-session` so they cannot edit files. Approved suggestions still use the configured agent handoff (`pi`, tmux, terminal, etc.).

For custom subscription CLIs, configure argv without shell strings:

```lua
require("master-hand").setup({
  model = {
    provider = "cli",
    command = { "my-ai-cli", "run", "{prompt}" },
    login_command = { "my-ai-cli", "login" },
  },
})
```

`command` and `login_command` must be argv tables. Shell command strings are rejected instead of split.

### OpenAI-compatible API

```lua
require("master-hand").setup({
  model = {
    provider = "openai_compatible",
    endpoint = "https://api.openai.com/v1/chat/completions",
    name = "gpt-4.1-mini",
    api_key_env = "OPENAI_API_KEY", -- or use :MHAuth provider env:VAR
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
    api_key_env = "OLLAMA_API_KEY", -- or use :MHAuth ollama-cloud env:VAR
  },
})
```

</details>

<details>
<summary><strong>Commands</strong></summary>

| Command | Alias | Description |
| --- | --- | --- |
| `:MasterHand` | `:MH` | Open sidebar; async-load suggestions if empty |
| `:MasterHandClose` | `:MHClose` | Close sidebar |
| `:MasterHandGoal <goal>` | `:MHGoal <goal>` | Set long-term direction |
| `:MasterHandNext [goal]` | `:MHNext [goal]`, `:MHShort [goal]` | Set short-term next step; omit args to return to inference |
| `:MasterHandPlan` | `:MHPlan` | Generate plan-style suggestions |
| `:MasterHandSuggest` | `:MHSuggest` | Refresh suggestions asynchronously |
| `:MasterHandModelSuggest` | `:MHModelSuggest` | Alias for `:MHSuggest` |
| `:MasterHandStatus` | `:MHStatus` | Print cached context summary |
| `:MasterHandModel [args]` | `:MHModel [args]` | Open interactive model picker (no args); `show` prints config; args change it directly. Tab completion is context-aware |
| `:MasterHandAuth [provider] [login\|env:VAR\|key]` | `:MHAuth [provider] [login\|env:VAR\|key]` | Show/set AI provider auth for current Neovim session |
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
<summary><strong>Suggestion workflow</strong></summary>

Suggestions run in two stages:

1. **Local heuristics** inspect steering goals, diagnostics, git diff, related files, recent edits, and repo index.
2. **Optional model review** reads bounded, read-only context and returns extra suggestions.

Proactivity modes:

- `passive` — default. Only explicit commands generate suggestions.
- `advisory`, `proactive`, `high_initiative` — currently share the same safe behavior: editor events debounce suggestion refreshes, but still never edit files or run commands automatically.

Goal steering:

- **Direction (long-term)** — broad user/project intent, usually set by `:MHGoal`. Example: "ship subscription login support."
- **Next step (short-term)** — immediate task, either inferred from open buffers/recent edits/changed files/diagnostics/model review or pinned with `:MHNext`. Example: "update provider docs and tests."
- `:MHGoal <goal>` changes long-term direction only.
- `:MHNext <goal>` pins the short-term next step. Run `:MHNext` with no args to return it to inference.
- Changing either goal clears stale suggestions; the next `:MH`/`:MHSuggest` (or the open sidebar) regenerates suggestions steered by the new goals.

</details>

<details>
<summary><strong>Models</strong></summary>

With `provider = "auto"`, Master Hand uses local Ollama when available, preferring coder/code/Qwen models. If no model is reachable, local heuristic suggestions still work. Use `provider = "none"` to disable model calls.

### Ranked routing

Ranked model routing uses a cloud model as the router. Master Hand sends a tiny candidate-selection prompt to `ranking_model` (or the highest-ranked cloud candidate), then runs the chosen local or cloud model. This lets a cheap cloud model decide when a higher-tier model is worth using.

| Option | Meaning |
| --- | --- |
| `selection = "auto"` | Enable cloud-ranked routing when `ranked` candidates exist. |
| `selection = "fixed"` | Use one configured model; skip routing and cloud ranking. |
| `cloud_policy = "fallback"` | Sort local candidates before cloud candidates before asking the router. Default; usage-friendly. |
| `cloud_policy = "best"` | Sort all candidates by `rank` before asking the router. Stronger-model friendly. |
| `ranking_model` | Cloud model used only for candidate choice; defaults to highest-ranked cloud candidate. |
| `ranking_max_tokens` | Token cap for the router response; default `24`. |
| `ranked` / `candidates` | Ordered candidate list. Each entry accepts normal model fields plus `rank`, `is_local`, or `cloud`. Setup values replace defaults rather than merging index-wise. |

```lua
require("master-hand").setup({
  model = {
    selection = "auto", -- cloud-rank candidates; use "fixed" for one model
    cloud_policy = "fallback", -- local candidates listed first for router
    ranking_model = { provider = "openrouter", name = "openai/gpt-4.1-mini", api_key_env = "OPENROUTER_API_KEY" },
    ranked = {
      { provider = "ollama", name = "qwen3-coder:latest", rank = 70, is_local = true },
      { provider = "ollama-cloud", name = "gpt-oss:120b", rank = 90 },
      { provider = "openrouter", name = "anthropic/claude-3.5-sonnet", rank = 95, api_key_env = "OPENROUTER_API_KEY" },
    },
  },
})
```

### Runtime model switching

Run bare `:MHModel` to open an interactive picker: choose a provider, then (for
Ollama) pick from installed models or (for API/CLI providers) type a model name.
Use `:MHModel show` to print the active config without opening the picker. Tab
completion is context-aware — it completes provider names and `key=` values
(`provider=`, `selection=`, `cloud_policy=`), and installed Ollama model names as
the second argument after `ollama`.

```vim
:MHModel                         " open interactive model picker
:MHModel show                    " print current model config (no picker)
:MHModel auto                    " local Ollama auto-pick
:MHModel none                    " disable model calls
:MHModel qwen3-coder:latest      " infer local Ollama
:MHModel ollama qwen3-coder:latest
:MHModel fixed ollama qwen3-coder:latest " lock one model, skip routing
:MHModel selection=auto          " re-enable ranked routing
:MHModel ollama-cloud gpt-oss:120b
:MHModel pi                      " use Pi as read-only/background model provider
:MHModel codex                   " use logged-in Codex subscription CLI
:MHModel claude                  " use logged-in Claude subscription CLI
:MHModel gemini                  " use logged-in Gemini CLI
:MHModel openai gpt-4.1-mini
:MHModel openrouter anthropic/claude-3.5-sonnet
:MHModel anthropic claude-sonnet-4-20250514
```

Advanced key/value form:

```vim
:MHModel provider=openai model=gpt-4.1-mini endpoint=https://api.openai.com/v1/chat/completions api_key_env=OPENAI_API_KEY
:MHModel provider=ollama-cloud model=gpt-oss:120b
```

### Auth helpers

```vim
:MHAuth                         " show auth status for active provider
:MHAuth codex login             " run account/subscription CLI login in background; browser may open
:MHAuth claude login
:MHAuth gemini login
:MHAuth openai env:OPENAI_API_KEY
:MHAuth openrouter env:OPENROUTER_API_KEY
:MHAuth anthropic               " prompt for key with inputsecret()
:MHAuth clear                   " unset Master Hand's process-env key for active provider
```

`:MHModel` and `:MHAuth` change runtime config for the current Neovim session. Put model defaults in `setup()` for persistent config. Prefer subscription CLI login when available; otherwise use `env:VAR` or shell env vars so API keys do not enter command history.

</details>

<details>
<summary><strong>Agent handoff</strong></summary>

Agent handoff is enabled by default. Accepting a suggestion sends it to an external agent. Disable if you want feedback-only mode.

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

Custom agent `command` must be an argv table. Shell command strings are rejected.

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
<summary><strong>Configuration reference</strong></summary>

Defaults live in `lua/master-hand/config.lua`. Common options:

```lua
require("master-hand").setup({
  proactivity = "passive", -- passive | advisory | proactive | high_initiative
  suggestion_frequency_ms = 5000,
  ignore = { ".git/", "node_modules/", "dist/", "build/", ".env", ".env.*" },
  model = {
    provider = "auto", -- none | auto | openai_compatible | openrouter | ollama | anthropic | pi | codex | claude | gemini | cli
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
    enabled = true, -- handoff only happens after approving a suggestion
    adapter = "auto",
    auto_checktime = true,
  },
  storage = { enabled = true },
  ui = {
    width = 46,
    max_width_ratio = 0.45,
    side = "right",
    highlights = {},
  },
})
```

List-valued setup options replace defaults rather than merging index-wise. This applies to `ignore`, `commands.allowlist`, `commands.blocklist`, and `model.ranked`/`model.candidates`; include every item you want active. Command templates (`model.command`, `model.login_command`, and `agent.command`) must be argv tables, not shell strings.

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
<summary><strong>Safety model</strong></summary>

- No automatic edits or command execution.
- Accepting a suggestion dispatches to an external agent unless `agent.enabled = false`.
- Diffs must pass `git apply --check` before approval and before apply.
- Commands use argv arrays, not shell strings.
- Model request bodies and auth headers travel over stdin, never argv — keys stay out of `ps` output and large contexts cannot hit the kernel's per-argument exec limit (E2BIG).
- Provider spawn failures surface as sidebar errors instead of breaking the async suggestion flow.
- Shell metacharacters and dangerous commands are blocked.
- Pending diffs live in memory, not on disk.
- Model/provider failures degrade to local heuristic suggestions.

</details>

<details>
<summary><strong>Testing</strong></summary>

From repo root:

```sh
nvim --headless -u NONE +'set rtp+=.' -l tests/run.lua
```

</details>
