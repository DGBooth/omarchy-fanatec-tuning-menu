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

### 1. Install the `hid-fanatecff` driver

On Arch / Omarchy it is in the AUR as `hid-fanatecff-dkms`:

```bash
yay -S hid-fanatecff-dkms
```

The package builds the `hid_fanatec` kernel module with DKMS and installs a
udev rule (`/usr/lib/udev/rules.d/99-fanatec.rules`). Upstream project and
supported-device list: <https://github.com/gotzl/hid-fanatecff>.

Check that it loaded and sees your base:

```bash
lsmod | grep hid_fanatec          # the module is loaded
ls /sys/class/ftec_tuning/        # one entry per tuning-capable base
cat /sys/bus/hid/drivers/fanatec/*/wheel_id   # id of the attached rim
```

If the module is missing after a kernel update, rebuild it with
`sudo dkms autoinstall` (or reinstall the package), then replug the base.

### 2. Add yourself to the `games` group

The driver's udev rule makes the tuning files writable by the **`games`**
group, not by regular users. Without it the widget is read-only and shows a
note saying so.

```bash
sudo usermod -aG games "$USER"
```

Then **reboot**. A plain log-out is often not enough: the long-running
`systemd --user` manager that your desktop session inherits its groups from
can survive a log-out and keeps the old group list. If you'd rather not
reboot, log out, switch to a TTY (Ctrl+Alt+F3), log in, run
`sudo systemctl stop user@$(id -u)`, then log back in from the display manager.

Check that it took effect:

```bash
id | grep -o games                                  # prints "games"
[ -w /sys/class/ftec_tuning/*/SLOT ] && echo writable
```

If `id` doesn't list `games`, the session hasn't picked the group up yet.

### 3. Install the plugin

```bash
omarchy plugin add https://github.com/DGBooth/omarchy-fanatec-tuning-menu.git
omarchy plugin enable io.github.dgbooth.fanatec-tuning-menu
```

Plugins land disabled so you can read the code first. This one runs
unsandboxed inside `omarchy-shell`, like every Omarchy plugin. The icon
appears at the right end of the bar; move it with
`omarchy bar move io.github.dgbooth.fanatec-tuning-menu --before omarchy.clock`
or any other placement.

Update with `omarchy plugin update`, remove with
`omarchy plugin remove io.github.dgbooth.fanatec-tuning-menu`.

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

### Settings

| Setting         | Default | Description                                          |
|-----------------|---------|------------------------------------------------------|
| Polling interval | 10 s   | How often the widget re-reads the wheel; 2–300 s     |
| Show preset in bar | on   | Show `A` / `S1` … next to the icon                   |

## How it works

A small shell script (`status.sh`) reads `/sys/bus/hid/drivers/fanatec/*/`
(`range`, `wheel_id`, `fw_version`) and `/sys/class/ftec_tuning/*/` (every
tuning value) and prints `key=value` lines. `Panel.qml` parses them with
`Model.js` and draws the bar widget and panel. Writes go to
`/sys/class/ftec_tuning/<device>/<NAME>`, restricted to a fixed list of
parameter names, and the panel re-reads the wheel shortly after to show what
the wheel actually accepted.

## Limitations

- Developed and tested on one setup: a CSL DD-family base (`0EB7:0020`) with a
  CSL Steering Wheel GT3. Other bases and rims should work wherever the driver
  creates the tuning files, but are untested.
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
