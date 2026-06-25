# lex-ghostty-shaders

A collection of custom [Ghostty](https://ghostty.org/) terminal shaders, authored and tuned by hand.

Ghostty supports custom GLSL fragment shaders that run on the terminal's rendered output every frame. This repo collects the shaders I've built for it. Each shader is a single, self-contained `.glsl` file written in Ghostty's ShaderToy-compatible format, with tunable constants documented at the top.

## Shaders

| Shader           | File                                       | Description                                                                                                                                                                                                                                                                                        |
| ---------------- | ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Water Ripple** | [`water_ripple.glsl`](./water_ripple.glsl) | Renders the terminal behind a calm water surface. A subtle ambient undulation is always present, and each keystroke drops a "pebble" at the cursor — a damped radial wave train that expands outward and fades to calm. Faster typing keeps fresh ripples near the cursor; idle water stays still. |

> **About the Water Ripple "stateless" design.** Ghostty custom shaders are stateless (ShaderToy format) — the GPU carries no per-frame state, and only `iChannel0` (the terminal image) plus built-in uniforms are available. This shader builds its dynamic effect purely from `iTime` and `iTimeCursorChange` (the timestamp of the most recent cursor change, which fires per keystroke and is not retriggered by cursor blink). Because only the single latest keystroke is timestamped, at most one pebble wave train is active at a time; the ambient field plus the wave train's many rings provide the "interacting ripples" feel within that constraint. See the shader's header comment for the full explanation and the list of tunable knobs.

## Requirements

- [Ghostty](https://ghostty.org/) (custom shader support ships with recent versions)

## Installation

1. Clone this repository:

   ```sh
   git clone https://github.com/lexrus/lex-ghostty-shaders.git
   ```

2. Copy the shader(s) you want into Ghostty's config directory:

   ```sh
   mkdir -p ~/.config/ghostty/shaders/
   cp lex-ghostty-shaders/water_ripple.glsl ~/.config/ghostty/shaders/
   ```

## Enabling a shader in Ghostty

Add a `custom-shader` line to your Ghostty config file at `~/.config/ghostty/config`:

```ini
custom-shader = ./shaders/water_ripple.glsl
```

Paths are relative to the config file's location, or you can use an absolute path:

```ini
custom-shader = ~/.config/ghostty/shaders/water_ripple.glsl
```

Restart Ghostty (or reload its config) for the change to take effect. You can comment out the line with `#` to disable the shader.

### Tip: keep this repo as your shaders folder

If you'd like this repo to *be* your Ghostty shaders directory, you can symlink it:

```sh
# Back up any existing shaders folder first, then:
ln -s "$PWD/lex-ghostty-shaders" ~/.config/ghostty/shaders
```

Then reference shaders directly:

```ini
custom-shader = ./shaders/water_ripple.glsl
```

## Tuning

Each shader exposes its parameters as clearly commented `const` values near the top of the file. For **Water Ripple**, the most useful knobs are:

| Knob                         | What it controls                                                                     |
| ---------------------------- | ------------------------------------------------------------------------------------ |
| `REFRACTION`                 | How strongly the water distorts the terminal text. Lower = more legible.             |
| `AMBIENT_STRENGTH`           | Strength of the always-on shallow-water undulation. `0` = perfectly still when idle. |
| `PEBBLE_AMP`                 | Height of the cursor-drop ripples.                                                   |
| `WAVENUMBER` / `OMEGA`       | Ring spacing and propagation speed.                                                  |
| `FRONT_SPEED`                | How fast ripples expand across the screen.                                           |
| `RIPPLE_LIFE` / `DECAY_RATE` | How long ripples persist before calming.                                             |

Edit the values in the `.glsl` file and reload Ghostty — no recompilation step is needed.

## If you like this project

You might also like my other apps.

### [SubList](https://apps.apple.com/app/sublist-subscription-list/id6757860829) (iOS, macOS)

Track subscriptions, renewals, and spending in one place with reminders, analytics, and iCloud sync.

### 🗂️ [SwiftyMenu](https://apps.apple.com/app/id1567748223) (macOS)

A Finder extension which presents a customizable menu to rapidly open selected folders or files with your favorite applications.

### 📱 [Sharptooth](https://apps.apple.com/app/id6748440814) (macOS)

Effortlessly manage your Bluetooth devices right from the menu bar with custom hotkeys and smart automation.

### 🔤 [RegEx+](https://apps.apple.com/app/id1511763524) (iOS, macOS)

An app to test your regular expressions with live matching.

### 📸 [LiveExtractor](https://apps.apple.com/app/id6746672642) (iOS, macOS, tvOS, visionOS)

Extract individual photos and videos from your Live Photos across all your Apple devices.

## License

Provided as-is for personal use. Individual shaders note their upstream sources and licenses in their header comments where applicable.
