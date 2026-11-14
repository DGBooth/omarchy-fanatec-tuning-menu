# Omarchy Fanatec Tuning Menu

A bar widget for [Omarchy](https://omarchy.org) that shows the state of a
Fanatec wheelbase and lets you change its tuning menu from the desktop, so you
don't have to dig through the wheel's own display.

It talks to the wheel through the
[`hid-fanatecff`](https://github.com/gotzl/hid-fanatecff) kernel driver
(`fanatec-ff`), which exposes the base and its tuning menu as sysfs files.
The widget only reads and writes those files. It needs no extra daemon.

> Unofficial. Not affiliated with or endorsed by Fanatec / Endor AG. Changing
> tuning values sends commands to your hardware, so use it at your own risk.

![Fanatec Tuning Menu panel](preview.png)

The bar shows the active preset next to the icon, and **Edit S1 settings** opens
the tuning-menu list:

| Bar icon | Settings list |
|----------|---------------|
| ![Bar icon with the active preset](screenshots/bar.png) | ![Tuning-menu settings list](screenshots/panel-settings.png) |

## What it does

- **Bar icon** with the active preset next to it (`A`, `S1` … `S4`). The
  tooltip shows the base, the attached wheel rim and the preset.
- **Panel** with the wheelbase model, rim, rotation range and firmware.
- **Preset buttons** (Auto, S1–S4) to switch the active tuning preset, with an
  optional **nickname** per preset (S1–S4) shown in the panel and tooltips.
  The bar label always stays `A` / `S1` … `S4`.
- **Edit settings** list with a slider or switch for each tuning-menu
  parameter your base exposes, with help text on each (click the label).
  Right-click a slider to reset it to Fanatec's default.
- Wheel-mouse scrolling over the list scrolls the list; it never changes a
  slider by accident.

The parameters follow Fanatec's own
[tuning menu documentation](https://help.fanatec.com/hc/en-us/articles/43901256649233):
SEN, FF, FUL, NDP, NFR, NIN, INT, FEI, FOR / SPR / DPR, BLI, SHO, ACP, brF, plus
force-feedback scaling and the standard / advanced mode switch. Which of them
appear depends on your base, because the driver only creates the files the
base supports.

## Requirements

- Omarchy with the shell (`omarchy-shell`) that supports bar-widget plugins.
- The `hid-fanatecff` driver, loaded, and a connected Fanatec wheelbase.
- Your user in the `games` group, so the widget can **write** (reading works
  without it).

## Setup

Setup has five steps. Steps 2 and 3 involve `sudo` and are for you to run;
the plugin itself never runs privileged commands.

### 1. Install the `hid-fanatecff` driver

The driver is in the AUR as `hid-fanatecff-dkms`. Install it with Omarchy's
package tools:

```bash
omarchy pkg aur add hid-fanatecff-dkms
```

This installs it only if it's missing, and reports an error if it didn't land.
Prefer to browse? `omarchy pkg aur install` opens a fuzzy-finder; search for
`hid-fanatecff-dkms` and pick it.

The package builds the `hid_fanatec` kernel module with DKMS and installs a
udev rule (`/usr/lib/udev/rules.d/99-fanatec.rules`). Upstream project and
supported-device list: <https://github.com/gotzl/hid-fanatecff>.

### 2. Narrow the driver's USB rule

The packaged udev rule makes the wheel's USB and `hidraw` device nodes
**writable by every local account** (`MODE="0666"`), so another user on the
machine could reset the wheel or detach its driver. See
[Security notes](#security-notes). This step overrides that one line so only
members of `games` (the group you join in step 3, and the one this plugin needs
anyway) can open those nodes. It copies the installed rule and changes only the
`0666` line:

```bash
sed 's|^SUBSYSTEMS=="usb", ATTRS{idVendor}=="0eb7", MODE="0666"|SUBSYSTEMS=="usb", ATTRS{idVendor}=="0eb7", GROUP="games", MODE="0660"|' \
  /usr/lib/udev/rules.d/99-fanatec.rules | sudo tee /etc/udev/rules.d/99-fanatec.rules >/dev/null
sudo udevadm control --reload
```

A file with the same name in `/etc/udev/rules.d/` takes precedence over the
packaged one. Confirm that exactly one line differs:

```bash
diff /usr/lib/udev/rules.d/99-fanatec.rules /etc/udev/rules.d/99-fanatec.rules
```

You should see line 5 change from `MODE="0666"` to `GROUP="games", MODE="0660"`.
If `diff` prints nothing, the packaged rule has changed upstream and the `sed`
didn't match: stop, and check the packaged file before going on.

The override is a copy, so after a driver package upgrade, re-run this step to
pick up any new upstream rules. To undo it, delete the file and reload:

```bash
sudo rm /etc/udev/rules.d/99-fanatec.rules && sudo udevadm control --reload
```

Tested on one machine with AMS2 (Steam/Proton): steering, force feedback and
this plugin's tuning controls all worked with the narrowed rule. If a game or
tool that talks to the wheel directly stops working, check that the user
running it is in `games`.

### 3. Add yourself to the `games` group

The driver's udev rule makes the tuning files writable by the **`games`**
group, not by regular users. Without it the widget is read-only and shows a
note saying so.

```bash
sudo usermod -aG games "$USER"
```

### 4. Reboot and check

**Reboot.** This loads the driver, applies the rule to the connected wheel, and
gives your session the new group. A plain log-out is often not enough: the
long-running `systemd --user` manager that your desktop session inherits its
groups from can survive a log-out and keeps the old group list. (If you only
re-ran step 2 on an already-working setup, replugging the wheelbase is enough.)

Then check each part:

```bash
omarchy pkg present hid-fanatecff-dkms && echo "package installed"
lsmod | grep hid_fanatec                        # the module is loaded
ls /sys/class/ftec_tuning/                      # one entry per tuning-capable base
id | grep -o games                              # prints "games"
[ -w /sys/class/ftec_tuning/*/SLOT ] && echo writable
```

And confirm the wheel's device nodes are no longer world-writable:

```bash
for n in /dev/hidraw*; do udevadm info -a -n "$n" | grep -q 'idVendor}=="0eb7"' && stat -c '%a %U:%G %n' "$n"; done
lsusb | awk '/0eb7/{gsub(":","",$4); print "/dev/bus/usb/"$2"/"$4}' | xargs stat -c '%a %U:%G %n'
```

Both should print `660 root:games`. `666 root:root` means the override isn't in
effect: re-run step 2 and replug the wheelbase. (The wheel's `/dev/input/event*`
node isn't covered by this rule and stays as it was.)

If `id` doesn't list `games`, the session hasn't picked the group up yet.
DKMS rebuilds the module for new kernels as part of `omarchy update`. If the
module is missing after a kernel update, reinstall the package to force a
rebuild, then reboot:

```bash
omarchy pkg drop hid-fanatecff-dkms && omarchy pkg aur add hid-fanatecff-dkms
```

### 5. Install the plugin

```bash
omarchy plugin add https://github.com/DGBooth/omarchy-fanatec-tuning-menu.git
omarchy plugin enable io.github.dgbooth.fanatec-tuning-menu
```

Plugins land disabled so you can read the code first. This one runs
unsandboxed inside `omarchy-shell`, like every Omarchy plugin. The icon
appears at the right end of the bar; move it with
`omarchy bar move io.github.dgbooth.fanatec-tuning-menu --before omarchy.clock`
or any other placement.

### Update

```bash
omarchy plugin update                                          # every git-installed plugin
omarchy plugin update io.github.dgbooth.fanatec-tuning-menu    # just this one
```

### Uninstall

```bash
omarchy plugin remove io.github.dgbooth.fanatec-tuning-menu
```

It asks you to confirm (add `--yes` to skip the prompt), turns the plugin off
and deletes its folder. Your wheelbase settings are untouched, since they live
on the wheel.

Removing does not edit `~/.config/omarchy/shell.json`, so the widget's entry in
the bar layout stays behind, along with any nicknames and options. For a clean
removal, open `shell.json` and delete the object with
`"id": "io.github.dgbooth.fanatec-tuning-menu"` from its bar section. Leave it
in place if you plan to reinstall, and your nicknames will come back.

The `hid-fanatecff` driver, your `games` group membership and the udev override
from setup step 2 are separate from the plugin and aren't changed by any of this.
Delete `/etc/udev/rules.d/99-fanatec.rules` yourself if you also remove the
driver.

`omarchy plugin disable` followed by `omarchy plugin enable` gives the widget a
fresh bar entry, so nicknames and options set earlier are reset. Disable and
re-enable leave the plugin's files alone, and your wheelbase settings are
untouched.

## Using it

- Click the icon to open the panel. Right-click the icon to refresh now.
- Pick a preset with the buttons. The wheel's display and every value in the
  list update to that preset a moment later.
- Click **Edit S2 settings** (it names the active preset) to open the list.
  Drag a slider and release to write it. Click a label to read what the
  setting does and its default.
- Type in the nickname box to name the active preset (S1–S4). Nicknames are
  stored in the plugin's entry in `~/.config/omarchy/shell.json` as `nickS1` …
  `nickS4`; they are not stored on the wheel.

### What it changes

Nothing is written until you act on a control:

- **On the wheelbase:** moving a slider or switch, choosing a preset, resetting
  a slider (right-click) or toggling advanced mode sends that one value to the
  wheelbase, which stores it as part of its tuning menu. The plugin never
  changes a value on its own, and never on install or enable.
- **In `~/.config/omarchy/shell.json`:** only this widget's own entry, and only
  when you edit a nickname or run `omarchy bar set` yourself. Other entries and
  settings are left as they are.
- **Nowhere else:** no other files, and no network access.

### Presets

The driver passes a raw slot number 1–5, and the wheel displays it shifted by
one:

| Button | Wheel shows | Notes                                             |
|--------|-------------|---------------------------------------------------|
| Auto   | A SET       | Auto Setup; games may adjust it                   |
| S1     | SET 1       | Custom preset                                     |
| S2–S4  | SET 2–SET 4 | Custom presets                                    |

The driver only accepts slots 1–5, so a sixth preset (SET 5) can only be
selected from the wheel itself.

## Customising

### Widget options

Options live on the widget's own entry in `~/.config/omarchy/shell.json`,
inside the bar section it sits in (usually `bar.layout.right`):

```json
{
  "id": "io.github.dgbooth.fanatec-tuning-menu",
  "pollingInterval": 5,
  "barShowProfile": false,
  "nickS1": "AMS2"
}
```

| Key              | Type    | Default | What it does                                                        |
|------------------|---------|---------|---------------------------------------------------------------------|
| `pollingInterval`| integer | `10`    | Seconds between background re-reads of the wheel (2–300). `0` turns background polling off; the panel still refreshes when opened and on right-click. |
| `barShowProfile` | boolean | `true`  | Show the active preset (`A`, `S1` … `S4`) next to the bar icon. It is always hidden on a vertical bar. |
| `nickS1` … `nickS4` | string | none | Nickname for each custom preset, up to 24 characters. Easiest set from the panel's nickname box. Auto has no nickname. |

Keys you haven't set use their default, so a fresh install has none of them.
The shell hot-reloads `shell.json` on save, so edits (by hand, through
`omarchy bar set` below, or from the panel's nickname box) apply straight away.

### From the command line

`omarchy bar set` writes an option for you. Pass `--json` for numbers and
booleans, otherwise the value is stored as text and a setting like
`barShowProfile` won't be read as a boolean:

```bash
ID=io.github.dgbooth.fanatec-tuning-menu

omarchy bar set $ID pollingInterval 5 --json      # poll every 5 s
omarchy bar set $ID barShowProfile false --json   # hide the preset label
omarchy bar set $ID nickS2 "Spa wet"              # nickname for S2 (plain text)

omarchy bar get $ID pollingInterval               # prints the value, or exits 1 if unset
```

`omarchy bar get` only returns options you've set explicitly. For one you
haven't touched it prints nothing and exits with status 1, which means the
default applies. To go back to the default, delete the key from the widget's
entry in `shell.json`.

### Where it sits on the bar

```bash
omarchy bar move $ID --section right --index 0       # first in the right section
omarchy bar move $ID --after omarchy.clock           # or next to any other widget
```

The sections are `left`, `centerBegin`, `center`, `centerEnd`, `tray` and
`right`. The plugin's default is `right`.

### Changing what the panel shows

The panel's contents are data in `Model.js`, so most tweaks don't touch the
QML. After editing a file, run `omarchy-restart-shell` to load the change.

- **Settings list**: `tuningDefs` holds each slider's label, range, step,
  default and help text. Reorder it to reorder the list, or remove an entry to
  hide a setting you never use. Entries only appear if the driver exposes
  that setting for your base, so you never need to filter by model.
- **Preset buttons**: `slotOptions` has the button labels and tooltips.
- **Names**: `baseNames` (USB product id → base name) and `wheelNames`
  (rim id → rim name). Use these to name a base or rim the plugin shows as
  unknown.
- **Slider limits**: the minimums and maximums follow Fanatec's documented
  ranges for the DD family. If you raise one, remember the wheel and driver
  still enforce their own limits and will reject values outside them.

The plugin folder is a git checkout, so `omarchy plugin update` can conflict
with local edits. If you want your changes to last, fork the repo and
`omarchy plugin add` your fork instead.

## How it works

A small shell script (`status.sh`) reads `/sys/bus/hid/drivers/fanatec/*/`
(`range`, `wheel_id`, `fw_version`) and `/sys/class/ftec_tuning/*/` (every
tuning value) and prints `key=value` lines. `Panel.qml` parses them with
`Model.js` and draws the bar widget and panel. Writes go to
`/sys/class/ftec_tuning/<device>/<NAME>`, restricted to a fixed list of
parameter names, and the panel re-reads the wheel shortly after to show what
the wheel actually accepted.

## Development

The plugin folder is a plain git checkout. Saving a file under
`~/.config/omarchy/plugins/` reloads the plugin; if a change doesn't apply, run
`omarchy-shell shell rescanPlugins` or `omarchy-restart-shell`.

```bash
omarchy plugin validate .   # manifest check, same one the store runs
node --test tests/          # Model.js unit tests, no dependencies
```

Text that doesn't come from the plugin (nicknames, names read from the
device) is stripped of markup characters before it reaches Omarchy's shared
tooltips, and every `Text` in the panel is `PlainText`.

## Security notes

**What the plugin does.** It runs no privileged commands: no `sudo`, `pkexec`,
package manager or service control. The `sudo` and package commands in this
README are for you to run yourself during setup. At runtime it reads a few
values from sysfs, writes to `/sys/class/ftec_tuning/*` only when you act on a
control (see [What it changes](#what-it-changes)), and stores its options in its
own entry in `shell.json`. It makes no network requests. Like every Omarchy
plugin it runs unsandboxed inside `omarchy-shell`, so read the code if you
want to be sure.

**The driver's udev rule.** The `hid-fanatecff-dkms` package (0.2.3) installs
`/usr/lib/udev/rules.d/99-fanatec.rules`, which contains

```
SUBSYSTEMS=="usb", ATTRS{idVendor}=="0eb7", MODE="0666"
```

That makes the matching USB and `hidraw` device nodes writable by every local
account, not just members of `games`. While a wheel is connected, any user on the
machine could reset it or detach its driver, which would disrupt the controller
whether or not this plugin is installed. The rule belongs to the upstream driver
([gotzl/hid-fanatecff](https://github.com/gotzl/hid-fanatecff)), whose rule file
carries a comment that it should be narrowed down. This plugin doesn't install or
change it.

The setup instructions deal with it as a required step instead of leaving it as
an option. [Step 2](#2-narrow-the-drivers-usb-rule) installs a local override
that restricts those nodes to the `games` group, and
[step 4](#4-reboot-and-check) has commands that confirm the active rule is
restricted (`660 root:games`). Anyone who skips step 2 still has the upstream
rule, and the exposure above.

This plugin only works with a Fanatec wheelbase and the `hid-fanatecff` driver,
so anyone using it already has the driver and its udev rule. The plugin adds no
new device access of its own: it only needs the `games` group for the tuning
files, and it doesn't depend on the `0666` rule.

## Limitations

- Developed and tested on one setup: a CSL DD-family base (`0EB7:0020`) with a
  CSL Steering Wheel GT3. On that setup, values changed in the panel reach
  the wheel, and values changed on the wheel itself show up in the panel.
  Other bases and rims should work wherever the driver creates the tuning
  files, but are untested.
- The CSL DD, GT DD Pro and ClubSport DD share one USB id, so the base is
  shown as "Fanatec DD Family". Other bases are named from the driver's
  product ids.
- Wheel rims are recognised by id. Unknown ones show as `Unknown rim (0xNN)`.
  To add one, read its id from `/sys/bus/hid/drivers/fanatec/*/wheel_id` and
  add `"0xNN": "Name"` to `wheelNames` in `Model.js` (pull requests welcome).
- The widget polls; changes made on the wheel itself appear at the next
  refresh.
- Value ranges come from the driver and Fanatec's article for the DD family;
  older bases may have different limits.

## License

MIT, see [LICENSE](LICENSE).
