-- Ensure shadows are rendered so hyprglass decoration pipeline activates
hl.window_rule({ match = { class = ".*" }, no_shadow = false })

-- Apply Apple Liquid Glass ('pomme') preset to terminals
hl.window_rule({ match = { class = "^(kitty)$" }, tag = "+hyprglass_preset_pomme" })
hl.window_rule({ match = { class = "^(foot)$" }, tag = "+hyprglass_preset_pomme" })

-- System utilities & dialogs with frosted glass transparency
hl.window_rule({ match = { class = "^(pavucontrol|org.pulseaudio.pavucontrol)$" }, opacity = 0.88, tag = "+hyprglass_preset_pomme" })
hl.window_rule({ match = { class = "^(nm-connection-editor)$" }, opacity = 0.88, tag = "+hyprglass_preset_pomme" })
hl.window_rule({ match = { class = "^(nwg-look)$" }, opacity = 0.90, tag = "+hyprglass_preset_pomme" })
