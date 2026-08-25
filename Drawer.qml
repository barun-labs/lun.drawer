import QtQuick

// Collapsible drawer for other bar widgets: tucks a configured list of
// widgets behind a chevron and reveals them on hover, like a tray overflow.
// The reveal/animation shape mirrors the tray widget: an `expanded` bool,
// `revealProgress` (0..1) animated by a NumberAnimation Behavior, and a
// chevron that sits at the collapsed edge and slides as the drawer opens.
Item {
  id: root

  property var bar
  property string moduleName
  property var settings

  property bool hovered: false
  property bool dragHover: false        // pointer is over us during a live bar drag
  property bool expanded: hovered || dragHover || reorderSourceIndex >= 0
  property real revealProgress: expanded ? 1 : 0

  property string pendingDropId: ""     // id of the widget that would drop into us on release

  // --- Reorder widgets within the drawer --------------------------------
  property int reorderSourceIndex: -1   // entry index being dragged, -1 when idle
  property int reorderTargetIndex: -1   // entry index it would drop before, -1 when idle
  property bool reorderEject: false     // true while the drag would pop the widget out onto the bar
  property int  reorderEjectEdge: 0     // -1 = left/top edge crossed, +1 = right/bottom (or perpendicular pull)

  readonly property color foreground: bar ? bar.foreground : "white"
  readonly property string fontFamily: bar ? bar.fontFamily : "monospace"
  readonly property int barExtent: bar ? bar.barSize : 26
  readonly property int glyphSize: Math.round(barExtent * 0.45)

  // Bar orientation: left/right bars stack widgets vertically. Injected `bar`
  // exposes this; default horizontal when the bar isn't wired yet.
  readonly property bool vertical: bar ? (bar.vertical === true) : false

  // Each settings.items entry is either a widget id string or an object with
  // an "id" key plus extra keys that become that widget's own settings — the
  // same shape BarModel.entrySettings produces. Re-evaluated whenever the
  // injected settings object is replaced.
  readonly property var entries: buildEntries()

  function buildEntries() {
    var result = []
    // settings crosses a QML `property var` boundary, so settings.items arrives
    // as a QVariantList, not a real JS Array — Array.isArray() returns false on
    // it. Accept anything array-like (has a numeric length) instead; index access
    // still yields the per-entry objects.
    var raw = settings ? settings.items : null
    var items = (raw && typeof raw.length === "number") ? raw : []
    for (var i = 0; i < items.length; i++) {
      var entry = items[i]
      var id = ""
      var entrySettings = {}
      if (typeof entry === "string") {
        id = entry
      } else if (entry && typeof entry === "object") {
        id = String(entry.id || "")
        for (var key in entry) if (key !== "id") entrySettings[key] = entry[key]
      }
      if (id) result.push({ id: id, settings: entrySettings })
    }
    return result
  }

  // Reading `.widgets` here makes every binding that goes through `registry`
  // re-evaluate when the bar widget registry mutates (a widget registers or
  // unregisters) — the same dependency trick Bar.qml's ModuleSlot uses.
  readonly property var registry: bar && bar.barWidgetRegistry ? bar.barWidgetRegistry.widgets : ({})

  // Natural extent of the hidden widgets, measured from the positioner itself
  // (a plain Item does not adopt its child Row/Column implicit size, so we must
  // read drawerRow/drawerColumn directly or the reveal stays 0-wide).
  readonly property int drawerExtent: root.vertical ? drawerColumn.implicitHeight : drawerRow.implicitWidth
  readonly property real revealExtent: drawerExtent * revealProgress

  implicitWidth: root.vertical ? barExtent : chevron.implicitWidth + revealExtent
  implicitHeight: root.vertical ? chevron.implicitHeight + revealExtent : barExtent
  clip: true

  Behavior on revealProgress {
    NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
  }

  HoverHandler {
    onHoveredChanged: root.hovered = hovered
  }

  // --- Drag a bar widget INTO the drawer ---------------------------------
  // Bar.qml owns the drag; we observe it. `bar.barDragTarget` is the slot the
  // pointer is over (already same-window/visibility filtered by the bar), so
  // "over us" == its moduleName is ours. On release (barDragSource clears) while
  // over us, we splice the dragged widget's config entry into our `items`.
  // The bar's own drop fires first and merely repositions the widget next to our
  // slot; our deferred claim then moves it into items — both converge.
  // NOTE: rides on Bar.qml internals (barDragSource/barDragTarget). If a future
  // Omarchy renames them the Connections simply never fire — drag-into degrades
  // off, the rest of the drawer is unaffected.
  Connections {
    target: root.bar
    // `bar` is undefined when this Connections is created, so QML briefly binds
    // to the default target (our parent), which has no barDrag* signals and logs
    // a warning. It rebinds correctly once `bar` injects; silence the transient.
    ignoreUnknownSignals: true

    function onBarDragTargetChanged() {
      var t = root.bar ? root.bar.barDragTarget : null
      if (t && t.moduleName === root.moduleName) {
        root.dragHover = true
        var src = root.bar.barDragSource
        root.pendingDropId = (src && src.moduleName) ? src.moduleName : ""
      } else {
        root.dragHover = false
        root.pendingDropId = ""
      }
    }

    function onBarDragSourceChanged() {
      if (root.bar && root.bar.barDragSource) return   // a drag started or is ongoing
      var id = root.pendingDropId                      // captured before we clear it
      root.dragHover = false
      root.pendingDropId = ""
      if (id && id !== root.moduleName)
        Qt.callLater(function() { root.claimWidget(id) })
    }
  }

  // Move the widget with id `id` out of its bar section and into our items[].
  function claimWidget(id) {
    var shell = root.bar ? root.bar.shell : null
    if (!shell || typeof shell.mutateShellConfig !== "function") return
    shell.mutateShellConfig(function(config) {
      if (!config.bar || !config.bar.layout) return
      var layout = config.bar.layout
      var sections = ["left", "center", "right"]

      function entryIdOf(entry) {
        if (typeof entry === "string") return entry
        return (entry && typeof entry === "object") ? String(entry.id || "") : ""
      }

      // Pull the dragged entry (whole object, keeping inline settings) out.
      var moved = null
      for (var s = 0; s < sections.length && moved === null; s++) {
        var arr = layout[sections[s]]
        if (!Array.isArray(arr)) continue
        for (var i = 0; i < arr.length; i++) {
          if (entryIdOf(arr[i]) === id) { moved = arr.splice(i, 1)[0]; break }
        }
      }
      if (moved === null) return

      // Find our own drawer entry object; append the widget to its items.
      var mine = null
      for (var s2 = 0; s2 < sections.length && mine === null; s2++) {
        var arr2 = layout[sections[s2]]
        if (!Array.isArray(arr2)) continue
        for (var j = 0; j < arr2.length; j++) {
          var e = arr2[j]
          if (e && typeof e === "object" && entryIdOf(e) === root.moduleName) { mine = e; break }
        }
      }
      if (mine === null) return
      if (!Array.isArray(mine.items)) mine.items = []
      // moved is already out of its section by this point, so discarding it here
      // (as an early return once did) would lose it. Only skip the push when an
      // entry with this id is already in items; the section-removal above still
      // happened either way, keeping the "never in both places" invariant.
      var alreadyInItems = false
      for (var k = 0; k < mine.items.length; k++) {
        if (entryIdOf(mine.items[k]) === id) { alreadyInItems = true; break }
      }
      if (!alreadyInItems) mine.items.push(moved)

      // A third-party widget pulled out of the bar layout is otherwise treated
      // as disabled and never registers, so the drawer's Loader would get a null
      // component and mount nothing. Recording it in plugins[] is the only
      // enable-path that keeps it registered WITHOUT putting it back on the bar;
      // a bar-widget there does not double-render (only panel/overlay/menu/service
      // kinds match those loaders). Also drop any stale disabledPlugins entry,
      // which isEnabled checks first and would veto the registration.
      if (!Array.isArray(config.plugins)) config.plugins = []
      var alreadyEnabled = false
      for (var p = 0; p < config.plugins.length; p++) {
        if (entryIdOf(config.plugins[p]) === id) { alreadyEnabled = true; break }
      }
      if (!alreadyEnabled) config.plugins.push({ id: id })
      if (Array.isArray(config.disabledPlugins)) {
        for (var d = config.disabledPlugins.length - 1; d >= 0; d--) {
          if (entryIdOf(config.disabledPlugins[d]) === id) config.disabledPlugins.splice(d, 1)
        }
      }
    })
  }

  // Move our items[from] to insertion slot `slot` and save. `from` is an item
  // index; `slot` is an insertion slot from entryIndexAt (see its contract).
  // Silent no-op on any missing piece — never throw.
  function reorderItems(from, slot) {
    if (from < 0 || slot < 0) return
    var shell = root.bar ? root.bar.shell : null
    if (!shell || typeof shell.mutateShellConfig !== "function") return
    shell.mutateShellConfig(function(config) {
      if (!config.bar || !config.bar.layout) return
      var layout = config.bar.layout
      var sections = ["left", "center", "right"]
      function entryIdOf(entry) {
        if (typeof entry === "string") return entry
        return (entry && typeof entry === "object") ? String(entry.id || "") : ""
      }
      var mine = null
      for (var s = 0; s < sections.length && mine === null; s++) {
        var arr = layout[sections[s]]
        if (!Array.isArray(arr)) continue
        for (var j = 0; j < arr.length; j++) {
          if (arr[j] && typeof arr[j] === "object" && entryIdOf(arr[j]) === root.moduleName) { mine = arr[j]; break }
        }
      }
      if (mine === null || !Array.isArray(mine.items)) return
      if (from >= mine.items.length) return
      var moved = mine.items.splice(from, 1)[0]
      // The splice-out shifted everything after `from` left by one, so a slot
      // that was past `from` must shift down to still mean the same place.
      if (from < slot) slot--
      if (slot === from) {
        mine.items.splice(from, 0, moved)  // no-op move: dropped back where it started
        return
      }
      mine.items.splice(slot, 0, moved)
    })
  }

  // Pop items[from] out of the drawer and back onto the bar, into the drawer's own
  // section adjacent to the drawer slot. edge < 0 inserts BEFORE the drawer slot
  // (leading side), otherwise AFTER it. Mirror of claimWidget; leaves plugins[]
  // alone (a bar widget listed there does not double-render). Silent no-op on any
  // missing piece — never throw. Caller defers this (it destroys the delegate).
  function ejectWidget(from, edge) {
    if (from < 0) return
    var shell = root.bar ? root.bar.shell : null
    if (!shell || typeof shell.mutateShellConfig !== "function") return
    shell.mutateShellConfig(function(config) {
      if (!config.bar || !config.bar.layout) return
      var layout = config.bar.layout
      var sections = ["left", "center", "right"]
      function entryIdOf(entry) {
        if (typeof entry === "string") return entry
        return (entry && typeof entry === "object") ? String(entry.id || "") : ""
      }
      var arr = null, mi = -1
      for (var s = 0; s < sections.length && arr === null; s++) {
        var a = layout[sections[s]]
        if (!Array.isArray(a)) continue
        for (var j = 0; j < a.length; j++) {
          if (a[j] && typeof a[j] === "object" && entryIdOf(a[j]) === root.moduleName) { arr = a; mi = j; break }
        }
      }
      if (arr === null) return
      var mine = arr[mi]
      if (!Array.isArray(mine.items) || from >= mine.items.length) return
      var moved = mine.items.splice(from, 1)[0]
      var at = (edge < 0) ? mi : mi + 1
      arr.splice(at, 0, moved)
    })
  }

  // Given a coordinate along the positioner (x for horizontal, y for vertical),
  // return an INSERTION SLOT in [0, N] (N = root.entries.length) — a position in
  // the FULL items array, so hidden zero-extent entries still count as slots and
  // "after the last item" (slot === N) is expressible. Counting only VISIBLE
  // (non-zero-extent) delegates for the geometry test: a pointer past a visible
  // child's midpoint lands after it (that child's index + 1); before the first
  // visible child lands on it.
  function entryIndexAt(pos) {
    var positioner = root.vertical ? drawerColumn : drawerRow
    var best = -1
    var kids = positioner.children
    for (var i = 0; i < kids.length; i++) {
      var k = kids[i]
      if (!k || k.index === undefined) continue          // skip the Repeater item itself
      var extent = root.vertical ? k.height : k.width
      if (extent <= 0) continue                          // hidden widget, no visual slot
      var start = root.vertical ? k.y : k.x
      var mid = start + extent / 2
      if (pos >= mid) best = k.index + 1                 // pointer is past this one's middle
      else if (best < 0) best = k.index                  // before the first visible: land on it
    }
    return Math.max(0, Math.min(best, root.entries.length))
  }

  // Axis coordinate (within the reveal Item) of the leading edge of insertion
  // `slot`, for positioning the drop marker. Reads the positioner children like
  // entryIndexAt. slot === N (past the last item) returns the trailing edge.
  function slotOffset(slot) {
    var positioner = root.vertical ? drawerColumn : drawerRow
    var base = root.vertical ? positioner.y : positioner.x
    var lastEnd = base
    var kids = positioner.children
    for (var i = 0; i < kids.length; i++) {
      var k = kids[i]
      if (!k || k.index === undefined) continue          // skip the Repeater node
      var extent = root.vertical ? k.height : k.width
      var start = root.vertical ? k.y : k.x
      if (extent > 0) lastEnd = base + start + extent
      if (k.index === slot) return base + start
    }
    return lastEnd
  }

  Component {
    id: entryLoaderComponent

    Item {
      id: entryRoot
      required property var modelData
      required property int index
      // Follow the Loader's collapsed-or-natural extent so the Row/Column lays us out
      // exactly like before (hidden widgets stay zero-extent).
      width:  entryLoader.width
      height: entryLoader.height
      // Entry settings edited in place: re-inject without reloading. `modelData`
      // lives here now, so its change handler must too (not on the Loader).
      onModelDataChanged: entryLoader.injectProps()

      Loader {
        id: entryLoader
        // No anchors: the Loader sizes itself (showing ? implicitWidth : 0) and
        // entryRoot follows entryLoader.width — anchoring to parent would loop.

        // null when the id is not registered — the Loader stays empty, no crash.
        sourceComponent: root.registry[modelData.id] ? root.registry[modelData.id].component : null

        // A bar widget hides itself (visible:false) when it has nothing to show —
        // omapods with no AirPods, onedrive idle, a disconnected VPN. The bar's own
        // slots collapse to ZERO WIDTH in that case (Bar.qml ModuleSlot); mirror it
        // so an idle widget leaves no reserved gap. We must NOT bind the Loader's
        // `visible` to item.visible: that property reports EFFECTIVE visibility, so
        // hiding the Loader feeds back and latches every widget off. Instead keep the
        // Loader visible and collapse its own extent, clipping the mounted widget.
        readonly property bool showing: item && item.visible
        // Same reason as the containers above: a hidden widget collapses to 0 extent
        // but its mounted item keeps full size, so it would still take clicks meant
        // for whatever the Row shifted into that spot.
        enabled: showing
        clip: true
        width:  root.vertical ? root.barExtent : (showing ? item.implicitWidth : 0)
        height: root.vertical ? (showing ? item.implicitHeight : 0) : root.barExtent

        onLoaded: {
          injectProps()
          Qt.callLater(injectProps)
        }

        function injectProps() {
          var target = entryLoader.item
          if (!target) return
          if ("bar" in target) target.bar = root.bar
          if ("moduleName" in target) target.moduleName = modelData.id
          if ("settings" in target) target.settings = modelData.settings
        }
      }

      // Drag-to-reorder. A MouseArea here would be dead code: the bar's own
      // modulePointer MouseArea is declared after our Loader in the shipped
      // ModuleSlot, at the same z, so it overlays the whole drawer and grabs
      // every left press first. A DragHandler instead takes a PASSIVE grab on
      // press (delivered the point despite the overlay) and, once past
      // dragThreshold, takes the EXCLUSIVE grab from modulePointer — canceling
      // the bar's whole-drawer drag before it starts.
      DragHandler {
        id: dragHandler
        target: null                     // do NOT visually translate entryRoot
        enabled: entryLoader.showing      // only draggable when the widget is visible
        // ponytail: 2, not 3. Verified with a Qt QTest harness driving synthetic
        // moves into the delivery agent: the exclusive-grab steal lags ~1 move
        // event, so at 3 the bar's modulePointer still crosses its own 4px
        // (Style.space(4)) threshold and lifts the whole drawer. 2 leaves margin —
        // clicks with up to 2px jitter still register, a 3px+ drag reorders, and
        // the bar never lifts on a normal (stepped) drag. Ceiling: a fast flick
        // whose single motion delta is >=~5px can still start the bar's drag; the
        // fix for that would be to drive reorder from the bar's own drag machinery.
        dragThreshold: 2

        onActiveChanged: {
          if (active) {
            root.reorderSourceIndex = entryRoot.index
            root.reorderEject = false
            root.reorderEjectEdge = 0
          } else {
            var from = root.reorderSourceIndex
            var slot = root.reorderTargetIndex
            var eject = root.reorderEject
            var edge = root.reorderEjectEdge
            root.reorderSourceIndex = -1
            root.reorderTargetIndex = -1
            root.reorderEject = false
            root.reorderEjectEdge = 0
            if (eject) {
              // Eject rebuilds entries and destroys THIS delegate mid-handler, so
              // defer (same reason claimWidget defers its call).
              var f = from
              var e = edge
              Qt.callLater(function() { root.ejectWidget(f, e) })
            } else if (slot >= 0) {
              root.reorderItems(from, slot)
            }
          }
        }

        onCentroidChanged: {
          if (!active) return
          var m = root.barExtent
          // One mapping into root: if the pointer leaves root's rect by > m in ANY
          // direction (sideways past an end, or pulled off the bar), it's an eject.
          var r = entryRoot.mapToItem(root, centroid.position.x, centroid.position.y)
          if (r.x < -m || r.x > root.width + m || r.y < -m || r.y > root.height + m) {
            root.reorderEject = true
            if (root.vertical) root.reorderEjectEdge = (r.y < 0) ? -1 : 1
            else               root.reorderEjectEdge = (r.x < 0) ? -1 : 1
            root.reorderTargetIndex = -1
          } else {
            root.reorderEject = false
            var p = entryRoot.mapToItem(root.vertical ? drawerColumn : drawerRow,
                                         centroid.position.x, centroid.position.y)
            var pos = root.vertical ? p.y : p.x
            root.reorderTargetIndex = root.entryIndexAt(pos)
          }
        }
      }

      // Subtle drag feedback, nothing flashy (user wants a clean look).
      opacity: (root.reorderSourceIndex === entryRoot.index) ? (root.reorderEject ? 0.25 : 0.4) : 1.0
    }
  }

  // Reveal container sits just left of the chevron and grows from 0 to the full
  // natural width as revealProgress animates; the Row is pinned to its right edge
  // so widgets slide out from behind the chevron. clip hides them when collapsed.
  Item {
    id: drawerHorizontal
    width: root.revealExtent
    height: root.barExtent
    anchors.right: chevron.left
    anchors.verticalCenter: parent.verticalCenter
    // revealProgress 0 must mean "not there": clip is VISUAL only, so a collapsed
    // drawer still hit-tests. The Row is anchored to the container's right edge and
    // the container is 0-wide when collapsed, so the widgets sit at negative x,
    // exactly under the bar icons left of the chevron, which is why clicking one of
    // those sometimes fired a drawer widget instead. visible:false stops delivery.
    visible: !root.vertical && root.revealProgress > 0
    clip: true

    Row {
      id: drawerRow
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      Repeater {
        model: root.entries
        delegate: entryLoaderComponent
      }
    }

    Rectangle {
      id: dropMarkerH
      width: 2
      height: parent.height
      color: root.foreground
      z: 10
      visible: root.reorderSourceIndex >= 0 && !root.reorderEject && root.reorderTargetIndex >= 0
      x: root.slotOffset(root.reorderTargetIndex)
    }
  }

  Item {
    id: drawerVertical
    width: root.barExtent
    height: root.revealExtent
    anchors.bottom: chevron.top
    anchors.horizontalCenter: parent.horizontalCenter
    visible: root.vertical && root.revealProgress > 0   // see drawerHorizontal
    clip: true

    Column {
      id: drawerColumn
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      Repeater {
        model: root.entries
        delegate: entryLoaderComponent
      }
    }

    Rectangle {
      id: dropMarkerV
      width: parent.width
      height: 2
      color: root.foreground
      z: 10
      visible: root.reorderSourceIndex >= 0 && !root.reorderEject && root.reorderTargetIndex >= 0
      y: root.slotOffset(root.reorderTargetIndex)
    }
  }

  Text {
    id: chevron
    anchors.right: root.vertical ? undefined : parent.right
    anchors.bottom: root.vertical ? parent.bottom : undefined
    anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
    anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
    // "More" affordance, deliberately NOT a chevron: the system tray already
    // shows its own chevron, and two identical chevrons read as a bug. Ellipsis
    // (horizontal on a top/bottom bar, vertical on a side bar) signals "hidden
    // widgets here" without duplicating the tray's glyph.
    text: root.vertical ? "\uf142" : "\uf141"
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.glyphSize
  }

  // Tooltip on the chevron: the chevron is the deepest hover target, so its
  // MouseArea fires before the root HoverHandler flips `expanded` and the
  // text shows the state the user is about to change.
  MouseArea {
    anchors.fill: chevron
    acceptedButtons: Qt.NoButton
    hoverEnabled: true
    onEntered: if (root.bar && root.bar.showTooltip && root.entries.length > 0) root.bar.showTooltip(chevron, root.expanded ? "Hide" : ("Show " + root.entries.length + " hidden"))
    onExited: if (root.bar && root.bar.hideTooltip) root.bar.hideTooltip(chevron)
  }
}
