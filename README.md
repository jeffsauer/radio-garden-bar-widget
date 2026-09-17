# radio-garden-bar-widget
Omarchy bar widget to toggle (i.e. show/hide) Radio Garden web application visibility using a hyprland scratchpad workspace.

To install, use the following command:

```
omarchy plugin add https://github.com/jeffsauer/radio-garden-bar-widget --enable
```

And then add the following rule to ~/.config/hypr/looknfeel.lua followed by a ```hyprctl reload``` command to let hyprland know about the new rule.

```
o.window({ class = "^brave-radio\\.garden__", title = "^Radio Garden" }, { workspace = "special:radiogarden silent", float = true })
```

To enable a keybinding shortcut to toggle the visibility of Radio Garden (e.g. SUPER+ALT+R), simply add the following to .config/hypr/bindings.lua:

```
o.bind("SUPER + ALT + R", "Radio Garden", "omarchy-shell -q com.darkhorse-studios.radio-garden-bar-widget toggle")
```

Make sure you are not over-riding an existing key binding.
