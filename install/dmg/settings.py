import json
import os

dmg_dir = defines["dmg_dir"]
with open(os.path.join(dmg_dir, "layout.json")) as f:
    layout = json.load(f)

app_path = defines["app"]
app_name = os.path.basename(app_path)
window = layout["window"]

volume_name = "Mac Janitor"
format = "UDZO"
compression_level = 9
filesystem = "HFS+"
files = [app_path]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]
background = os.path.join(dmg_dir, "background.png")

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
window_rect = ((200, 120), (window["width"], window["height"]))
default_view = "icon-view"
show_icon_preview = False
arrange_by = None
icon_size = layout["iconSize"]
text_size = layout["textSize"]
label_pos = "bottom"
icon_locations = {
    app_name: (layout["app"]["x"], layout["app"]["y"]),
    "Applications": (layout["applications"]["x"], layout["applications"]["y"]),
}
