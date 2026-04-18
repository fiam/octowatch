import os


app = os.path.abspath(defines["app"])
app_name = os.path.basename(app)
app_icon = defines.get(
    "badge_icon",
    os.path.join(app, "Contents", "Resources", "AppIcon.icns"),
)
background = defines.get("background", "builtin-arrow")

format = "UDZO"
compression_level = 9

files = [app]
symlinks = {"Applications": "/Applications"}
badge_icon = app_icon if os.path.exists(app_icon) else None
background = background

default_view = "icon-view"
show_toolbar = False
show_status_bar = False
show_tab_view = False
show_pathbar = False
show_sidebar = False

window_rect = ((120, 120), (680, 430))
icon_size = 128
text_size = 14

arrange_by = None
grid_spacing = 100
include_icon_view_settings = "auto"
include_list_view_settings = "auto"

icon_locations = {
    app_name: (180, 215),
    "Applications": (500, 215),
}
