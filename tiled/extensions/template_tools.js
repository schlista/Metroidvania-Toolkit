/* Saved-XML template helpers and the creator preset command. Tiled has no
 * template scripting API, so template identity comes from the saved TMX.
 */
(function () {
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
    var version = 3;
    if (keepExisting(_g.MVTKTemplateTools, _g.MVTKTemplateTools && _g.MVTKTemplateTools.version >= version)) {
        if (typeof module !== "undefined" && module.exports) module.exports = _g.MVTKTemplateTools;
        return;
    }

    // Keep entity order identical to the exporter's decodeXmlAttribute.
    function decodeXmlAttribute(value) {
        return String(value || "")
            .replace(/&#x([0-9a-f]+);/gi, function (_, n) {
                return String.fromCharCode(parseInt(n, 16));
            })
            .replace(/&#([0-9]+);/g, function (_, n) {
                return String.fromCharCode(parseInt(n, 10));
            })
            .replace(/&quot;/g, '"')
            .replace(/&apos;/g, "'")
            .replace(/&lt;/g, "<")
            .replace(/&gt;/g, ">")
            .replace(/&amp;/g, "&");
    }
    function encodeXmlAttribute(value, quote) {
        var encoded = String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
            .replace(/\n/g, "&#10;").replace(/\r/g, "&#13;").replace(/\t/g, "&#9;");
        return quote === '"' ? encoded.replace(/"/g, "&quot;") : encoded.replace(/'/g, "&apos;");
    }
    function withoutComments(text) {
        // Same comment exclusion as templateReferences, but retain original offsets.
        return String(text || "").replace(/<!--[\s\S]*?-->/g, function (comment) {
            return comment.replace(/[\s\S]/g, " ");
        });
    }
    function tags(name) {
        // A quoted '>' belongs to its attribute, not the end of the tag.
        return new RegExp("<" + name + "(?=[\\s/>])(?:[^>\"']|\"[^\"]*\"|'[^']*')*>", "g");
    }
    function attributes(tag) {
        var result = [], match, pattern = /([^\s=<>\/]+)\s*=\s*(["'])([\s\S]*?)\2/g;
        while ((match = pattern.exec(tag)) !== null) {
            result.push({name: match[1], quote: match[2], value: decodeXmlAttribute(match[3]),
                index: match.index + match[0].length - match[3].length - 1, length: match[3].length});
        }
        return result;
    }
    function attribute(tag, name) {
        var attrs = attributes(tag), i;
        for (i = 0; i < attrs.length; i++) if (attrs[i].name === name) return attrs[i].value;
        return "";
    }
    // index/length span the encoded value only, excluding its quote characters.
    // Duplicate references are intentional: each occurrence can be rewritten.
    function templateRefs(xmlText) {
        var refs = [], match, pattern = tags("object");
        var text = withoutComments(xmlText);
        while ((match = pattern.exec(text)) !== null) {
            attributes(match[0]).forEach(function (attr) {
                if (attr.name === "template") refs.push({index: match.index + attr.index,
                    length: attr.length, quote: attr.quote, value: attr.value});
            });
        }
        return refs;
    }
    function templateInfo(txText) {
        var text = withoutComments(txText), object = tags("object").exec(text);
        var info = {type: object ? (attribute(object[0], "type") || attribute(object[0], "class")) : "",
            name: object ? attribute(object[0], "name") : "", presetOf: "", version: "", hasTileset: tags("tileset").test(text)};
        var pattern = tags("property"), match;
        while ((match = pattern.exec(text)) !== null) {
            var name = attribute(match[0], "name");
            if (name === "mvtk_preset_of") info.presetOf = attribute(match[0], "value");
            if (name === "mvtk_template_version") info.version = attribute(match[0], "value");
        }
        return info;
    }

    function cleanPath(path) {
        var text = String(path || "").replace(/\\/g, "/");
        var root = /^(?:[A-Za-z]:\/|\/\/[^/]+\/[^/]+\/?|\/)/.exec(text);
        var prefix = root ? root[0].replace(/\/?$/, "/") : "", parts = [];
        text.slice(root ? root[0].length : 0).split("/").forEach(function (part) {
            if (!part || part === ".") return;
            if (part === ".." && parts.length && parts[parts.length - 1] !== "..") parts.pop();
            else if (part !== ".." || !prefix) parts.push(part);
        });
        return prefix + parts.join("/");
    }

    // Read one-level class values from saved template XML. No template API is
    // exposed by Tiled. Keep metadata as well as values for structural checks.
    function templateProperties(txText) {
        var text = withoutComments(txText), roots = Object.create(null), stack = [], match;
        var pattern = /<property(?=[\s/>])(?:[^>"']|"[^"]*"|'[^']*')*>|<\/property\s*>/g;
        while ((match = pattern.exec(text)) !== null) {
            if (/^<\//.test(match[0])) { stack.pop(); continue; }
            var tag = match[0], type = attribute(tag, "type") || "string";
            var raw = attribute(tag, "value");
            if (!attributes(tag).some(function (a) { return a.name === "value"; }) && type !== "class") {
                var end = text.indexOf("</property", pattern.lastIndex);
                if (end >= 0 && !/\/\s*>$/.test(tag)) {
                    raw = text.slice(pattern.lastIndex, end);
                    var cdata = /^<!\[CDATA\[([\s\S]*?)\]\]>$/.exec(raw);
                    raw = cdata ? cdata[1] : decodeXmlAttribute(raw);
                }
            }
            var value = type === "bool" ? raw === "true" :
                (/^(int|float|object)$/.test(type) ? Number(raw) : raw);
            var p = {name: attribute(tag, "name"), type: type,
                className: attribute(tag, "propertytype"), value: value, members: Object.create(null)};
            var parent = stack.length ? stack[stack.length - 1].members : roots;
            parent[p.name] = p;
            if (!/\/\s*>$/.test(tag)) stack.push(p);
        }
        return roots;
    }

    function presetProblems(presetText, baseText) {
        var out = [], info = templateInfo(presetText), base = templateInfo(baseText);
        function issue(severity, code, message) { out.push({severity: severity, code: code, message: message}); }
        if (!baseText) {
            issue("error", "preset_unknown_base", "Unknown base '" + info.presetOf + "'. Choose a toolkit base and save the preset again.");
            return out;
        }
        if (info.type !== base.type) issue("error", "preset_type_mismatch", "Preset type differs from its base. Save the preset again from a placed " + base.name + ".");
        var properties = templateProperties(presetText), defaults = templateProperties(baseText), missing = [];
        Object.keys(properties).forEach(function (name) {
            if (name === "mvtk_preset_of") return;
            var p = properties[name], b = defaults[name];
            if (!b) {
                issue("error", p.type === "class" ? "preset_unknown_group" : "preset_unknown_property",
                    "Property '" + name + "' is not in the base. Remove it and save the preset again.");
                return;
            }
            if (p.type !== b.type || p.className !== b.className) issue("error", "preset_property_type_mismatch",
                "Property '" + name + "' has a different type from the base. Save the preset again.");
            Object.keys(p.members).forEach(function (member) {
                var m = p.members[member], bm = b.members[member];
                if (m.type === "class" || Object.keys(m.members).length) issue("error", "preset_nested_class",
                    "Nested class '" + name + "." + member + "' is unsupported. Keep only the base's one-level groups and save the preset again.");
                if (!bm) issue("error", "preset_unknown_member", "Member '" + name + "." + member + "' is not in the base. Remove it and save the preset again.");
                else if (m.type !== bm.type || m.className !== bm.className) issue("error", "preset_property_type_mismatch",
                    "Member '" + name + "." + member + "' has a different type from the base. Save the preset again.");
            });
        });
        Object.keys(defaults).forEach(function (name) {
            var p = properties[name], b = defaults[name];
            if (!p) missing.push(name);
            else Object.keys(b.members).forEach(function (member) {
                if (!Object.prototype.hasOwnProperty.call(p.members, member)) missing.push(name + "." + member);
            });
        });
        if (missing.length) issue("warning", "preset_missing_members", "Base members are missing (" + missing.join(", ") + "); save the preset again.");
        if (info.version !== base.version) issue("warning", "preset_base_changed", "Base version differs; save the preset again.");
        return out;
    }

    function objectTemplates(tmxText) {
        var result = {}, match, pattern = tags("object"), text = withoutComments(tmxText);
        while ((match = pattern.exec(text)) !== null) {
            var ref = attribute(match[0], "template");
            if (ref) result[attribute(match[0], "id")] = ref;
        }
        return result;
    }

    // Only own class overrides need repair. Use fresh dictionaries so neither
    // the original PropertyValue nor its detached own-property snapshot changes.
    function fillPreset(object, presetText, usage, propertyValue) {
        var own = object.properties(), groups = templateProperties(presetText);
        Object.keys(own).forEach(function (name) {
            var p = groups[name], instance = own[name];
            if (!p || p.type !== "class" || !instance || !instance.value || typeof instance.value !== "object") return;
            var merged = {};
            Object.keys(p.members).forEach(function (member) { merged[member] = p.members[member].value; });
            Object.keys(instance.value).forEach(function (member) { merged[member] = instance.value[member]; });
            object.setProperty(name, propertyValue(p.className, merged));
        });
        object.setProperty("mvtk_preset", usage);
    }
    function windowsPath(path) { return /^[A-Za-z]:\//.test(path); }
    function pathKey(path) {
        var cleaned = cleanPath(path).replace(/\/+$/, "");
        return windowsPath(cleaned) ? cleaned.toLowerCase() : cleaned;
    }
    function basename(path) { return path.slice(path.lastIndexOf("/") + 1); }
    function templateSuffix(path) {
        var marker = "/tiled/templates/", key = windowsPath(path) ? path.toLowerCase() : path;
        var index = key.lastIndexOf(marker);
        return index < 0 ? "" : path.slice(index + marker.length);
    }
    // Index entries hold metadata plus path (full path) and relativePath (below
    // tiled/templates). Missing originals may use only this relative path match.
    function retargetTarget(externalPath, externalInfo, toolkitIndex) {
        if (externalInfo && externalInfo.presetOf) return {skip: true, reason: "preset"};
        var source = cleanPath(externalPath), suffix = templateSuffix(source), candidates = [];
        function same(a, b, entry) {
            var fold = windowsPath(source) || windowsPath(entry.path);
            return fold ? a.toLowerCase() === b.toLowerCase() : a === b;
        }
        if (suffix) candidates = toolkitIndex.filter(function (entry) {
            return same(suffix, entry.relativePath, entry);
        });
        var reason = "path match";
        if (!candidates.length && externalInfo) {
            reason = "basename match";
            candidates = toolkitIndex.filter(function (entry) {
                return same(basename(source), basename(cleanPath(entry.path)), entry);
            });
        }
        if (!candidates.length) return {skip: true, reason: externalInfo ? "no match" : "missing original; no path match"};
        if (candidates.length !== 1) return {skip: true, reason: "ambiguous " + reason};
        var candidate = candidates[0];
        if (externalInfo && externalInfo.type !== candidate.type) return {skip: true, reason: "type mismatch"};
        return {target: candidate.path, reason: externalInfo ? reason : "missing original"};
    }
    function relativeRef(fromDir, toPath) {
        var from = cleanPath(fromDir), to = cleanPath(toPath);
        var fromRoot = /^(?:[A-Za-z]:\/|\/\/[^/]+\/[^/]+\/?|\/)/.exec(from);
        var toRoot = /^(?:[A-Za-z]:\/|\/\/[^/]+\/[^/]+\/?|\/)/.exec(to);
        var fold = windowsPath(from) && windowsPath(to);
        function key(value) { return fold ? value.toLowerCase() : value; }
        if (key(fromRoot ? fromRoot[0] : "") !== key(toRoot ? toRoot[0] : "")) return to;
        var a = from.slice(fromRoot ? fromRoot[0].length : 0).split("/").filter(Boolean);
        var b = to.slice(toRoot ? toRoot[0].length : 0).split("/").filter(Boolean);
        var i = 0, relative = [];
        while (i < a.length && i < b.length && key(a[i]) === key(b[i])) i++;
        for (var j = i; j < a.length; j++) relative.push("..");
        return relative.concat(b.slice(i)).join("/") || ".";
    }
    // mapping is a dictionary: decoded old reference -> new reference. Only
    // value spans change; comments, whitespace and unrelated XML stay byte-equal.
    function rewriteRefs(xmlText, mapping) {
        var replacements = Object.create(null), count = 0, cursor = 0, parts = [];
        Object.keys(mapping).forEach(function (old) { replacements[pathKey(old)] = mapping[old]; });
        templateRefs(xmlText).forEach(function (ref) {
            var key = pathKey(ref.value);
            if (!Object.prototype.hasOwnProperty.call(replacements, key) || replacements[key] === ref.value) return;
            parts.push(xmlText.slice(cursor, ref.index), encodeXmlAttribute(replacements[key], ref.quote));
            cursor = ref.index + ref.length;
            count++;
        });
        parts.push(xmlText.slice(cursor));
        return {text: parts.join(""), count: count};
    }
    function toolkitIndex(root) {
        var base = cleanPath(root + "/tiled/templates"), result = [];
        function visit(dir) {
            File.directoryEntries(dir, File.Files | File.NoDotAndDotDot | File.NoSymLinks).forEach(function (name) {
                if (!/\.tx$/i.test(name)) return;
                var path = dir + "/" + name, file = new TextFile(path, TextFile.ReadOnly), info;
                try { info = templateInfo(file.readAll()); }
                finally { file.close(); }
                info.path = path;
                info.relativePath = path.slice(base.length + 1);
                result.push(info);
            });
            File.directoryEntries(dir, File.Dirs | File.NoDotAndDotDot | File.NoSymLinks).forEach(function (name) {
                visit(dir + "/" + name);
            });
        }
        visit(base);
        return result;
    }

    function own(object, name) { return Object.prototype.hasOwnProperty.call(object, name); }
    function absolute(path, dir) {
        return cleanPath(/^(?:[A-Za-z]:[\\/]|\/)/.test(path) ? path : dir + "/" + path);
    }
    function dirname(path) { return path.slice(0, path.lastIndexOf("/")); }
    function within(path, folder) {
        var p = pathKey(path), f = pathKey(folder);
        return p === f || p.indexOf(f + "/") === 0;
    }
    function presetValues(object) {
        function plain(value, property) {
            if (!value || typeof value !== "object") return value;
            if (value.localFile !== undefined) {
                if (!value.localFile && String(value.url || "")) throw new Error("File property '" + property + "' must use a local file. Choose an original on disk and save again.");
                return String(value.localFile);
            }
            if (value.typeName && typeof value.value === "number") {
                var type = tiled.project && tiled.project.findTypeByName(value.typeName);
                if (!type || !type.isEnum) throw new Error("Unknown enum '" + value.typeName + "'. Open MVTK.tiled-project and save again.");
                return type.nameOf(value);
            }
            // References are reset by the builder; do not traverse a MapObject.
            if (typeof value.resolvedProperties === "function") return 0;
            var source = value.typeName ? value.value : value, result = Object.create(null);
            Object.keys(source).forEach(function (name) { result[name] = plain(source[name], property ? property + "." + name : name); });
            return result;
        }
        return plain(object.resolvedProperties());
    }

    // Preserve base spelling/ordering when a value is equal (e.g. float 2.0).
    // Only leaf values and dimensions change; shapes and class structure stay.
    function buildPresetText(baseText, resolvedValues, opts) {
        opts = opts || {};
        var text = String(baseText).replace(/^\uFEFF/, "").replace(/\r\n?/g, "\n");
        var defaults = templateProperties(text), values = resolvedValues || {}, stack = [], edits = [], scanned = withoutComments(text);
        var pattern = /<property(?=[\s/>])(?:[^>"']|"[^"]*"|'[^']*')*>|<\/property\s*>/g, match;
        while ((match = pattern.exec(scanned)) !== null) {
            var tag = match[0];
            if (/^<\//.test(tag)) { stack.pop(); continue; }
            var name = attribute(tag, "name"), parent = stack.length ? stack[0] : null;
            var p = parent ? defaults[parent].members[name] : defaults[name];
            if (stack.length > 1 || (parent && p.type === "class"))
                throw new Error("Nested class '" + (parent ? parent + "." : "") + name + "' is unsupported. Use one-level base groups.");
            if (p.type === "class") { if (!/\/\s*>$/.test(tag)) stack.push(name); continue; }
            var group = parent && values[parent], hasValue = parent ? group && own(group, name) : own(values, name);
            var value = hasValue ? (parent ? group[name] : values[name]) : p.value;
            if (p.type === "object") value = 0;
            if ((!parent && /_id$/.test(name) && p.type === "string") || name === "mvtk_template_version") value = p.value;
            if (p.type === "file" && value) {
                var source = absolute(String(value), hasValue ? opts.mapDir : opts.baseDir);
                if (opts.validateFile) opts.validateFile(parent ? parent + "." + name : name, source);
                value = relativeRef(opts.presetDir, source);
            }
            var end = pattern.lastIndex;
            if (!/\/\s*>$/.test(tag)) end = text.indexOf("</property", end) + "</property>".length;
            if (value !== p.value) {
                var replacement = tag;
                if (attributes(tag).some(function (a) { return a.name === "value"; })) {
                    replacement = tag.replace(/(\bvalue\s*=\s*)(["'])([\s\S]*?)\2/, function (_, prefix, quote) {
                        return prefix + quote + encodeXmlAttribute(value, quote) + quote;
                    }).replace(/\s*\/?>$/, "/>");
                } else replacement = tag.replace(/\s*\/?>$/, ' value="' + encodeXmlAttribute(value, '"') + '"/>');
                edits.push({start: match.index, end: end, text: replacement});
            }
            if (!/\/\s*>$/.test(tag)) pattern.lastIndex = end;
            if (!parent && name === "mvtk_template_version") {
                var indent = /(?:^|\n)([ \t]*)$/.exec(text.slice(0, match.index));
                edits.push({start: match.index, end: match.index, text: '<property name="mvtk_preset_of" value="' +
                    encodeXmlAttribute(opts.baseId, '"') + '"/>\n' + (indent ? indent[1] : "")});
            }
        }
        edits.sort(function (a, b) { return b.start - a.start || b.end - a.end; }).forEach(function (edit) {
            text = text.slice(0, edit.start) + edit.text + text.slice(edit.end);
        });
        return text.replace(tags("object"), function (tag) {
            ["width", "height"].forEach(function (name) {
                if (opts[name] === undefined) return;
                var attr = new RegExp('\\b' + name + '\\s*=\\s*(["\'])(.*?)\\1');
                if (attr.test(tag)) tag = tag.replace(attr, name + '="' + opts[name] + '"');
                else tag = tag.replace(/\s*\/?>$/, ' ' + name + '="' + opts[name] + '">');
            });
            return tag;
        });
    }

    function askPreset(name, folder, update) {
        var dialog = new Dialog(update ? "Update preset " + name : "Save as Template Preset...");
        var nameInput = dialog.addTextInput("Name", name, "Use lower-case letters, digits and underscores; start with a letter or digit.");
        var folderInput = dialog.addTextInput("Folder", folder, "Keep presets with your originals, outside the toolkit.");
        // Read the fields while the dialog is open: Tiled (seen on 1.12.2) deletes
        // a closed script dialog's widgets, so reading them after exec() returns
        // gives empty values.
        var answers = null;
        function read() { return {name: String(nameInput.text || ""), folder: String(folderInput.text || "")}; }
        var ok = dialog.addButton("OK"), cancel = dialog.addButton("Cancel");
        ok.clicked.connect(function () { answers = read(); dialog.done(Dialog.Accepted); });
        cancel.clicked.connect(function () { dialog.done(Dialog.Rejected); });
        if (dialog.exec() !== Dialog.Accepted) return null;
        return answers || read();
    }
    function savePreset(answers) {
        var map = answers && answers.map || tiled.activeAsset;
        if (!map || !map.isTileMap) throw new Error("Open a room map, select one template object and try again.");
        // An open map names its file. A map read from disk by the TMX format
        // (native tests) reports an empty fileName, so the hook may name it.
        var mapPath = String(map.fileName || (answers && answers.mapPath) || "");
        if (!mapPath) throw new Error("Save the room as a TMX map before saving a template preset.");
        // Only a map open in the editor has a selection; for a disk-read map
        // (native tests) the hook names the object instead.
        var selected = answers && answers.object ? [answers.object] : (map.selectedObjects || []);
        if (selected.length !== 1) throw new Error("Select exactly one template object and try again.");
        var object = selected[0], layer = object.layer;
        if (!layer || !layer.isObjectLayer || layer.name !== "templates" || layer.parentLayer)
            throw new Error("Move the object to the top-level templates object layer and try again.");
        if (object.tile) throw new Error("Tile objects cannot be saved as presets. Select a toolkit rectangle, point or ellipse template instead.");
        var exporter = _g.MVTKMapExport;
        if (!exporter || !exporter.root) throw new Error("Open MVTK.tiled-project and restart Tiled to load the toolkit extensions.");
        var root = exporter.root(), mapDir = dirname(cleanPath(mapPath));
        var ref = objectTemplates(exporter.read(mapPath))[object.id];
        if (!ref) throw new Error("No template for this object in the saved TMX. Save the room; if needed, place a toolkit template and try again.");
        var source = absolute(ref, mapDir), sourceText = exporter.read(source), info = templateInfo(sourceText);
        var templates = cleanPath(root + "/tiled/templates"), baseId;
        if (info.presetOf) baseId = info.presetOf;
        else if (within(source, templates)) baseId = source.slice(templates.length + 1).replace(/\.tx$/i, "");
        else throw new Error("This template is outside the toolkit's tiled/templates and is not a preset. Place a template from this toolkit and try again.");
        if (!/^[a-z0-9_]+(?:\/[a-z0-9_]+)*$/.test(baseId))
            throw new Error("Unknown preset base '" + baseId + "'. Place its toolkit base and save the preset again.");
        var basePath = templates + "/" + baseId + ".tx";
        if (!exporter.exists(basePath)) throw new Error("Unknown preset base '" + baseId + "'. Restore its toolkit template and save again.");
        var baseText = exporter.read(basePath), baseInfo = templateInfo(baseText);
        if (info.hasTileset || baseInfo.hasTileset || attribute((tags("object").exec(withoutComments(baseText)) || [""])[0], "gid"))
            throw new Error("Tile templates cannot be saved as presets. Select a toolkit rectangle, point or ellipse template instead.");
        var name = info.presetOf ? basename(source).replace(/\.tx$/i, "") : "";
        var folder = info.presetOf ? dirname(source) : mapDir + "/presets";
        answers = answers || askPreset(name, folder, !!info.presetOf);
        if (!answers) return null;
        name = answers.name === undefined ? name : String(answers.name);
        folder = answers.folder === undefined ? folder : String(answers.folder);
        if (!/^[a-z0-9][a-z0-9_]*$/.test(name)) throw new Error("Invalid preset name. Use lower-case letters, digits and underscores, starting with a letter or digit.");
        if (!folder.trim()) throw new Error("Choose a preset folder outside the toolkit and try again.");
        folder = absolute(folder, mapDir);
        var target = folder + "/" + name + ".tx";
        if (exporter.insideRoot(target, root)) throw new Error("Choose a preset folder outside the toolkit, including outside tiled/templates. Internal files can be replaced or cleared.");
        var values = presetValues(object);
        if (info.presetOf) {
            // Tiled resolves an owned partial class without its template members.
            // Fill from the source preset without changing the selected object.
            var inherited = templateProperties(sourceText);
            function inheritedValue(p) {
                return p.type === "file" && p.value ? absolute(p.value, dirname(source)) : p.value;
            }
            Object.keys(inherited).forEach(function (name) {
                var p = inherited[name];
                if (p.type === "class") {
                    var merged = Object.create(null), selectedGroup = values[name] || {};
                    Object.keys(p.members).forEach(function (member) { merged[member] = inheritedValue(p.members[member]); });
                    Object.keys(selectedGroup).forEach(function (member) { merged[member] = selectedGroup[member]; });
                    values[name] = merged;
                } else if (!own(values, name)) values[name] = inheritedValue(p);
            });
        }
        var text = buildPresetText(baseText, values, {baseId: baseId, width: object.width, height: object.height,
            baseDir: dirname(basePath), mapDir: mapDir, presetDir: folder, validateFile: function (property, path) {
                var skin = basename(dirname(path)).toLowerCase().replace(/[\s-]+/g, "_").replace(/[^a-z0-9_]/g, "").replace(/_+/g, "_").replace(/^_+|_+$/g, "");
                if (baseInfo.type !== "enemy" || property !== "art" || exporter.insideRoot(path, root) ||
                    !exporter.exists(path) || !/^[a-z0-9_]+_[0-9]+\.png$/i.test(basename(path)) || !skin || skin === "none")
                    throw new Error("File property '" + property + "' cannot be imported. Choose an existing Enemy art <state>_<NN>.png in an original skin folder outside the toolkit, or clear this property.");
            }});
        if (exporter.exists(target) && !tiled.confirm("Overwrite the existing preset?\n" + target, "Update preset " + name)) return null;
        exporter.mkdir(folder);
        // TextFile uses QIODevice::Text on Windows. BinaryFile preserves LF.
        var utf8 = unescape(encodeURIComponent(text)), bytes = new Uint8Array(utf8.length);
        for (var i = 0; i < utf8.length; i++) bytes[i] = utf8.charCodeAt(i);
        var file = new BinaryFile(target, BinaryFile.WriteOnly);
        try { file.write(bytes.buffer); }
        catch (writeError) { file.close(); throw writeError; }
        file.commit();
        var listed = tiled.project && tiled.project.folders.some(function (path) {
            return within(target, absolute(path, dirname(projectPath)));
        });
        return {path: target, message: "Saved template preset:\n" + target + "\nPlace it on the top-level templates layer." +
            (listed ? "" : "\nChoose Project > Add Folder to Project... to show this folder in the Project view.")};
    }

    var api = {version: version, templateRefs: templateRefs, templateInfo: templateInfo,
        retargetTarget: retargetTarget, relativeRef: relativeRef, rewriteRefs: rewriteRefs, toolkitIndex: toolkitIndex,
        presetProblems: presetProblems, templateProperties: templateProperties, objectTemplates: objectTemplates, fillPreset: fillPreset,
        buildPresetText: buildPresetText, presetValues: presetValues, savePreset: savePreset};
    Object.defineProperty(api, "fromProject", {value: isProjectCopy});
    if (typeof tiled !== "undefined" && typeof tiled.registerAction === "function") {
        var action = tiled.registerAction("MVTK.SaveAsTemplatePreset", function () {
            _g.__mvtkLastPresetError = "";
            _g.__mvtkLastPresetResult = null;
            try {
                var result = savePreset(_g.__mvtkPresetAnswers || null);
                _g.__mvtkLastPresetResult = result;
                if (result && !(_g.__mvtkPresetAnswers && _g.__mvtkPresetAnswers.quiet)) tiled.alert(result.message, "Save as Template Preset...");
            } catch (error) {
                _g.__mvtkLastPresetError = String(error && error.message || error);
                if (!(_g.__mvtkPresetAnswers && _g.__mvtkPresetAnswers.quiet)) tiled.alert(_g.__mvtkLastPresetError, "Save as Template Preset...");
            }
        });
        action.text = "Save as Template Preset...";
        ["MapView.Objects", "File"].forEach(function (menu) {
            if (tiled.menus.indexOf(menu) >= 0) tiled.extendMenu(menu, [{action: "MVTK.SaveAsTemplatePreset"}]);
        });
    }
    if (typeof tiled !== "undefined" && typeof tiled.log === "function")
        tiled.log("[MVTK] template_tools.js loaded from the " + (isProjectCopy ? "project" : "global") + " copy");
    if (typeof module !== "undefined" && module.exports) module.exports = api;
    // Publish last so incomplete initialization can be retried. No legacy alias.
    _g.MVTKTemplateTools = api;
})();
