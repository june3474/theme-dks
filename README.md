# theme-dks

theme-dks is a GTK 2/GTK 3/GTK 4/Xfce theme that blends the GTK 2 theme
(`gtkrc`) from Adwaita with the GTK 3 theme (`gtk.css`) from PRO-dark-XFCE by
PAULXFCE. Some modifications were made while blending them, and GTK 4 support
was added later to match the GTK 3 theme.

The repository provides two manually selectable theme names:

- `theme-dks`: the existing light GTK 2/GTK 3/GTK 4 and Xfwm4 theme
- `theme-dks-dark`: the dark GTK 3/GTK 4 and Xfwm4 theme

The dark variant uses a restrained blue-gray palette and a subtle one-pixel
window border. It intentionally has no GTK 2 dark variant.

## Screenshots

### GTK3

<image src="screenshots/gtk3-light.png" width="1000px" height="543px" title="gtk3-light"></img>

<image src="screenshots/gtk3-dark.png" width="1000px" height="543px" title="gtk3-dark"></img>

### GTK4

<image src="screenshots/gtk4-light.png" width="1000px" height="488px" title="gtk4-light"></img>

<image src="screenshots/gtk4-dark.png" width="1000px" height="488px" title="gtk4-dark"></img>

## Installation

If this checkout is already located at `~/.themes/theme-dks`, expose the dark
theme with one additional relative-directory link:

```sh
ln -s "$HOME/.themes/theme-dks/theme-dks-dark" "$HOME/.themes/theme-dks-dark"
```

For a checkout elsewhere, link both runtime theme roots into `~/.themes`
(replace `/path/to/theme-dks` with the checkout's absolute path):

```sh
mkdir -p "$HOME/.themes"
ln -s /path/to/theme-dks "$HOME/.themes/theme-dks"
ln -s /path/to/theme-dks/theme-dks-dark "$HOME/.themes/theme-dks-dark"
```

For a link-free installation, create the destinations and dereference the
repository's internal links while copying:

```sh
mkdir -p "$HOME/.themes/theme-dks" "$HOME/.themes/theme-dks-dark"
cp -aL /path/to/theme-dks/index.theme \
  /path/to/theme-dks/gtk-2.0 \
  /path/to/theme-dks/gtk-3.0 \
  /path/to/theme-dks/gtk-4.0 \
  /path/to/theme-dks/xfwm4 \
  "$HOME/.themes/theme-dks/"
cp -aL /path/to/theme-dks/theme-dks-dark/index.theme \
  /path/to/theme-dks/theme-dks-dark/gtk-3.0 \
  /path/to/theme-dks/theme-dks-dark/gtk-4.0 \
  /path/to/theme-dks/theme-dks-dark/xfwm4 \
  "$HOME/.themes/theme-dks-dark/"
```

Use empty destination directories for the copy method so older files cannot
remain from a previous version.

## Selecting light or dark

Open **Xfce Settings → Appearance → Style** and select either `theme-dks` or
`theme-dks-dark`.

When Appearance's **Set matching Xfwm4 theme if there is one** option is
enabled, Xfce also selects the matching window decoration. If that option is
disabled, open **Xfce Settings → Window Manager → Style** and select the same
theme name there.

Theme DKS installs no switcher, autostart item, background monitor, portal
listener, or other executable. It never changes the selected theme on its own.

## Removal

Remove only the two links or copied directories that you installed:
`~/.themes/theme-dks` and `~/.themes/theme-dks-dark`. Check whether each path is
a link or a directory first, especially if the checkout itself lives at
`~/.themes/theme-dks`; deleting that directory would also delete the checkout.

## License

theme-dks is licensed under GPLv2, of which the downloaded file contains a copy.

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program; if not, write to the Free Software Foundation, Inc.,
    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
