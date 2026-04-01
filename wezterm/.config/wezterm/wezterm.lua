local wezterm = require("wezterm")
local config = wezterm.config_builder()

config = {
	font = wezterm.font_with_fallback({
		"JetBrainsMonoNL Nerd Font",
		{ family = "Symbols Nerd Font Mono", scale = 1.2 },
	}),
	font_size = 16,
	color_scheme = "Tokyo Night Moon",
	enable_tab_bar = false,
	window_decorations = "RESIZE",
	window_background_opacity = 0.97,
	macos_window_background_blur = 10,
}

return config
