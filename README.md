# Dropdown Terminal

An Omarchy Quickshell plugin that toggles the configured default terminal as a
floating overlay on the current Hyprland workspace.

![Dropdown Terminal preview](preview.png)

## Install

From the plugin repository:

```bash
omarchy plugin add https://github.com/tuthan/omarchy-dropdown-terminal.git --enable
```

For local development:

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/io.github.tuthan.dropdown-terminal
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.tuthan.dropdown-terminal --section right
```

The helper requires `jq`, `hyprctl`, and the Omarchy `omarchy` command.

## Hotkey

The plugin registers `io.github.tuthan.dropdown-terminal:toggle` with Hyprland. The easiest
persistent binding is one line in `~/.config/hypr/bindings.lua`:

```lua
hl.bind("CTRL + GRAVE", hl.dsp.global("io.github.tuthan.dropdown-terminal:toggle"))
```

This is deliberately the only Hyprland configuration required. The plugin
does not replace or hard-code the user's terminal emulator.

For a temporary test without editing a file, run:

```bash
hyprctl eval 'hl.bind("CTRL + GRAVE", hl.dsp.global("io.github.tuthan.dropdown-terminal:toggle"))'
```

The runtime version is lost when Hyprland reloads; use the `bindings.lua` line
for a persistent shortcut. To use a physical keycode instead of the keyboard
symbol, for example:

```lua
hl.bind("CTRL + code:41", hl.dsp.global("io.github.tuthan.dropdown-terminal:toggle"))
```

The bar icon also provides a shortcut installer: right-click it to add the
default `Ctrl + Grave` binding. If the binding is not already present, the
plugin backs up `bindings.lua`, appends the line, and reloads Hyprland.

## Behavior

- First activation runs `omarchy launch terminal`, preserving the configured
  default terminal and current working directory behavior.
- The new window stays on the current workspace, floats at 90% × 45%, and is
  centered near the top edge so the current desktop remains visible behind it.
- Later activations move the same terminal to/from a hidden workspace named
  `dropdown-terminal-hidden`, without changing the user's current workspace.
- Existing dropdown windows are detected after a shell restart, so they are
  reused instead of duplicated.
- Runtime state is stored in `XDG_RUNTIME_DIR` when it is private; if that is
  unavailable, the plugin creates a private per-user directory under `/tmp`.

## Remove

```bash
omarchy plugin remove io.github.tuthan.dropdown-terminal
```

## License

MIT
