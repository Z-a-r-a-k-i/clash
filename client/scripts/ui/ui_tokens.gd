class_name UiTokens
extends RefCounted

# Design tokens for every clash UI surface (plan m1/06 wave 2 — the
# "10/10 UX" bar): one spacing scale, one typographic ramp, one set of
# color roles. Panels and widgets derive everything from here; no
# one-off magic values in UI code.

# ---------- Spacing (4px base scale) ----------
const SPACE_1 := 4
const SPACE_2 := 8
const SPACE_3 := 12
const SPACE_4 := 16
const SPACE_6 := 24

# ---------- Type ramp (1.25 major-third ratio, 13px body) ----------
const FONT_CAPTION := 11
const FONT_BODY := 13
const FONT_EMPHASIS := 16
const FONT_TITLE := 20
const FONT_DISPLAY := 25

# ---------- Radii / strokes ----------
const RADIUS_SM := 2
const RADIUS_MD := 4
const BORDER_W := 1
const BORDER_W_HOT := 2

# ---------- Color roles (cyberpunk dark surface) ----------
const COLOR_BG := Color(0.010, 0.018, 0.034, 0.98)
const COLOR_SURFACE := Color(0.025, 0.038, 0.070, 0.96)
const COLOR_SURFACE_RAISED := Color(0.050, 0.080, 0.130, 1.0)
const COLOR_SURFACE_HOVER := Color(0.075, 0.130, 0.200, 1.0)
const COLOR_BORDER := Color(0.220, 0.330, 0.430, 0.92)
const COLOR_BORDER_HOT := Color(0.290, 0.820, 0.940, 0.70)
const COLOR_TEXT := Color(0.900, 0.940, 0.980, 1.0)
const COLOR_TEXT_MUTED := Color(0.580, 0.710, 0.840, 1.0)
const COLOR_TEXT_FAINT := Color(0.420, 0.520, 0.620, 1.0)
const COLOR_ACCENT := Color(0.250, 0.760, 0.900, 1.0)
const COLOR_ACCENT_MAGENTA := Color(1.000, 0.250, 0.580, 1.0)
const COLOR_AMBER := Color(0.880, 0.460, 0.080, 1.0)
const COLOR_AMBER_BORDER := Color(0.970, 0.720, 0.250, 1.0)
const COLOR_SUCCESS := Color(0.250, 0.850, 0.500, 1.0)
const COLOR_DANGER := Color(1.000, 0.250, 0.300, 1.0)
const COLOR_HP_HIGH := Color(0.25, 1.0, 0.65, 1.0)
const COLOR_HP_LOW := Color(1.0, 0.20, 0.30, 1.0)
const COLOR_PROGRESS_BACK := Color(0.0, 0.0, 0.0, 0.68)

# ---------- Shared stylebox builders ----------


static func panel_style(raised: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_SURFACE if not raised else COLOR_BG
	style.border_color = COLOR_BORDER if not raised else COLOR_BORDER_HOT
	style.set_border_width_all(BORDER_W)
	style.set_corner_radius_all(RADIUS_MD)
	style.set_content_margin_all(SPACE_2)
	return style


static func button_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(BORDER_W)
	style.set_corner_radius_all(RADIUS_SM)
	style.content_margin_left = SPACE_3
	style.content_margin_right = SPACE_3
	style.content_margin_top = SPACE_1
	style.content_margin_bottom = SPACE_1
	return style


static func bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(RADIUS_SM)
	return style
