/*
 * Connected-room commands for the toolkit's Tiled worlds (File menu, Tiled 1.11+):
 *
 * - Add Connected Room...  builds a new room beside the active room, inside the
 *   same world, with a closed bounds ring and door cells painted in both rooms
 *   on the shared edge. It reuses the active room's own bounds and door tiles.
 * - Copy Room Properties to Rooms...  copies the ticked map properties
 *   (region, darkness, room zone, music, combat music) from the active room
 *   to the world's rooms whose file names contain a filter text, after
 *   listing them for confirmation. room_title and room_title_card are never
 *   copied.
 * - Check Door Seams       reads every room of the world and reports doors
 *   with no match, doors whose spans miss, and overlapping rooms, with the
 *   same rule and words as the world layout check in Prepare & Check
 *   (developer/tools/world_layout.lua `connect`), which stays the authority.
 *
 * Neither command touches a bounds ring of an existing room: door cells sit
 * on the edge row or column, in line with a closed ring.
 */

(function () {
    // The open project's copy wins; otherwise the newest copy registers.
    // Re-registering an action replaces it, so attach the menu items again.
    var _g = (typeof globalThis !== "undefined") ? globalThis : this;
    var projectPath = typeof tiled !== "undefined" ? String(tiled.projectFilePath || "").replace(/\\/g, "/") : "";
    var scriptPath = typeof __filename !== "undefined" ? String(__filename).replace(/\\/g, "/") : "";
    var projectFolder = projectPath.slice(0, projectPath.lastIndexOf("/") + 1);
    var isProjectCopy = !!(projectFolder && scriptPath && typeof tiled !== "undefined" &&
        (tiled.platform === "windows" ? scriptPath.toLowerCase().indexOf(projectFolder.toLowerCase()) === 0 : scriptPath.indexOf(projectFolder) === 0));
    function keepExisting(api, versionIsCurrent) {
        var fromProject = !!(api && api.fromProject);
        if (fromProject !== isProjectCopy) return fromProject;
        // At equal provenance, keep the existing version rule.
        return !!versionIsCurrent;
    }
    var version = 4;
    if (keepExisting(_g.MVTKWorldRooms, _g.MVTKWorldRooms && _g.MVTKWorldRooms.version >= version)) return;

    var EPS = 0.001;
    var SIDES = ["right", "left", "up", "down"];
    var SIDE_LABELS = ["Right", "Left", "Top", "Bottom"];
    var OPPOSITE = { left: "right", right: "left", up: "down", down: "up" };
    var DOOR_LAYER = { left: "door_left", right: "door_right", up: "door_top", down: "door_bottom" };
    // Map properties a new room takes from its neighbour. is_starting_room is
    // never copied: a world has exactly one starting room.
    var COPIED_PROPERTIES = ["biome", "darkness", "room_zone", "music", "combat_music"];
    // Copy Room Properties offers the same five, never room_title or
    // room_title_card: those name one room.
    var PROPERTY_LABELS = { biome: "Region (biome)", darkness: "Darkness", room_zone: "Room zone (room_zone)",
        music: "Music", combat_music: "Combat music (combat_music)" };
    // The room id rule of developer/tools/world_layout.lua (Lua %w is ASCII
    // letters and digits) and of File > Export All Maps and Tiled World.
    var ROOM_ID = /^[A-Za-z0-9_][A-Za-z0-9_-]*$/;

    function horizontalSide(side) { return side === "left" || side === "right"; }

    // ---------------------------------------------------------------------
    // Pure functions (published on MVTKWorldRooms for tests)
    // ---------------------------------------------------------------------

    // Same normalisation and side names as mvtk/editor/room_doors.lua.
    function normalizeLayerName(name) {
        return String(name || "").toLowerCase().replace(/[\s\-]+/g, "_").replace(/__+/g, "_");
    }
    function doorSide(layerName) {
        var n = normalizeLayerName(layerName);
        if (/^doors?_left$/.test(n) || /^left_doors?$/.test(n) || n === "door_l") return "left";
        if (/^doors?_right$/.test(n) || /^right_doors?$/.test(n) || n === "door_r") return "right";
        if (/^doors?_up$/.test(n) || /^up_doors?$/.test(n) || /^doors?_top$/.test(n) || n === "door_u") return "up";
        if (/^doors?_down$/.test(n) || /^down_doors?$/.test(n) || /^doors?_bottom$/.test(n) || n === "door_d") return "down";
        return null;
    }

    // Strict overlap, as world_layout.lua `connect`: rooms that only touch do
    // not overlap.
    function overlaps(a, b) {
        return Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x) > EPS &&
            Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y) > EPS;
    }

    // The cells of a door on one edge of a width x height room, in tiles.
    // start counts along the edge: rows for left/right, columns for up/down.
    function doorCells(side, width, height, start, span) {
        var cells = [], i;
        for (i = start; i < start + span; i++) {
            if (side === "left") cells.push({ x: 0, y: i });
            else if (side === "right") cells.push({ x: width - 1, y: i });
            else if (side === "up") cells.push({ x: i, y: 0 });
            else cells.push({ x: i, y: height - 1 });
        }
        return cells;
    }

    // The closed bounds ring of a width x height room, in tiles.
    function ringCells(width, height) {
        var cells = [], x, y;
        for (x = 0; x < width; x++) {
            cells.push({ x: x, y: 0 });
            if (height > 1) cells.push({ x: x, y: height - 1 });
        }
        for (y = 1; y < height - 1; y++) {
            cells.push({ x: 0, y: y });
            if (width > 1) cells.push({ x: width - 1, y: y });
        }
        return cells;
    }

    // The new room's rectangle in world pixels. sizePx is the new room's
    // {width, height}; tile is {width, height}. The two door starts are cells
    // along the shared edge, so the doors line up cell for cell.
    function neighborRect(sourceRect, side, sizePx, doorStartSource, doorStartNew, tile) {
        var shiftX = (doorStartSource - doorStartNew) * tile.width;
        var shiftY = (doorStartSource - doorStartNew) * tile.height;
        if (side === "right") return { x: sourceRect.x + sourceRect.width, y: sourceRect.y + shiftY, width: sizePx.width, height: sizePx.height };
        if (side === "left") return { x: sourceRect.x - sizePx.width, y: sourceRect.y + shiftY, width: sizePx.width, height: sizePx.height };
        if (side === "up") return { x: sourceRect.x + shiftX, y: sourceRect.y - sizePx.height, width: sizePx.width, height: sizePx.height };
        return { x: sourceRect.x + shiftX, y: sourceRect.y + sourceRect.height, width: sizePx.width, height: sizePx.height };
    }

    // The default door on one side of a room whose edge is `length` cells:
    // just above the floor row for left and right, centred for up and down.
    // Corner cells belong to the ring's turn, so a door never uses them.
    function defaultDoor(side, length) {
        var span = horizontalSide(side) ? 3 : 2;
        span = Math.max(1, Math.min(span, length - 2));
        var offset = horizontalSide(side) ? length - 1 - span : Math.floor((length - span) / 2);
        return { span: span, offset: Math.max(1, offset) };
    }

    // Where the new room's door starts: the same distance from the bottom
    // (left and right) or from the centre (up and down) as the source door,
    // kept off the corners.
    function newDoorStart(side, sourceLength, newLength, offset, span) {
        var start = horizontalSide(side) ? newLength - (sourceLength - offset)
            : offset + Math.floor((newLength - sourceLength) / 2);
        return Math.max(1, Math.min(start, newLength - 1 - span));
    }

    // Consecutive integers -> [{start, end}] (inclusive), as room_doors.lua
    // group_runs.
    function groupRuns(sorted) {
        var runs = [], i = 0;
        while (i < sorted.length) {
            var j = i;
            while (j + 1 < sorted.length && sorted[j + 1] === sorted[j] + 1) j++;
            runs.push({ start: sorted[i], end: sorted[j] });
            i = j + 1;
        }
        return runs;
    }

    // Door runs on one side, from the painted cells of that side's layer.
    // As room_doors.lua: every painted cell counts (tile 0 too), a door is a
    // run of consecutive rows (left/right) or columns (up/down) inside the
    // bounds box, wherever the cells sit across it.
    function doorRuns(side, cells, bounds) {
        var mark = {}, list = [], i, limit = horizontalSide(side) ? bounds.h : bounds.w;
        for (i = 0; i < cells.length; i++) {
            var v = horizontalSide(side) ? cells[i].y - bounds.y : cells[i].x - bounds.x;
            if (v >= 0 && v < limit) mark[v] = true;
        }
        for (i = 0; i < limit; i++) if (mark[i]) list.push(i);
        var runs = groupRuns(list);
        // room_doors.lua numbers left and right doors in Defold's bottom-up
        // rows, so the lowest door is exit 1 there as here.
        if (horizontalSide(side)) runs.reverse();
        return runs;
    }

    // One room for seamReport, from cell lists in tiles:
    // spec {id, x, y (world pixels of the map's top-left), tileWidth,
    // tileHeight, bounds: [cells], doors: {left: [cells], ...}}.
    // The room rectangle is the bounds box, as world_layout.lua.
    function roomFromCells(spec) {
        var cells = spec.bounds || [];
        if (!cells.length) return { id: spec.id, error: spec.id + ": the bounds layer is empty; paint a closed bounds ring." };
        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity, i;
        for (i = 0; i < cells.length; i++) {
            minX = Math.min(minX, cells[i].x); minY = Math.min(minY, cells[i].y);
            maxX = Math.max(maxX, cells[i].x); maxY = Math.max(maxY, cells[i].y);
        }
        var box = { x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1 };
        var tw = spec.tileWidth, th = spec.tileHeight;
        var room = { id: spec.id, x: spec.x + minX * tw, y: spec.y + minY * th, width: box.w * tw, height: box.h * th, doors: [] };
        ["left", "right", "up", "down"].forEach(function (side) {
            doorRuns(side, (spec.doors && spec.doors[side]) || [], box).forEach(function (run) {
                var size = horizontalSide(side) ? th : tw, origin = horizontalSide(side) ? room.y : room.x;
                room.doors.push({ side: side, from: origin + run.start * size, to: origin + (run.end + 1) * size });
            });
        });
        return room;
    }

    // The seam rule of developer/tools/world_layout.lua `connect`, in Tiled's
    // y-down pixels: opposite sides, a gap of 0 at the bounds edge, and spans
    // that overlap by more than 0.001. rooms: [{id, x, y, width, height,
    // doors: [{side, from, to}]}]. Unlike `connect`, it lists every problem
    // instead of stopping at the first overlap or ambiguous door.
    function seamReport(rooms) {
        var list = rooms.slice().sort(function (a, b) { return a.id < b.id ? -1 : a.id > b.id ? 1 : 0; });
        var problems = [], used = {}, neighbors = {}, connections = 0, i, j;
        list.forEach(function (r) { neighbors[r.id] = []; });
        function gapOf(a, b, side) {
            if (side === "right") return b.x - (a.x + a.width);
            if (side === "left") return a.x - (b.x + b.width);
            if (side === "up") return a.y - (b.y + b.height);
            return b.y - (a.y + a.height);
        }
        for (i = 0; i < list.length; i++) for (j = i + 1; j < list.length; j++) {
            var a = list[i], b = list[j];
            if (overlaps(a, b)) problems.push("Overlapping world room bounds: " + a.id + " / " + b.id);
            a.doors.forEach(function (da, ai) {
                b.doors.forEach(function (db, bi) {
                    if (OPPOSITE[da.side] !== db.side) return;
                    if (Math.abs(gapOf(a, b, da.side)) >= EPS) return;
                    if (Math.min(da.to, db.to) - Math.max(da.from, db.from) <= EPS) return;
                    var ak = a.id + ":" + (ai + 1), bk = b.id + ":" + (bi + 1);
                    if (used[ak] || used[bk]) { problems.push("Ambiguous world door: " + ak + " / " + bk); return; }
                    used[ak] = used[bk] = true; connections++;
                    neighbors[a.id].push(b.id); neighbors[b.id].push(a.id);
                });
            });
        }
        list.forEach(function (room) {
            room.doors.forEach(function (door, index) {
                if (used[room.id + ":" + (index + 1)]) return;
                problems.push(room.id + ": unmatched " + door.side + " exit " + (index + 1) +
                    "; align an opposing painted opening in Tiled or leave it intentionally disconnected.");
                // A door on a touching edge whose span misses: name it, so the
                // fix is to move cells, not to look for a missing room.
                list.forEach(function (other) {
                    if (other === room) return;
                    if (Math.abs(gapOf(room, other, door.side)) >= EPS) return;
                    other.doors.forEach(function (od, oi) {
                        if (od.side !== OPPOSITE[door.side] || used[other.id + ":" + (oi + 1)]) return;
                        // One line per pair, from the room listed first.
                        if (other.id < room.id) return;
                        var miss = Math.round(Math.max(od.from - door.to, door.from - od.to));
                        problems.push(room.id + ": " + door.side + " exit " + (index + 1) + " touches " + other.id +
                            "'s " + od.side + " exit " + (oi + 1) + ", but their spans " +
                            (miss > 0 ? "miss by " + miss + " px." : "only meet at a corner.") +
                            " Paint both doors on the same cells.");
                    });
                });
            });
        });
        var reached = {}, groups = 0;
        function visit(id) {
            if (reached[id]) return;
            reached[id] = true;
            neighbors[id].forEach(visit);
        }
        list.forEach(function (r) { if (!reached[r.id]) { groups++; visit(r.id); } });
        var notes = [];
        if (groups > 1) notes.push("World has " + groups + " disconnected door groups. Check intended teleporter/elevator routes in play.");
        return { problems: problems, notes: notes, connections: connections };
    }

    // The next free "<world>_NN.tmx" name; taken(baseName) says whether a file
    // or world member already uses it.
    function nextRoomName(worldBase, taken) {
        for (var n = 1; n < 1000; n++) {
            var name = worldBase + "_" + (n < 10 ? "0" + n : String(n)) + ".tmx";
            if (!taken(name)) return name;
        }
        return worldBase + "_new.tmx";
    }

    // The world members Copy Room Properties edits: every room except the
    // source whose file name contains filter (any case; empty matches all),
    // sorted by file name. entries: [{fileName}] with absolute paths.
    function matchRooms(entries, sourceKey, filter, keyOf) {
        var needle = String(filter || "").replace(/^\s+|\s+$/g, "").toLowerCase();
        keyOf = keyOf || function (p) { return p; };
        return entries.filter(function (e) {
            if (keyOf(e.fileName) === sourceKey) return false;
            return baseOf(e.fileName).toLowerCase().indexOf(needle) >= 0;
        }).sort(function (a, b) {
            var x = baseOf(a.fileName).toLowerCase(), y = baseOf(b.fileName).toLowerCase();
            return x < y ? -1 : x > y ? 1 : 0;
        });
    }

    // How a property value reads in the confirmation: enum values
    // (PropertyValue) show their name, file paths their path. Tiled holds an
    // enum value as its index (biome 12), so the project's type names it.
    function describeValue(value) {
        if (value === undefined || value === null) return "(not set)";
        if (typeof value === "object") {
            if (value.typeName && typeof value.value === "number" && typeof tiled !== "undefined" &&
                tiled.project && typeof tiled.project.findTypeByName === "function") {
                var type = tiled.project.findTypeByName(value.typeName);
                if (type && type.isEnum) return String(type.nameOf(value));
            }
            if (value.value !== undefined) return describeValue(value.value);
            if (value.url !== undefined) return String(value.url).replace(/^file:\/\//, "").replace(/^\/([A-Za-z]:)/, "$1");
            if (value.localFile !== undefined) return String(value.localFile);
        }
        return String(value);
    }

    // Every check of Add Connected Room that needs no Tiled object. Throws
    // an Error naming the fix, or returns the plan:
    // {rect, sourceCells, newCells, newStart}.
    // o: {side, width, height (new room, tiles), span, offset,
    //     source: {width, height (tiles), rect (world px)}, tile: {width, height},
    //     ringClosed (the source's ring lies on the map edge and is closed on
    //     this side), embedded (the source has an embedded tileset),
    //     fileName, id, exists, inside, others: [world rects]}
    function plan(o) {
        if (OPPOSITE[o.side] === undefined) throw new Error("Choose a side: right, left, top or bottom.");
        if (o.embedded) throw new Error("This room uses an embedded tileset. Export it as an external tileset (Tileset > Export Tileset As...), then try again.");
        if (!o.ringClosed) throw new Error("This room's bounds ring must be closed and lie on the map edge on the " + o.side +
            " side. Rooms with inset or irregular bounds are not supported: add the room with File > new_room_blank instead.");
        if (!(o.width >= 3 && o.height >= 3) || Math.floor(o.width) !== o.width || Math.floor(o.height) !== o.height)
            throw new Error("The new room needs whole sizes of at least 3 x 3 tiles.");
        if (!ROOM_ID.test(o.id || "")) throw new Error("Room file names use letters, digits, _ and - only, and do not start with -: " + o.id);
        if (o.inside) throw new Error("Choose an authoring folder outside the Defold project. Internal folders hold exported copies and can be cleared by Reset Project.");
        if (o.exists) throw new Error("A file already exists there:\n" + o.fileName);
        var srcLen = horizontalSide(o.side) ? o.source.height : o.source.width;
        var newLen = horizontalSide(o.side) ? o.height : o.width;
        var span = o.span, offset = o.offset;
        if (!(span >= 1) || Math.floor(span) !== span || Math.floor(offset) !== offset)
            throw new Error("The door span and offset are whole numbers of tiles, and the span is at least 1.");
        if (offset < 1 || offset + span > srcLen - 1)
            throw new Error("The door runs past this room's edge: it has " + srcLen + " cells there, and the corners stay part of the ring.");
        if (span > newLen - 2)
            throw new Error("The door runs past the new room's edge: it has " + newLen + " cells there, and the corners stay part of the ring.");
        var newStart = newDoorStart(o.side, srcLen, newLen, offset, span);
        var rect = neighborRect(o.source.rect, o.side, { width: o.width * o.tile.width, height: o.height * o.tile.height },
            offset, newStart, o.tile);
        (o.others || []).forEach(function (other) {
            if (overlaps(rect, other)) throw new Error("The new room would overlap " + (other.id || "another room") +
                " in this world. Choose another side, size or door offset.");
        });
        return {
            rect: rect, newStart: newStart,
            sourceCells: doorCells(o.side, o.source.width, o.source.height, offset, span),
            newCells: doorCells(OPPOSITE[o.side], o.width, o.height, newStart, span)
        };
    }

    // ---------------------------------------------------------------------
    // Tiled helpers
    // ---------------------------------------------------------------------

    function exporter() {
        var api = _g.MVTKMapExport;
        if (!api || !api.root) throw new Error("The toolkit's Tiled extensions did not load. Open MVTK.tiled-project " +
            "(File > Open File or Project...), click Enable Extensions if Tiled asks, and check the Tiled Console for errors in tiled/extensions.");
        return api;
    }
    function normalizePath(path) { return String(path || "").replace(/\\/g, "/"); }
    function key(path) {
        var api = _g.MVTKMapExport;
        return api && api.key ? api.key(path) : normalizePath(path);
    }
    function dirOf(path) { var p = normalizePath(path); return p.slice(0, p.lastIndexOf("/")); }
    function baseOf(path) { var p = normalizePath(path); return p.slice(p.lastIndexOf("/") + 1); }
    function stem(path) { return baseOf(path).replace(/\.[^.]*$/, ""); }

    // setProperty turns a whole number into an int property, so a darkness
    // of 0 or 1 would change type; the copied numbers are all floats.
    function copyProperty(map, name, value) {
        if (typeof value === "number" && typeof map.setFloatProperty === "function") map.setFloatProperty(name, value);
        else map.setProperty(name, value);
    }

    function eachTileLayer(layers, visit) {
        (layers || []).forEach(function (layer) {
            if (layer.isGroupLayer) eachTileLayer(layer.layers, visit);
            else if (layer.isTileLayer) visit(layer);
        });
    }
    function findTileLayer(map, name) {
        var found = null;
        eachTileLayer(map.layers, function (layer) {
            if (!found && normalizeLayerName(layer.name) === name) found = layer;
        });
        return found;
    }
    function paintedCells(layer) {
        var cells = [], x, y;
        if (!layer) return cells;
        for (y = 0; y < layer.height; y++) for (x = 0; x < layer.width; x++) {
            if (layer.tileAt(x, y)) cells.push({ x: x, y: y });
        }
        return cells;
    }
    function tileRef(layer, cell) {
        var tile = layer.tileAt(cell.x, cell.y);
        return { file: tile.tileset.fileName, id: tile.id, flags: layer.flagsAt(cell.x, cell.y) };
    }
    function resolveTile(map, ref) {
        var tilesets = map.tilesets || [], i;
        for (i = 0; i < tilesets.length; i++) {
            if (tilesets[i].fileName && key(tilesets[i].fileName) === key(ref.file)) return tilesets[i].tile(ref.id);
        }
        throw new Error("Tileset not found in " + (map.fileName || "the new room") + ": " + ref.file);
    }
    function paint(map, layer, cells, ref) {
        var tile = resolveTile(map, ref);
        // A layer built before its map had a size could still be empty-sized.
        if (!(layer.width > 0) && typeof layer.resize === "function" && typeof Qt !== "undefined" && Qt.size)
            layer.resize(Qt.size(map.width, map.height), Qt.point(0, 0));
        var edit = layer.edit();
        cells.forEach(function (c) { edit.setTile(c.x, c.y, tile, ref.flags || 0); });
        edit.apply();
    }

    // The ring on the map edge: the bounds box is the whole map, and the
    // side's edge line is painted from corner to corner.
    function ringClosedOn(boundsLayer, width, height, side) {
        var cells = paintedCells(boundsLayer);
        if (!cells.length) return false;
        var room = roomFromCells({ id: "", x: 0, y: 0, tileWidth: 1, tileHeight: 1, bounds: cells });
        if (room.x !== 0 || room.y !== 0 || room.width !== width || room.height !== height) return false;
        var length = horizontalSide(side) ? height : width;
        var edge = doorCells(side, width, height, 0, length);
        return edge.every(function (c) { return !!boundsLayer.tileAt(c.x, c.y); });
    }

    // The door tile for one side: that side's own painted door cell, else any
    // painted door cell (unflipped), else the ring tile (unflipped).
    function doorRef(map, side, ringRef) {
        var own = findTileLayer(map, DOOR_LAYER[side]), cells = paintedCells(own);
        if (cells.length) return tileRef(own, cells[0]);
        var found = null;
        ["left", "right", "up", "down"].forEach(function (s) {
            var layer = findTileLayer(map, DOOR_LAYER[s]), c = paintedCells(layer);
            if (!found && c.length) { found = tileRef(layer, c[0]); found.flags = 0; }
        });
        return found || { file: ringRef.file, id: ringRef.id, flags: 0 };
    }

    function chooseWorld(map) {
        var worlds = tiled.worlds || [];
        var choices = worlds.filter(function (w) { return map && w.containsMap(map); });
        return choices.length ? choices[0] : null;
    }
    function worldOf(title) {
        var active = tiled.activeAsset, worlds = tiled.worlds || [];
        var choices = worlds.filter(function (w) { return active && active.isTileMap && w.containsMap(active); });
        if (!choices.length) choices = worlds;
        if (!choices.length) throw new Error("Open a .world file in Tiled (File > Open File or Project...), then try again.");
        if (choices.length === 1) return choices[0];
        var answer = tiled.prompt("Select the world number:\n" + choices.map(function (w, i) { return (i + 1) + ". " + w.fileName; }).join("\n"), "1", title);
        if (!answer) return null;
        var index = Number(answer) - 1;
        if (!(index >= 0 && index < choices.length && Math.floor(index) === index)) throw new Error("Choose a listed world number.");
        return choices[index];
    }

    // ---------------------------------------------------------------------
    // Add Connected Room...
    // ---------------------------------------------------------------------

    function askOptions(source, existing, worldBase, taken) {
        var dialog = new Dialog("Add Connected Room");
        dialog.newRowMode = Dialog.SingleWidgetRows;
        var sideBox = dialog.addComboBox("Side", SIDE_LABELS, 0, "The edge of this room the new room joins.");
        var widthInput = dialog.addNumberInput("Width (tiles)", source.width, "The new room's width in tiles.");
        var heightInput = dialog.addNumberInput("Height (tiles)", source.height, "The new room's height in tiles.");
        var spanInput = dialog.addNumberInput("Door span (tiles)", 3, "How many cells the door covers.");
        var offsetInput = dialog.addNumberInput("Door offset (tiles)", 1,
            "Where the door starts on this room's edge: rows from the top for right and left, columns from the left for top and bottom.");
        var nameInput = dialog.addTextInput("File name", nextRoomName(worldBase, taken),
            "Saved in this room's folder unless you type a full path.");
        [widthInput, heightInput, spanInput, offsetInput].forEach(function (input) {
            input.decimals = 0; input.minimum = 0; input.maximum = 100000;
        });
        widthInput.value = source.width; heightInput.value = source.height;
        function fillDoor() {
            var side = SIDES[sideBox.currentIndex] || "right";
            var door = existing[side] || defaultDoor(side, horizontalSide(side) ? source.height : source.width);
            spanInput.value = door.span; offsetInput.value = door.offset;
        }
        fillDoor();
        if (sideBox.currentIndexChanged) sideBox.currentIndexChanged.connect(fillDoor);
        // Read the fields while the dialog is open: Tiled (seen on 1.12.2) deletes
        // a closed script dialog's widgets, so reading them after exec() returns
        // gives empty values.
        var answers = null;
        function read() {
            return {
                side: SIDES[sideBox.currentIndex] || "right",
                width: widthInput.value, height: heightInput.value,
                span: spanInput.value, offset: offsetInput.value,
                fileName: String(nameInput.text || "")
            };
        }
        var ok = dialog.addButton("OK"), cancel = dialog.addButton("Cancel");
        ok.clicked.connect(function () { answers = read(); dialog.accept(); });
        cancel.clicked.connect(function () { dialog.reject(); });
        if (dialog.exec() !== Dialog.Accepted) return null;
        return answers || read();
    }

    // answers: the dialog's values (tests and the native step skip the
    // dialog). env (native step only, where --evaluate has no open tabs):
    // {asset, path, world, save(asset), noOpen}.
    function addConnectedRoom(answers, env) {
        env = env || {};
        var api = exporter(), root = api.root();
        var asset = env.asset || tiled.activeAsset;
        var sourcePath = env.path || (asset && asset.fileName);
        if (!asset || !asset.isTileMap || !sourcePath)
            throw new Error("Open a saved room of a world first, then choose File > Add Connected Room... again.");
        var saveAsset = env.save || function (a) { return a.save(); };
        var world = env.world || chooseWorld(asset);
        if (!world) throw new Error("This room is not part of a loaded world. Open the .world file " +
            "(File > Open File or Project...), or start one with File > Start a New World..., then try again.");
        if (world.readOnly) throw new Error("This world is read-only:\n" + world.fileName + "\nMake the .world file writable, then try again.");
        if (!root) throw new Error("Open your toolkit's Tiled project first: File > Open File or Project... and pick MVTK.tiled-project.");
        var builder = _g.MVTKNewRoom;
        if (!builder || !builder.build || !builder.write) throw new Error("The new room builder did not load (tiled/extensions/new_room_blank.js).");

        var entries = world.allMaps(), sourceEntry = null;
        entries.forEach(function (e) { if (key(api.absolute(e.fileName, dirOf(world.fileName))) === key(sourcePath)) sourceEntry = e; });
        if (!sourceEntry) throw new Error("Could not find this room's place in the world:\n" + world.fileName);

        // The tiles, properties and tilesets come from the saved file.
        if (asset.modified && !saveAsset(asset)) throw new Error("Save this room first: saving failed or was canceled.\n" + sourcePath);
        var disk = api.readMap(sourcePath);
        if (disk.error) throw new Error(disk.error);
        var source = disk.map;
        var boundsLayer = findTileLayer(source, "bounds");
        var boundsCells = paintedCells(boundsLayer);
        if (!boundsCells.length) throw new Error("This room's bounds layer is empty. Paint a closed bounds ring first; the new room reuses its tile.");
        var ringRef = tileRef(boundsLayer, boundsCells[0]);

        var existing = {};
        SIDES.forEach(function (side) {
            var runs = doorRuns(side, paintedCells(findTileLayer(source, DOOR_LAYER[side])), { x: 0, y: 0, w: source.width, h: source.height });
            if (!runs.length) return;
            // The lowest door on left and right (doorRuns lists those bottom
            // first), the leftmost on top and bottom.
            var run = runs[0];
            existing[side] = { offset: run.start, span: run.end - run.start + 1 };
        });
        var folder = dirOf(sourcePath), worldBase = stem(world.fileName);
        var members = {};
        entries.forEach(function (e) { members[stem(e.fileName).toLowerCase()] = true; });
        function taken(name) { return members[stem(name).toLowerCase()] || File.exists(folder + "/" + name); }

        var o = answers || askOptions(source, existing, worldBase, taken);
        if (!o) return null;
        var fileName = normalizePath(o.fileName).replace(/^\s+|\s+$/g, "");
        if (!fileName) throw new Error("Type a file name for the new room.");
        if (!/\.tmx$/i.test(fileName)) fileName += ".tmx";
        var path = FileInfo.isAbsolutePath(fileName) ? FileInfo.cleanPath(fileName) : FileInfo.cleanPath(folder + "/" + fileName);
        var id = stem(path);
        var embedded = (source.tilesets || []).some(function (ts) { return !ts.fileName; });
        var others = entries.filter(function (e) { return e !== sourceEntry; }).map(function (e) {
            return { id: stem(e.fileName), x: e.rect.x, y: e.rect.y, width: e.rect.width, height: e.rect.height };
        });
        others.push({ id: stem(sourceEntry.fileName), x: sourceEntry.rect.x, y: sourceEntry.rect.y,
            width: sourceEntry.rect.width, height: sourceEntry.rect.height });
        var p = plan({
            side: o.side, width: o.width, height: o.height, span: o.span, offset: o.offset,
            source: { width: source.width, height: source.height, rect: sourceEntry.rect },
            tile: { width: source.tileWidth, height: source.tileHeight },
            ringClosed: ringClosedOn(boundsLayer, source.width, source.height, o.side),
            embedded: embedded, fileName: path, id: id,
            exists: File.exists(path) || !!members[id.toLowerCase()], inside: api.insideRoot(path, root), others: others
        });

        // 1. The new room, written before anything else changes.
        var room = builder.build(o.width, o.height, source.tileWidth, source.tileHeight);
        (source.tilesets || []).forEach(function (ts) {
            if (!room.addTileset(ts)) throw new Error("Could not add the tileset " + ts.fileName + " to the new room.");
        });
        COPIED_PROPERTIES.forEach(function (name) {
            var value = source.property(name);
            if (value !== undefined) copyProperty(room, name, value);
        });
        paint(room, findTileLayer(room, "bounds"), ringCells(o.width, o.height), ringRef);
        var opposite = OPPOSITE[o.side];
        paint(room, findTileLayer(room, DOOR_LAYER[opposite]), p.newCells, doorRef(source, opposite, ringRef));
        var error = builder.write(room, path);
        if (error) throw new Error("Could not write the new room (nothing else changed):\n" + error);
        var changed = [path];

        try {
            // 2. Matching door cells in this room; its bounds stay untouched.
            var doorLayer = findTileLayer(asset, DOOR_LAYER[o.side]);
            if (!doorLayer) throw new Error("This room has no " + DOOR_LAYER[o.side] + " layer. Add it to the exit group.");
            paint(asset, doorLayer, p.sourceCells, doorRef(source, o.side, ringRef));
            if (!saveAsset(asset)) throw new Error("Saving this room failed or was canceled:\n" + sourcePath);
            changed.push(sourcePath);
            // 3. The world.
            var r = p.rect;
            world.addMap(path, typeof Qt !== "undefined" && Qt.rect ? Qt.rect(r.x, r.y, r.width, r.height) : r);
            if (!world.save()) throw new Error("Saving the world failed:\n" + world.fileName);
            changed.push(world.fileName);
        } catch (e) {
            throw new Error(String(e && e.message ? e.message : e) + "\n\nFiles already changed:\n  " + changed.join("\n  "));
        }

        var warnings = [];
        var solid = findTileLayer(asset, "solid");
        if (solid && p.sourceCells.some(function (c) { return !!solid.tileAt(c.x, c.y); }))
            warnings.push("This room's solid layer covers the new door cells. Erase those solid tiles so the player can pass; art was not changed.");
        var opened = env.noOpen ? null : tiled.open(path);
        if (opened) tiled.activeAsset = opened;
        return { path: path, rect: p.rect, sourceCells: p.sourceCells, newCells: p.newCells, warnings: warnings, changed: changed };
    }

    // ---------------------------------------------------------------------
    // Copy Room Properties to Rooms...
    // ---------------------------------------------------------------------

    function askCopyOptions(sourceName, entries, sourceKey) {
        var dialog = new Dialog("Copy Room Properties to Rooms");
        dialog.newRowMode = Dialog.SingleWidgetRows;
        dialog.addLabel("Copy from " + sourceName + " the properties you tick:");
        var boxes = COPIED_PROPERTIES.map(function (name) {
            return { name: name, box: dialog.addCheckBox(PROPERTY_LABELS[name], false, "Copy this room's " + name + " map property.") };
        });
        var filterInput = dialog.addTextInput("File name contains", "",
            "Rooms of this world whose file names contain this text. Leave it empty for every room.");
        var countLabel = dialog.addLabel("");
        function refresh() {
            var n = matchRooms(entries, sourceKey, filterInput.text, key).length;
            countLabel.text = n + " matching room" + (n === 1 ? "" : "s") + " (listed before anything changes)";
        }
        refresh();
        if (filterInput.textChanged) filterInput.textChanged.connect(refresh);
        // Read the fields while the dialog is open (see askOptions).
        var answers = null;
        function read() {
            return {
                properties: boxes.filter(function (b) { return b.box.checked; }).map(function (b) { return b.name; }),
                filter: String(filterInput.text || "")
            };
        }
        var ok = dialog.addButton("OK"), cancel = dialog.addButton("Cancel");
        ok.clicked.connect(function () { answers = read(); dialog.accept(); });
        cancel.clicked.connect(function () { dialog.reject(); });
        if (dialog.exec() !== Dialog.Accepted) return null;
        return answers || read();
    }

    // answers: {properties: [names], filter} (tests and the native step skip
    // the dialog). env (tests and the native step): {asset, path, world,
    // openAssets, save(asset), confirm(text)}.
    function copyRoomProperties(answers, env) {
        env = env || {};
        var api = exporter();
        var asset = env.asset || tiled.activeAsset;
        var sourcePath = env.path || (asset && asset.fileName);
        if (!asset || !asset.isTileMap || !sourcePath)
            throw new Error("Open a saved room of a world first, then choose File > Copy Room Properties to Rooms... again.");
        var world = env.world || chooseWorld(asset);
        if (!world) throw new Error("This room is not part of a loaded world. Open the .world file " +
            "(File > Open File or Project...), then try again.");
        if (world.readOnly) throw new Error("This world is read-only:\n" + world.fileName + "\nMake the .world file writable, then try again.");
        var worldDir = dirOf(world.fileName), sourceKey = key(sourcePath);
        var entries = world.allMaps().map(function (e) { return { fileName: api.absolute(e.fileName, worldDir) }; });
        var o = answers || askCopyOptions(stem(sourcePath), entries, sourceKey);
        if (!o) return null;
        var names = o.properties || [];
        names.forEach(function (name) {
            if (COPIED_PROPERTIES.indexOf(name) < 0) throw new Error("Copy Room Properties copies only " + COPIED_PROPERTIES.join(", ") + "; not " + name + ".");
        });
        if (!names.length) throw new Error("Tick at least one property to copy.");
        var values = {}, copied = [], notSet = [];
        names.forEach(function (name) {
            var value = asset.property(name);
            if (value === undefined) notSet.push(name); else { values[name] = value; copied.push(name); }
        });
        if (!copied.length) throw new Error("This room has none of the ticked properties set: " + notSet.join(", ") + ".");
        var targets = matchRooms(entries, sourceKey, o.filter, key);
        if (!targets.length) throw new Error("No other room of this world has a file name containing \"" + String(o.filter || "") + "\".");

        var open = {};
        (env.openAssets || tiled.openAssets || []).forEach(function (a) { if (a && a.isTileMap && a.fileName) open[key(a.fileName)] = a; });
        var listed = targets.slice(0, 30).map(function (e) { return "  " + stem(e.fileName) + (open[key(e.fileName)] ? " (open)" : ""); });
        if (targets.length > listed.length) listed.push("  ... and " + (targets.length - listed.length) + " more");
        var unsavedOpen = targets.filter(function (e) { var a = open[key(e.fileName)]; return a && a.modified; });
        var text = ["Copy from " + stem(sourcePath) + ":"].concat(copied.map(function (name) {
            return "  " + PROPERTY_LABELS[name] + " = " + describeValue(values[name]);
        })).concat(notSet.length ? ["Not set on this room, so not copied: " + notSet.join(", ")] : [])
            .concat(["", "to " + targets.length + " room" + (targets.length === 1 ? "" : "s") + ":"]).concat(listed)
            .concat(unsavedOpen.length ? ["", "These open rooms have unsaved edits, which are saved too: " +
                unsavedOpen.map(function (e) { return stem(e.fileName); }).join(", ")] : [])
            .concat(["", "Continue?"]).join("\n");
        var confirm = env.confirm || function (t) { return tiled.confirm(t, "Copy Room Properties to Rooms"); };
        if (!confirm(text)) return null;

        var saveAsset = env.save || function (a) { return a.save(); };
        var changed = [];
        function fail(e) {
            var rest = targets.map(function (t) { return t.fileName; }).filter(function (p) { return changed.indexOf(p) < 0; });
            throw new Error(String(e && e.message ? e.message : e) + "\n\nFiles already changed:\n  " + (changed.length ? changed.join("\n  ") : "(none)") +
                "\n\nNot changed:\n  " + rest.join("\n  "));
        }
        targets.forEach(function (target) {
            var path = target.fileName, a = open[key(path)];
            try {
                if (a) {
                    // An open room is edited through its asset, so its tab and
                    // undo history stay in step, then saved.
                    copied.forEach(function (name) { copyProperty(a, name, values[name]); });
                    if (!saveAsset(a)) throw new Error("Saving " + stem(path) + " failed or was canceled:\n" + path);
                } else {
                    var disk = api.readMap(path);
                    if (disk.error) throw new Error(disk.error);
                    copied.forEach(function (name) { copyProperty(disk.map, name, values[name]); });
                    var format = tiled.mapFormatForFile(path);
                    if (!format || typeof format.write !== "function") throw new Error("Could not find a writable map format for:\n" + path);
                    var error = format.write(disk.map, path);
                    if (typeof error === "string" && error.length) throw new Error("Could not write " + path + ":\n" + error);
                }
            } catch (e) { fail(e); }
            changed.push(path);
        });
        return { changed: changed, properties: copied, notSet: notSet };
    }

    // ---------------------------------------------------------------------
    // Check Door Seams
    // ---------------------------------------------------------------------

    function readRoom(api, entry, worldDir) {
        var path = api.absolute(entry.fileName, worldDir), id = stem(path);
        var disk = api.readMap(path);
        if (disk.error) return { id: id, error: id + ": " + disk.error };
        var map = disk.map, doors = { left: [], right: [], up: [], down: [] }, bounds = [];
        eachTileLayer(map.layers, function (layer) {
            var name = normalizeLayerName(layer.name), side = doorSide(name);
            if (name === "bounds" && !bounds.length) bounds = paintedCells(layer);
            else if (side) doors[side] = doors[side].concat(paintedCells(layer));
        });
        return roomFromCells({ id: id, x: entry.rect.x, y: entry.rect.y, tileWidth: map.tileWidth, tileHeight: map.tileHeight,
            bounds: bounds, doors: doors });
    }

    function checkDoorSeams(world) {
        var api = exporter();
        var worldDir = dirOf(world.fileName), rooms = [], problems = [], unsaved = [];
        world.allMaps().forEach(function (entry) {
            var path = api.absolute(entry.fileName, worldDir);
            (tiled.openAssets || []).forEach(function (a) { if (a.modified && key(a.fileName || "") === key(path)) unsaved.push(stem(path)); });
            var room = readRoom(api, entry, worldDir);
            if (room.error) problems.push(room.error); else rooms.push(room);
        });
        var report = seamReport(rooms);
        problems = problems.concat(report.problems);
        return { rooms: rooms.length, problems: problems,
            notes: report.notes, connections: report.connections, unsaved: unsaved };
    }

    function run(title, body) {
        try { body(); } catch (e) {
            var message = String(e && e.message ? e.message : e);
            tiled.log("[MVTK] " + title + ": " + message);
            tiled.alert(message, title);
        }
    }

    var addAction = tiled.registerAction("MVTK.AddConnectedRoom", function () {
        run("Add Connected Room", function () {
            var made = addConnectedRoom(_g.__mvtkAddConnectedRoomAnswers || null);
            if (!made) return;
            tiled.log("[MVTK] Add Connected Room: " + made.path);
            made.warnings.forEach(function (w) { tiled.log("[MVTK] Add Connected Room: " + w); });
            if (!_g.__mvtkWorldRoomsQuiet) tiled.alert("Created the room:\n  " + made.path +
                "\nand painted matching door cells in both rooms.\n\n" +
                (made.warnings.length ? made.warnings.join("\n") + "\n\n" : "") +
                "Paint its art, floor and solid layers, then use File > Export All Maps and Tiled World.", "Add Connected Room");
        });
    });
    addAction.text = "Add Connected Room...";

    var checkAction = tiled.registerAction("MVTK.CheckDoorSeams", function () {
        run("Check Door Seams", function () {
            var world = worldOf("Check Door Seams");
            if (!world) return;
            var result = checkDoorSeams(world);
            _g.__mvtkLastDoorSeamReport = result;
            result.problems.concat(result.notes).forEach(function (line) { tiled.log("[MVTK] Door seams: " + line); });
            var head = result.problems.length
                ? result.problems.length + " door seam problem" + (result.problems.length === 1 ? "" : "s") + " in " + world.fileName + ":"
                : "No door seam problems in " + world.fileName + " (" + result.connections + " connected doors).";
            var shown = result.problems.slice(0, 12);
            if (result.problems.length > shown.length) shown.push("... and " + (result.problems.length - shown.length) + " more in the Console.");
            var tail = result.notes.concat(result.unsaved.length
                ? ["Unsaved rooms were checked as last saved: " + result.unsaved.join(", ")] : []);
            tiled.log("[MVTK] " + head);
            if (!_g.__mvtkWorldRoomsQuiet) tiled.alert([head].concat(shown).concat(tail.length ? [""].concat(tail) : []).join("\n"), "Check Door Seams");
        });
    });
    checkAction.text = "Check Door Seams";

    var copyAction = tiled.registerAction("MVTK.CopyRoomProperties", function () {
        run("Copy Room Properties to Rooms", function () {
            var done = copyRoomProperties(_g.__mvtkCopyRoomPropertiesAnswers || null);
            if (!done) return;
            done.changed.forEach(function (p) { tiled.log("[MVTK] Copy Room Properties: " + p); });
            if (!_g.__mvtkWorldRoomsQuiet) tiled.alert("Copied " + done.properties.join(", ") + " to " + done.changed.length + " room" +
                (done.changed.length === 1 ? "" : "s") + ".\n\nExport them again (File > Export All Maps and Tiled World) so Defold sees the change.",
                "Copy Room Properties to Rooms");
        });
    });
    copyAction.text = "Copy Room Properties to Rooms...";

    // Re-registering replaces the QAction and removes its old menu entry, so
    // attach the replacements too. --evaluate has no menus.
    if (tiled.menus.indexOf("File") >= 0) tiled.extendMenu("File", [
        { action: "MVTK.AddConnectedRoom" },
        { action: "MVTK.CopyRoomProperties" },
        { action: "MVTK.CheckDoorSeams" }
    ]);

    // Published last, so a copy whose registration failed can be retried.
    _g.MVTKWorldRooms = {
        version: version,
        neighborRect: neighborRect,
        doorCells: doorCells,
        ringCells: ringCells,
        overlaps: overlaps,
        seamReport: seamReport,
        roomFromCells: roomFromCells,
        defaultDoor: defaultDoor,
        newDoorStart: newDoorStart,
        nextRoomName: nextRoomName,
        doorSide: doorSide,
        plan: plan,
        matchRooms: matchRooms,
        describeValue: describeValue,
        addConnectedRoom: addConnectedRoom,
        copyRoomProperties: copyRoomProperties,
        checkDoorSeams: checkDoorSeams
    };
    Object.defineProperty(_g.MVTKWorldRooms, "fromProject", { value: isProjectCopy });
    if (typeof tiled !== "undefined" && typeof tiled.log === "function")
        tiled.log("[MVTK] world_rooms.js loaded from the " + (isProjectCopy ? "project" : "global") + " copy");
})();
