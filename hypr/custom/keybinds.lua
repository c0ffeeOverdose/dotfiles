-- See https://wiki.hyprland.org/Configuring/Binds/

----------------
---- User -------
----------------

hl.bind("CTRL + SUPER + slash",
    hl.dsp.exec_cmd("xdg-open ~/.config/illogical-impulse/config.json"),
    { description = "Edit shell config" }
)

hl.bind("CTRL + SUPER + ALT + slash",
    hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.conf"),
    { description = "Edit extra keybinds" }
)

hl.bind("mouse:275",
    hl.dsp.focus({ workspace = "r-1" }),
    { description = "Move to left" }
)

hl.bind("mouse:276",
    hl.dsp.focus({ workspace = "r+1" }),
    { description = "Move to right" }
)

hl.bind("SHIFT + mouse:275",
    hl.dsp.window.move({ workspace = "r-1" }),
    { description = "Send to left" }
)

hl.bind("SHIFT + mouse:276",
    hl.dsp.window.move({ workspace = "r+1" }),
    { description = "Send to right" }
)


----------------
---- Apps -------
----------------

-- Terminal
-- hl.bind("SUPER + Return",
--   hl.dsp.exec_cmd([[~/.config/hypr/hyprland/scripts/launch_first_available.sh "${TERMINAL}" "kitty -1" "foot" "alacritty" "wezterm" "konsole" "kgx" "uxterm" "xterm"]]),
--   { description = "Terminal" }
-- )

-- [hidden] terminal alt
-- hl.bind("SUPER + T",
--   hl.dsp.exec_cmd([[~/.config/hypr/hyprland/scripts/launch_first_available.sh "${TERMINAL}" "kitty -1" "foot" "alacritty" "wezterm" "konsole" "kgx" "uxterm" "xterm"]])
-- )

-- [hidden] terminal for Ubuntu people
-- hl.bind("CTRL + ALT + T",
--   hl.dsp.exec_cmd([[~/.config/hypr/hyprland/scripts/launch_first_available.sh "${TERMINAL}" "kitty -1" "foot" "alacritty" "wezterm" "konsole" "kgx" "uxterm" "xterm"]])
-- )

-- File manager
-- hl.bind("SUPER + E",
--   hl.dsp.exec_cmd([[~/.config/hypr/hyprland/scripts/launch_first_available.sh "dolphin" "nautilus" "nemo" "thunar" "${TERMINAL}" "kitty -1 fish -c yazi"]]),
--   { description = "File manager" }
-- )

-- Browser
-- hl.bind("SUPER + W",
--     hl.dsp.exec_cmd(
--         [[~/.config/hypr/hyprland/scripts/launch_first_available.sh "brave" "google-chrome-stable" "zen-browser" "firefox" "chromium" "microsoft-edge-stable" "opera" "librewolf"]]),
--     { description = "Browser" }
-- )

-- Code editor
-- hl.bind("SUPER + C",
--   hl.dsp.exec_cmd([[~/.config/hypr/hyprland/scripts/launch_first_available.sh "code" "codium" "cursor" "zed" "zedit" "zeditor" "kate" "gnome-text-editor" "emacs" "command -v nvim && kitty -1 nvim" "command -v micro && kitty -1 micro"]]),
--   { description = "Code editor" }
-- )

-- Office software
-- hl.bind("CTRL + SUPER + SHIFT + ALT + W",
--   hl.dsp.exec_cmd([[~/.config/hypr/hyprland/scripts/launch_first_available.sh "wps" "onlyoffice-desktopeditors" "libreoffice"]]),
--   { description = "Office software" }
-- )

-- Text editor
-- hl.bind("SUPER + X",
--   hl.dsp.exec_cmd([[~/.config/hypr/hyprland/scripts/launch_first_available.sh "kate" "gnome-text-editor" "emacs"]]),
--   { description = "Text editor" }
-- )

-- Volume mixer
-- hl.bind("CTRL + SUPER + V",
--   hl.dsp.exec_cmd([[~/.config/hypr/hyprland/scripts/launch_first_available.sh "pavucontrol-qt" "pavucontrol"]]),
--   { description = "Volume mixer" }
-- )

-- Settings app
-- hl.bind("SUPER + I",
--   hl.dsp.exec_cmd([[XDG_CURRENT_DESKTOP=gnome ~/.config/hypr/hyprland/scripts/launch_first_available.sh "qs -p ~/.config/quickshell/$qsConfig/settings.qml" "systemsettings" "gnome-control-center" "better-control"]]),
--   { description = "Settings app" }
-- )

-- Task manager
-- hl.bind("CTRL + SHIFT + Escape",
--   hl.dsp.exec_cmd([[~/.config/hypr/hyprland/scripts/launch_first_available.sh "gnome-system-monitor" "plasma-systemmonitor --page-name Processes" "command -v btop && kitty -1 fish -c btop"]]),
--   { description = "Task manager" }
-- )

-- Open Obsidian
hl.bind("SUPER + R",
    hl.dsp.exec_cmd("obsidian"),
    { description = "Obsidian" }
)

