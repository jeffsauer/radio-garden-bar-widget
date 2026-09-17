<img width="1535" height="849" alt="radio-garden-bar-widget" src="https://github.com/user-attachments/assets/9230d8e9-bb03-4e66-a221-e9d7f2e0f75a" />

# radio-garden-bar-widget
Omarchy bar widget to toggle (i.e. show/hide) Radio Garden web application visibility using a hyprland scratchpad workspace.

To install, use the following command:

```
omarchy plugin add https://github.com/jeffsauer/radio-garden-bar-widget --enable
```

To enable a keybinding shortcut to toggle the visibility of Radio Garden (e.g. SUPER+ALT+R), simply add the following to .config/hypr/bindings.lua:

```
o.bind("SUPER + ALT + R", "Radio Garden", "omarchy-shell -q com.darkhorse-studios.radio-garden-bar-widget toggle")
```

Make sure you are not over-riding an existing key binding.
