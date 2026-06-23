# Master Hand

Neovim-first AI coding assistant between tab completion and autonomous agents.

Master Hand observes repository activity, tracks an optional development goal, and surfaces advisory next steps. It never edits files or runs commands without explicit approval.

## MVP status

This repo contains a Neovim Lua plugin scaffold with local repository awareness:

- tracks open buffers and recent edits
- reads git status/diff
- accepts a natural-language goal
- builds a compact context snapshot
- produces advisory heuristic suggestions
- shows suggestions in a sidebar
- supports accept/dismiss/postpone feedback
- defines approval boundaries for edits/commands

LLM/provider-backed planning and proposed diff generation are extension points in `lua/master-hand/providers.lua` and `lua/master-hand/diff.lua`.

## Install with lazy.nvim

```lua
{
  dir = "/home/artemis/projects/Master Hand",
  name = "master-hand",
  config = function()
    require("master-hand").setup({
      proactivity = "advisory",
      model = {
        provider = "none", -- "openai_compatible" later
      },
    })
  end,
}
```

## Commands

- `:MasterHand` / `:MH` open sidebar
- `:MasterHandClose` / `:MHClose` close sidebar
- `:MasterHandGoal <goal>` / `:MHGoal <goal>` set active goal
- `:MasterHandPlan` / `:MHPlan` generate plan-oriented suggestions
- `:MasterHandSuggest` / `:MHSuggest` refresh suggestions
- `:MasterHandStatus` / `:MHStatus` print current context summary

## Design defaults

- Neovim Lua plugin first
- editor-independent core kept as pure Lua modules where practical
- no automatic edits
- no destructive commands
- repository reads allowed except ignored paths
- commands and edits require explicit user approval
- low-interruption advisory mode by default
