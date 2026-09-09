"""Compact drag-to-Applications layout; no custom artwork."""
import os

application = defines['app']
files = [application]
symlinks = {'Applications': '/Applications'}
format = 'UDZO'
compression_level = 9
filesystem = 'HFS+'
background = None
window_rect = ((200, 200), (540, 320))
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
show_icon_preview = False
arrange_by = None
grid_spacing = 80
icon_size = 96
text_size = 13
label_pos = 'bottom'
icon_locations = {
    os.path.basename(application): (150, 140),
    'Applications': (390, 140),
}
