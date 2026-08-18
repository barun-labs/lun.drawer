# lun.drawer

A collapsible drawer for the [Omarchy](https://omarchy.org/) 4 bar (Quickshell).
It tucks a chosen set of bar widgets behind a `•••` glyph and reveals them on
hover — like the system-tray overflow, but for **any** bar widget, not just SNI
tray icons. Keep the widgets you rarely glance at out of sight, and pull them up
only when you want them.

What you can do:

- **Hover** the `•••` to reveal the hidden widgets; move the cursor away and they
  collapse again.
- **Drag** any bar widget onto the `•••` to hide it in the drawer — the move is
  saved to `shell.json`, no manual editing.
- Inside the open drawer, **drag a widget sideways to reorder** it (a thin marker
  line shows where it will land), or **drag it off the drawer to pop it back onto
  the bar**.

## Install

Omarchy loads plugins from `~/.config/omarchy/plugins/<id>/`, and it does **not**
allow symlinks inside a plugin folder — so install a real copy of the files:

```bash
git clone https://github.com/barun-labs/lun.drawer.git
mkdir -p ~/.config/omarchy/plugins
cp -r lun.drawer ~/.config/omarchy/plugins/lun.drawer
rm -rf ~/.config/omarchy/plugins/lun.drawer/.git   # the plugin folder holds plugin files only
omarchy plugin validate ~/.config/omarchy/plugins/lun.drawer   # prints nothing, exits 0 on success
omarchy restart shell
```

To update later, re-copy the files over the installed copy and `omarchy restart shell`.

## Configure

Add a `lun.drawer` entry to a bar section in `~/.config/omarchy/shell.json` and
list the widget ids to hide under `items`. Move those ids **out** of their normal
section (leaving them there too would show them twice).

```jsonc
{
  "id": "lun.drawer",
  "items": [
    "io.github.thisisgm.omapods",              // bare id
    { "id": "vitals", "pollIntervalMs": 500 }  // id + that widget's own settings
  ]
}
```

Each entry is either a bare id string or an object with `id` plus that widget's
settings (the same shape as a normal bar layout entry). Unknown ids are skipped,
not fatal. `allowMultiple` is true — put one drawer left and one right if you like.

A widget that hides itself when it has nothing to show (empty AirPods, idle
OneDrive, a disconnected VPN) collapses to nothing inside the drawer too — the
reveal only shows widgets that currently have something to display.

Reload after editing by hand: `omarchy shell shell reloadConfig` (or
`omarchy restart shell`).

### Keeping hidden widgets alive

A third-party widget listed only under `items` is no longer in any bar layout
section, which Omarchy treats as "disabled" — it would never load, and the drawer
would show a blank slot. To prevent that, dragging a widget in also adds
`{ "id": "..." }` to the top-level `plugins` array (and clears any
`disabledPlugins` entry). A bar widget listed in `plugins` stays registered but
does not appear on the bar, so it renders only inside the drawer.

To take a widget out of the drawer for good, remove it from the drawer's `items`
**and** delete its `{ "id": ... }` from the top-level `plugins` array.

## Using it

**Drag a widget into the drawer.** Drag any bar widget onto the `•••` and release —
it is tucked into the drawer and saved to `shell.json`. The drawer opens as you
drag over it to show the drop will land there.

**Reorder inside the drawer.** Open the drawer, press a widget and drag it among
the others; a thin marker line shows where it will land. Release to save the new
order.

**Drag a widget back out onto the bar.** Press a widget in the open drawer and drag
it *off* the drawer — sideways past either end, or down/away off the bar — then
release. It lands on the bar next to the drawer, on the side you dragged toward.

Reorder and drag-out are a best-effort gesture: they compete with the bar's own
drag-to-reorder, which owns the drawer's whole slot. **Drag deliberately, not with
a fast flick** — a violent outward flick can still trip the bar's own whole-drawer
drag. If a future Omarchy release changes how the bar claims that press, the
gesture may fall back to moving the whole drawer; when that happens, reorder by
hand instead — edit the order of ids under this drawer's `items` in `shell.json`,
then run `omarchy shell shell reloadConfig` (it repaints live).

Clicking a widget inside the open drawer works normally.

### System-tray icons (Bitwarden, Claude, …)

Icons that belong to the system tray (SNI icons) live *inside* the tray widget,
not the drawer, so you can't drag them out individually — the drawer (and the bar)
moves the tray as one unit. To surface a buried tray icon, **pin it** instead: the
tray has a per-icon Pin control, or set `pinned` on the tray's own settings, e.g.
`{ "id": "lun.tray", "pinned": ["Bitwarden_status_icon_1", "Claude_status_icon_1"] }`.
Pinned icons sit outside the tray's `<` overflow. (Find an icon's id with
`busctl --user get-property <service> /StatusNotifierItem org.kde.StatusNotifierItem Id`.)

## How it works

The drawer mounts inside a single bar module slot and renders the hidden widgets
with a Quickshell `Repeater`. Drag-into rides the shipped bar's own drag internals
(`barDragSource` / `barDragTarget`): the bar drops the widget next to the drawer,
then the drawer claims it into `items`. Reorder and drag-out use a per-item
`DragHandler` that takes the pointer grab from the bar's slot-level handler once a
drag passes its threshold, so the gesture reorders or ejects the inner widget
instead of lifting the whole drawer.

Because it leans on those internals, drag-into and the reorder/eject gesture are
best-effort: if a future Omarchy renames or restructures them, those gestures
degrade off while the rest of the drawer (hover-reveal, hiding widgets via `items`)
keeps working.

## License

MIT — see [LICENSE](LICENSE).
