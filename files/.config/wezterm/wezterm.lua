local wezterm = require("wezterm")

local config = wezterm.config_builder()

local is_windows = os.getenv("OS") and os.getenv("OS"):lower():find("windows")
local is_macos = wezterm.target_triple:lower():find("darwin") ~= nil

-- Rose Pine Moon palette (for the header / tab bar)
local rpm = {
  base    = "#232136",
  surface = "#2a273f",
  overlay = "#393552",
  muted   = "#6e6a86",
  subtle  = "#908caa",
  text    = "#e0def4",
  love    = "#eb6f92",
  gold    = "#f6c177",
  rose    = "#ea9a97",
  pine    = "#3e8fb0",
  foam    = "#9ccfd8",
  iris    = "#c4a7e7",
  hl_low  = "#2a283e",
  hl_med  = "#44415a",
  hl_high = "#56526e",
}

config.color_scheme = "rose-pine-moon"
config.max_fps = 120
config.font = wezterm.font("Hack Nerd Font", { weight = "DemiBold" })
config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"

config.inactive_pane_hsb = {
  saturation = 0.0,
  brightness = 0.5,
}

-- Fancy tab bar so the header picks up window_frame styling
config.use_fancy_tab_bar = true
config.window_frame = {
  font = wezterm.font("Hack Nerd Font", { weight = "Bold" }),
  active_titlebar_bg = rpm.base,
  inactive_titlebar_bg = rpm.surface,
  active_titlebar_fg = rpm.text,
  inactive_titlebar_fg = rpm.subtle,
  active_titlebar_border_bottom = rpm.iris,
  button_fg = rpm.subtle,
  button_bg = rpm.base,
  button_hover_fg = rpm.text,
  button_hover_bg = rpm.overlay,
}

-- Tab colors (overrides only the tab bar, scheme handles the rest)
config.colors = {
  tab_bar = {
    background = rpm.base,
    active_tab = {
      bg_color = rpm.iris,
      fg_color = rpm.base,
      intensity = "Bold",
    },
    inactive_tab = {
      bg_color = rpm.surface,
      fg_color = rpm.muted,
    },
    inactive_tab_hover = {
      bg_color = rpm.hl_med,
      fg_color = rpm.text,
      italic = true,
    },
    new_tab = {
      bg_color = rpm.base,
      fg_color = rpm.muted,
    },
    new_tab_hover = {
      bg_color = rpm.overlay,
      fg_color = rpm.text,
    },
  },
}

-- Liquid glass
if is_windows then
  config.win32_system_backdrop = "Acrylic"
  config.window_background_opacity = 0.6
  config.window_frame.font_size = 10.0
end

if is_macos then
  config.window_background_opacity = 0.72
  config.macos_window_background_blur = 80
  config.font_size = 15.0
  config.window_frame.font_size = 13.0
end

return config