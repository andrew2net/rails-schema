(function() {
  "use strict";

  var data = window.__SCHEMA_DATA__;
  var config = window.__SCHEMA_CONFIG__ || {};
  var nodes = data.nodes;
  var edges = data.edges;

  // Hide legend items that don't apply to the current schema mode
  var mode = data.metadata && data.metadata.mode;
  if (mode) {
    var hideMode = mode === "mongoid" ? "active_record" : "mongoid";
    document.querySelectorAll('.legend-item[data-mode="' + hideMode + '"]').forEach(function(el) {
      el.style.display = "none";
    });
  }

  // State
  var selectedNode = null;
  var visibleModels = new Set(nodes.map(function(n) { return n.id; }));
  var simulation;
  var zoomTransform = d3.zoomIdentity;
  var NODE_WIDTH = 180;
  var NODE_HEADER_HEIGHT = 36;
  var NODE_COLUMN_HEIGHT = 18;
  var NODE_PADDING = 8;

  // Bezier curve tuning for edge routing
  var MIN_LOOP_OFFSET = 60;      // Minimum control-point distance for same-side (loop) edges
  var LOOP_OFFSET_RATIO = 0.5;   // Proportion of vertical gap used for loop curve spread
  var MIN_CURVE_OFFSET = 50;     // Minimum control-point distance for opposite-side edges
  var CURVE_OFFSET_RATIO = 0.4;  // Proportion of horizontal gap used for curve spread

  // Setup SVG
  var svgEl = document.getElementById("schema-svg");
  var svg = d3.select(svgEl);
  var defs = svg.append("defs");
  var container = svg.append("g").attr("class", "zoom-container");
  var edgeGroup = container.append("g").attr("class", "edges");
  var nodeGroup = container.append("g").attr("class", "nodes");

  // Marker definitions for crow's foot notation
  var MARKER_TYPES = {
    belongs_to: "--edge-belongs-to",
    has_many: "--edge-has-many",
    has_one: "--edge-has-one",
    has_and_belongs_to_many: "--edge-habtm",
    embeds_many: "--edge-embeds-many",
    embeds_one: "--edge-embeds-one",
    embedded_in: "--edge-embedded-in"
  };

  function buildMarkers() {
    defs.selectAll("marker").remove();
    var cs = getComputedStyle(document.documentElement);
    Object.keys(MARKER_TYPES).forEach(function(type) {
      var color = cs.getPropertyValue(MARKER_TYPES[type]).trim();

      // "one" marker: perpendicular bar
      var one = defs.append("marker")
        .attr("id", "marker-one-" + type)
        .attr("viewBox", "0 0 4 10")
        .attr("refX", 4).attr("refY", 5)
        .attr("markerWidth", 4).attr("markerHeight", 10)
        .attr("markerUnits", "userSpaceOnUse")
        .attr("orient", "auto-start-reverse");
      one.append("path")
        .attr("d", "M 4 0 L 4 10")
        .attr("stroke", color)
        .attr("stroke-width", 1.5)
        .attr("fill", "none");

      // "many" marker: crow's foot (three tines)
      var many = defs.append("marker")
        .attr("id", "marker-many-" + type)
        .attr("viewBox", "0 0 10 10")
        .attr("refX", 10).attr("refY", 5)
        .attr("markerWidth", 10).attr("markerHeight", 10)
        .attr("markerUnits", "userSpaceOnUse")
        .attr("orient", "auto-start-reverse");
      many.append("path")
        .attr("d", "M 10 5 L 0 0 M 10 5 L 0 10 M 10 5 L 0 5")
        .attr("stroke", color)
        .attr("stroke-width", 1.5)
        .attr("fill", "none");
    });
  }

  buildMarkers();

  // Compute node heights
  nodes.forEach(function(n) {
    var cols = config.expand_columns ? n.columns : n.columns.slice(0, 4);
    n._displayCols = cols;
    n._height = NODE_HEADER_HEIGHT + cols.length * NODE_COLUMN_HEIGHT + NODE_PADDING * 2;
    if (!config.expand_columns && n.columns.length > 4) {
      n._height += NODE_COLUMN_HEIGHT; // "+N more" row
    }

    // Build column y-offset map (from node center)
    n._colYMap = {};
    var startY = -n._height / 2 + NODE_HEADER_HEIGHT + NODE_PADDING;
    cols.forEach(function(col, i) {
      n._colYMap[col.name] = startY + i * NODE_COLUMN_HEIGHT + 10;
    });

    // Store "+N more" row y-offset for collapsed column fallback
    if (!config.expand_columns && n.columns.length > 4) {
      n._moreRowY = startY + cols.length * NODE_COLUMN_HEIGHT + 10;
    } else {
      n._moreRowY = null;
    }
  });

  // Build adjacency for focus
  var adjacency = {};
  nodes.forEach(function(n) { adjacency[n.id] = new Set(); });
  edges.forEach(function(e) {
    if (adjacency[e.from]) adjacency[e.from].add(e.to);
    if (adjacency[e.to]) adjacency[e.to].add(e.from);
  });

  // Marker assignment per association type
  var MARKER_MAP = {
    belongs_to:              { start: "many", end: "one" },
    has_many:                { start: "one",  end: "many" },
    has_one:                 { start: "one",  end: "one" },
    has_and_belongs_to_many: { start: "many", end: "many" },
    embeds_many:             { start: "one",  end: "many" },
    embeds_one:              { start: "one",  end: "one" },
    embedded_in:             { start: "many", end: "one" }
  };

  function getColumnY(node, colName) {
    if (colName && node._colYMap[colName] !== undefined) {
      return node._colYMap[colName];
    }
    if (node._moreRowY !== null) return node._moreRowY;
    return 0;
  }

  function getPkColumnY(node) {
    for (var i = 0; i < node._displayCols.length; i++) {
      if (node._displayCols[i].primary) {
        return node._colYMap[node._displayCols[i].name];
      }
    }
    if (node._moreRowY !== null) return node._moreRowY;
    return 0;
  }

  function getConnectionPoints(d) {
    var src = d.source;
    var tgt = d.target;
    var assocType = d.data.association_type;
    var fk = d.data.foreign_key;
    var srcColY = 0;
    var tgtColY = 0;

    if (assocType === "belongs_to" || assocType === "embedded_in") {
      srcColY = getColumnY(src, fk);
      tgtColY = getPkColumnY(tgt);
    } else if (assocType === "has_many" || assocType === "has_one" ||
               assocType === "embeds_many" || assocType === "embeds_one") {
      srcColY = getPkColumnY(src);
      tgtColY = getColumnY(tgt, fk);
    } else {
      srcColY = getPkColumnY(src);
      tgtColY = getPkColumnY(tgt);
    }

    var dx = tgt.x - src.x;
    var srcX, tgtX, sameDirection;

    if (Math.abs(dx) > NODE_WIDTH) {
      sameDirection = false;
      if (dx > 0) {
        srcX = src.x + NODE_WIDTH / 2;
        tgtX = tgt.x - NODE_WIDTH / 2;
      } else {
        srcX = src.x - NODE_WIDTH / 2;
        tgtX = tgt.x + NODE_WIDTH / 2;
      }
    } else {
      sameDirection = true;
      srcX = src.x + NODE_WIDTH / 2;
      tgtX = tgt.x + NODE_WIDTH / 2;
    }

    return {
      x1: srcX, y1: src.y + srcColY,
      x2: tgtX, y2: tgt.y + tgtColY,
      sameDirection: sameDirection
    };
  }

  // d3-force simulation
  var orphanNodes = [];
  var connectedNodes = [];
  var selfRefNodes = [];

  function setupSimulation() {
    var nodeMap = {};
    nodes.forEach(function(n) { nodeMap[n.id] = n; });

    var simEdges = edges.filter(function(e) {
      return visibleModels.has(e.from) && visibleModels.has(e.to);
    }).map(function(e) {
      return { source: e.from, target: e.to, data: e };
    });

    var simNodes = nodes.filter(function(n) { return visibleModels.has(n.id); });

    // Partition into connected, self-ref-only, and orphan nodes
    var connectedIds = new Set();
    var selfRefIds = new Set();
    simEdges.forEach(function(e) {
      if (e.data.from !== e.data.to) {
        connectedIds.add(e.data.from);
        connectedIds.add(e.data.to);
      } else {
        selfRefIds.add(e.data.from);
      }
    });
    // Self-ref-only = has self-ref edge but no cross-model edges
    selfRefIds.forEach(function(id) { if (connectedIds.has(id)) selfRefIds.delete(id); });

    connectedNodes = simNodes.filter(function(n) { return connectedIds.has(n.id); });
    selfRefNodes = simNodes.filter(function(n) { return selfRefIds.has(n.id); });
    selfRefNodes.sort(function(a, b) { return a.id.localeCompare(b.id); });
    orphanNodes = simNodes.filter(function(n) { return !connectedIds.has(n.id) && !selfRefIds.has(n.id); });
    orphanNodes.sort(function(a, b) { return a.id.localeCompare(b.id); });

    // Exclude self-ref-only edges from force simulation
    var forceEdges = simEdges.filter(function(e) {
      return !selfRefIds.has(e.data.from) || connectedIds.has(e.data.from);
    });

    if (simulation) simulation.stop();

    simulation = d3.forceSimulation(connectedNodes)
      .force("link", d3.forceLink(forceEdges).id(function(d) { return d.id; }).distance(320))
      .force("charge", d3.forceManyBody().strength(-600))
      .force("center", d3.forceCenter(svgEl.clientWidth / 2, svgEl.clientHeight / 2))
      .force("collide", d3.forceCollide().radius(function(d) { return Math.max(NODE_WIDTH, d._height) / 2 + 50; }))
      .on("tick", ticked);

    // Manually resolve edge references for self-ref-only nodes
    simEdges.forEach(function(e) {
      if (typeof e.source === 'string' && selfRefIds.has(e.source)) {
        var node = selfRefNodes.find(function(n) { return n.id === e.source; });
        e.source = node;
        e.target = node;
      }
    });

    return { simNodes: simNodes, simEdges: simEdges };
  }

  function layoutOrphans() {
    if (orphanNodes.length === 0) return;

    // Find connected graph bounds
    var minY = Infinity, minX = Infinity, maxX = -Infinity;
    connectedNodes.forEach(function(n) {
      var top = n.y - n._height / 2;
      if (top < minY) minY = top;
      if (n.x - NODE_WIDTH / 2 < minX) minX = n.x - NODE_WIDTH / 2;
      if (n.x + NODE_WIDTH / 2 > maxX) maxX = n.x + NODE_WIDTH / 2;
    });

    // Defaults when no connected nodes
    if (minY === Infinity) minY = svgEl.clientHeight / 2;
    if (minX === Infinity) minX = svgEl.clientWidth / 2 - NODE_WIDTH;
    if (maxX === -Infinity) maxX = svgEl.clientWidth / 2 + NODE_WIDTH;

    var centerX = (minX + maxX) / 2;
    var gap = 20;
    var rowGap = 30;

    // Lay out orphans into rows (wrap when exceeding connected graph width)
    var maxRowWidth = Math.max(maxX - minX, NODE_WIDTH * 3);
    var rows = [[]];
    var rowWidths = [0];

    orphanNodes.forEach(function(n) {
      var lastRow = rows[rows.length - 1];
      var lastWidth = rowWidths[rows.length - 1];
      var addedWidth = (lastRow.length > 0 ? gap : 0) + NODE_WIDTH;

      if (lastRow.length > 0 && lastWidth + addedWidth > maxRowWidth) {
        rows.push([n]);
        rowWidths.push(NODE_WIDTH);
      } else {
        lastRow.push(n);
        rowWidths[rows.length - 1] = lastWidth + addedWidth;
      }
    });

    // Position rows above the diagram, bottom row first (closest to graph)
    var currentY = minY - rowGap;
    for (var r = rows.length - 1; r >= 0; r--) {
      var row = rows[r];
      var rowHeight = 0;
      row.forEach(function(n) { if (n._height > rowHeight) rowHeight = n._height; });

      currentY -= rowHeight / 2;
      var startX = centerX - rowWidths[r] / 2 + NODE_WIDTH / 2;

      row.forEach(function(n, i) {
        n.x = startX + i * (NODE_WIDTH + gap);
        n.y = currentY;
      });

      currentY -= rowHeight / 2 + rowGap;
    }

  }

  function layoutSelfRefNodes() {
    if (selfRefNodes.length === 0) return;

    var minX = Infinity, minY = Infinity, maxY = -Infinity;
    connectedNodes.forEach(function(n) {
      if (n.x - NODE_WIDTH / 2 < minX) minX = n.x - NODE_WIDTH / 2;
      if (n.y - n._height / 2 < minY) minY = n.y - n._height / 2;
      if (n.y + n._height / 2 > maxY) maxY = n.y + n._height / 2;
    });

    if (minX === Infinity) minX = svgEl.clientWidth / 2;
    if (minY === Infinity) minY = svgEl.clientHeight / 2 - 100;
    if (maxY === -Infinity) maxY = svgEl.clientHeight / 2 + 100;

    var gap = 20;
    var colGap = 40;
    var centerY = (minY + maxY) / 2;

    var totalHeight = 0;
    selfRefNodes.forEach(function(n) { totalHeight += n._height; });
    totalHeight += (selfRefNodes.length - 1) * gap;

    var currentY = centerY - totalHeight / 2;
    var x = minX - NODE_WIDTH - colGap;

    selfRefNodes.forEach(function(n) {
      n.x = x;
      n.y = currentY + n._height / 2;
      currentY += n._height + gap;
    });
  }

  function truncateText(text, maxWidth, font) {
    var canvas = document.createElement("canvas");
    var ctx = canvas.getContext("2d");
    ctx.font = font + " " + getComputedStyle(document.body).fontFamily;
    if (ctx.measureText(text).width <= maxWidth) return text;
    var truncated = text;
    while (truncated.length > 0 && ctx.measureText(truncated + "…").width > maxWidth) {
      truncated = truncated.slice(0, -1);
    }
    return truncated + "…";
  }

  // Render
  var currentSim;

  function render() {
    currentSim = setupSimulation();
    renderEdges(currentSim.simEdges);
    renderNodes(currentSim.simNodes);
  }

  function renderEdges(simEdges) {
    edgeGroup.selectAll(".edge-group").remove();

    // Compute parallel edge offsets for edges between same node pair
    var pairCounts = {};
    simEdges.forEach(function(d) {
      var key = [d.data.from, d.data.to].sort().join("||");
      pairCounts[key] = (pairCounts[key] || 0) + 1;
    });
    var pairSeen = {};
    simEdges.forEach(function(d) {
      var key = [d.data.from, d.data.to].sort().join("||");
      pairSeen[key] = (pairSeen[key] || 0);
      d._pairCount = pairCounts[key];
      d._pairIndex = pairSeen[key];
      pairSeen[key]++;
    });

    var eGroups = edgeGroup.selectAll(".edge-group")
      .data(simEdges, function(d) { return d.data.from + "-" + d.data.to + "-" + d.data.label; })
      .enter().append("g")
      .attr("class", "edge-group");

    eGroups.append("path")
      .attr("class", function(d) {
        var cls = "edge-line " + d.data.association_type;
        if (d.data.through) cls += " through";
        if (d.data.polymorphic) cls += " polymorphic-edge";
        return cls;
      })
      .attr("marker-start", function(d) {
        var m = MARKER_MAP[d.data.association_type];
        return m ? "url(#marker-" + m.start + "-" + d.data.association_type + ")" : null;
      })
      .attr("marker-end", function(d) {
        var m = MARKER_MAP[d.data.association_type];
        return m ? "url(#marker-" + m.end + "-" + d.data.association_type + ")" : null;
      });

    eGroups.append("rect")
      .attr("class", "edge-label-bg");

    eGroups.append("text")
      .attr("class", function(d) { return "edge-label " + d.data.association_type; })
      .attr("text-anchor", "middle")
      .attr("dy", -6)
      .text(function(d) { return d.data.label; });
  }

  function renderNodes(simNodes) {
    nodeGroup.selectAll(".node-group").remove();

    var nGroups = nodeGroup.selectAll(".node-group")
      .data(simNodes, function(d) { return d.id; })
      .enter().append("g")
      .attr("class", "node-group")
      .call(d3.drag()
        .on("start", dragStarted)
        .on("drag", dragged)
        .on("end", dragEnded))
      .on("click", function(event, d) {
        event.stopPropagation();
        selectNode(d.id);
      })
      .on("dblclick", function(event, d) {
        event.stopPropagation();
        focusNeighborhood(d.id);
      });

    // Background rect
    nGroups.append("rect")
      .attr("class", "node-rect")
      .attr("width", NODE_WIDTH)
      .attr("height", function(d) { return d._height; })
      .attr("x", -NODE_WIDTH / 2)
      .attr("y", function(d) { return -d._height / 2; });

    // Header rect
    nGroups.append("rect")
      .attr("class", "node-header-rect")
      .attr("width", NODE_WIDTH)
      .attr("height", NODE_HEADER_HEIGHT)
      .attr("x", -NODE_WIDTH / 2)
      .attr("y", function(d) { return -d._height / 2; });

    // Cover bottom corners of header
    nGroups.append("rect")
      .attr("class", "node-header-cover")
      .attr("width", NODE_WIDTH)
      .attr("height", 10)
      .attr("x", -NODE_WIDTH / 2)
      .attr("y", function(d) { return -d._height / 2 + NODE_HEADER_HEIGHT - 10; });

    // Model name
    nGroups.append("text")
      .attr("class", "node-header-text")
      .attr("x", 0)
      .attr("y", function(d) { return -d._height / 2 + 16; })
      .attr("text-anchor", "middle")
      .attr("dominant-baseline", "central")
      .text(function(d) { return truncateText(d.id, NODE_WIDTH - NODE_PADDING * 2, "bold 13px"); });

    // Table name
    nGroups.append("text")
      .attr("class", "node-table-text")
      .attr("x", 0)
      .attr("y", function(d) { return -d._height / 2 + 30; })
      .attr("text-anchor", "middle")
      .attr("dominant-baseline", "central")
      .text(function(d) { return truncateText(d.table_name, NODE_WIDTH - NODE_PADDING * 2, "10px"); });

    // Columns
    nGroups.each(function(d) {
      var g = d3.select(this);
      var startY = -d._height / 2 + NODE_HEADER_HEIGHT + NODE_PADDING;

      d._displayCols.forEach(function(col, i) {
        var y = startY + i * NODE_COLUMN_HEIGHT + 10;
        g.append("text")
          .attr("class", "node-column-text" + (col.primary ? " node-column-pk" : ""))
          .attr("x", -NODE_WIDTH / 2 + 10)
          .attr("y", y)
          .text((col.primary ? "PK " : "") + col.name);

        g.append("text")
          .attr("class", "node-column-type")
          .attr("x", NODE_WIDTH / 2 - 10)
          .attr("y", y)
          .attr("text-anchor", "end")
          .text(col.type);
      });

      if (!config.expand_columns && d.columns.length > 4) {
        var moreY = startY + d._displayCols.length * NODE_COLUMN_HEIGHT + 10;
        g.append("text")
          .attr("class", "node-column-type")
          .attr("x", 0)
          .attr("y", moreY)
          .attr("text-anchor", "middle")
          .text("+" + (d.columns.length - 4) + " more");
      }
    });
  }

  function ticked() {
    layoutOrphans();
    layoutSelfRefNodes();
    edgeGroup.selectAll(".edge-group").each(function(d) {
      var g = d3.select(this);
      var src = d.source;
      var tgt = d.target;

      // Self-referential association (markers are applied at path creation time via marker-start/marker-end)
      if (src.id === tgt.id) {
        var selfX = src.x + NODE_WIDTH / 2;
        var selfY1 = src.y - 20;
        var selfY2 = src.y + 20;
        var selfOffset = 60;
        g.select("path").attr("d",
          "M " + selfX + " " + selfY1 +
          " C " + (selfX + selfOffset) + " " + selfY1 +
          ", " + (selfX + selfOffset) + " " + selfY2 +
          ", " + selfX + " " + selfY2);
        g.select("text")
          .attr("x", selfX + selfOffset + 5)
          .attr("y", src.y);
        return;
      }

      var connPts = getConnectionPoints(d);

      // Parallel edge offset
      var parallelOffset = 0;
      if (d._pairCount > 1) {
        parallelOffset = (d._pairIndex - (d._pairCount - 1) / 2) * 8;
      }

      var y1 = connPts.y1 + parallelOffset;
      var y2 = connPts.y2 + parallelOffset;

      // Compute cubic bezier control points
      var cp1x, cp1y, cp2x, cp2y;
      if (connPts.sameDirection) {
        var loopOffset = Math.max(MIN_LOOP_OFFSET, Math.abs(y2 - y1) * LOOP_OFFSET_RATIO);
        cp1x = connPts.x1 + loopOffset;
        cp1y = y1;
        cp2x = connPts.x2 + loopOffset;
        cp2y = y2;
      } else {
        var dx = connPts.x2 - connPts.x1;
        var cpOffset = Math.max(MIN_CURVE_OFFSET, Math.abs(dx) * CURVE_OFFSET_RATIO);
        var dir = Math.sign(dx) || 1;
        cp1x = connPts.x1 + cpOffset * dir;
        cp1y = y1;
        cp2x = connPts.x2 - cpOffset * dir;
        cp2y = y2;
      }

      g.select("path").attr("d",
        "M " + connPts.x1 + " " + y1 +
        " C " + cp1x + " " + cp1y +
        ", " + cp2x + " " + cp2y +
        ", " + connPts.x2 + " " + y2);

      var labelX = 0.125 * connPts.x1 + 0.375 * cp1x + 0.375 * cp2x + 0.125 * connPts.x2;
      var labelY = (y1 + y2) / 2;
      g.select("text")
        .attr("x", labelX)
        .attr("y", labelY);
    });

    resolveEdgeLabelOverlaps();

    nodeGroup.selectAll(".node-group")
      .attr("transform", function(d) { return "translate(" + d.x + "," + d.y + ")"; });
  }

  function resolveEdgeLabelOverlaps() {
    var labels = [];
    edgeGroup.selectAll(".edge-group text").each(function() {
      var el = d3.select(this);
      var x = +el.attr("x");
      var y = +el.attr("y");
      var text = el.text();
      var w = text.length * 6;  // approximate width at 10px font
      var h = 14;               // approximate height
      labels.push({ el: el, x: x, y: y, w: w, h: h });
    });

    // Run a few nudge passes
    for (var pass = 0; pass < 3; pass++) {
      for (var i = 0; i < labels.length; i++) {
        for (var j = i + 1; j < labels.length; j++) {
          var a = labels[i], b = labels[j];
          var overlapX = (a.w + b.w) / 2 - Math.abs(a.x - b.x);
          var overlapY = (a.h + b.h) / 2 - Math.abs(a.y - b.y);
          if (overlapX > 0 && overlapY > 0) {
            // Push apart vertically
            var shift = (overlapY / 2) + 2;
            if (a.y <= b.y) {
              a.y -= shift;
              b.y += shift;
            } else {
              a.y += shift;
              b.y -= shift;
            }
          }
        }
      }
    }

    // Apply resolved positions and update background rects
    labels.forEach(function(l) {
      l.el.attr("y", l.y);
      var bg = d3.select(l.el.node().previousElementSibling);
      if (bg.classed("edge-label-bg")) {
        bg.attr("x", l.x - l.w / 2)
          .attr("y", l.y - l.h + 2)
          .attr("width", l.w)
          .attr("height", l.h);
      }
    });
  }

  // Drag behavior
  function isOrphan(d) {
    return orphanNodes.indexOf(d) !== -1 || selfRefNodes.indexOf(d) !== -1;
  }

  function dragStarted(event, d) {
    if (isOrphan(d)) return;
    if (!event.active) simulation.alphaTarget(0.3).restart();
    d.fx = d.x;
    d.fy = d.y;
  }

  function dragged(event, d) {
    if (isOrphan(d)) {
      d.x = event.x;
      d.y = event.y;
      ticked();
      return;
    }
    d.fx = event.x;
    d.fy = event.y;
  }

  function dragEnded(event, d) {
    if (isOrphan(d)) return;
    if (!event.active) simulation.alphaTarget(0);
    d.fx = null;
    d.fy = null;
  }

  // Zoom
  var zoom = d3.zoom()
    .scaleExtent([0.1, 4])
    .on("zoom", function(event) {
      zoomTransform = event.transform;
      container.attr("transform", event.transform);
      document.getElementById("zoom-info").textContent = Math.round(event.transform.k * 100) + "%";
    });

  svg.call(zoom);
  svg.on("dblclick.zoom", null);

  // Click background to deselect
  svg.on("click", function() {
    deselectNode();
  });

  // Selection / Focus
  function selectNode(nodeId) {
    selectedNode = nodeId;
    var neighbors = adjacency[nodeId] || new Set();

    nodeGroup.selectAll(".node-group")
      .classed("faded", function(d) { return d.id !== nodeId && !neighbors.has(d.id); })
      .classed("highlighted", function(d) { return d.id === nodeId; });

    edgeGroup.selectAll(".edge-group")
      .classed("faded", function(d) {
        var src = typeof d.source === "object" ? d.source.id : d.source;
        var tgt = typeof d.target === "object" ? d.target.id : d.target;
        return !(src === nodeId || tgt === nodeId);
      });

    showDetailPanel(nodeId);
    updateSidebarActive(nodeId);
  }

  function focusNeighborhood(nodeId) {
    var neighbors = adjacency[nodeId] || new Set();
    visibleModels.clear();
    visibleModels.add(nodeId);
    neighbors.forEach(function(id) { visibleModels.add(id); });
    buildSidebar();
    render();
    selectNode(nodeId);
    setTimeout(fitToScreen, 100);
  }

  function deselectNode() {
    selectedNode = null;
    nodeGroup.selectAll(".node-group").classed("faded", false).classed("highlighted", false);
    edgeGroup.selectAll(".edge-group").classed("faded", false);
    hideDetailPanel();
    updateSidebarActive(null);
  }

  // Detail panel
  function showDetailPanel(nodeId) {
    var node = nodes.find(function(n) { return n.id === nodeId; });
    if (!node) return;

    var panel = document.getElementById("detail-panel");
    var content = document.getElementById("detail-content");
    panel.classList.add("open");

    var nodeEdges = edges.filter(function(e) { return e.from === nodeId || e.to === nodeId; });

    var html = '<div class="detail-header">';
    html += '<h2 title="' + escapeHtml(node.id) + '">' + escapeHtml(node.id) + '</h2>';
    html += '<button id="detail-close" onclick="window.__closeDetail()">&times;</button>';
    html += '</div>';
    html += '<div class="detail-table" title="' + escapeHtml(node.table_name) + '">' + escapeHtml(node.table_name) + '</div>';

    html += '<h3>Columns</h3>';
    html += '<ul class="column-list">';
    node.columns.forEach(function(col) {
      var pkCls = col.primary ? ' pk' : '';
      html += '<li><span class="col-name' + pkCls + '">' + (col.primary ? 'PK ' : '') + escapeHtml(col.name) + '</span>';
      html += '<span class="col-type">' + escapeHtml(col.type) + (col.nullable ? '' : ' NOT NULL') + '</span></li>';
    });
    html += '</ul>';

    if (nodeEdges.length > 0) {
      html += '<h3>Associations</h3>';
      html += '<ul class="assoc-list">';
      nodeEdges.forEach(function(e) {
        var target = e.from === nodeId ? e.to : e.from;
        html += '<li><span class="assoc-type">' + escapeHtml(e.association_type) + '</span>';
        html += '<span class="assoc-target" data-model="' + escapeHtml(target) + '">' + escapeHtml(e.label) + '</span>';
        html += ' &rarr; ' + escapeHtml(target);
        if (e.through) html += ' <em>(through ' + escapeHtml(e.through) + ')</em>';
        html += '</li>';
      });
      html += '</ul>';
    }

    content.innerHTML = html;

    // Click association targets to navigate
    content.querySelectorAll('.assoc-target').forEach(function(el) {
      el.addEventListener('click', function() {
        selectNode(el.dataset.model);
      });
    });
  }

  function hideDetailPanel() {
    document.getElementById("detail-panel").classList.remove("open");
  }

  window.__closeDetail = deselectNode;

  // Sidebar
  function buildSidebar() {
    var list = document.getElementById("model-list");
    list.innerHTML = "";

    var filtered = getFilteredModels();

    filtered.forEach(function(n) {
      var edgeCount = edges.filter(function(e) { return e.from === n.id || e.to === n.id; }).length;
      var div = document.createElement("div");
      div.className = "model-item" + (selectedNode === n.id ? " active" : "");
      div.innerHTML = '<input type="checkbox" ' + (visibleModels.has(n.id) ? "checked" : "") + '>' +
        '<span class="model-name">' + escapeHtml(n.id) + '</span>' +
        '<span class="assoc-count">' + edgeCount + '</span>';

      var cb = div.querySelector("input");
      cb.addEventListener("change", function(e) {
        e.stopPropagation();
        if (cb.checked) {
          visibleModels.add(n.id);
        } else {
          visibleModels.delete(n.id);
        }
        render();
      });

      div.addEventListener("click", function(e) {
        if (e.target.tagName === "INPUT") return;
        selectNode(n.id);
      });

      list.appendChild(div);
    });
  }

  function getFilteredModels() {
    var query = document.getElementById("search-input").value.toLowerCase();
    if (!query) return nodes;
    return nodes.filter(function(n) {
      return n.id.toLowerCase().indexOf(query) !== -1 ||
             n.table_name.toLowerCase().indexOf(query) !== -1;
    });
  }

  function updateSidebarActive(nodeId) {
    document.querySelectorAll(".model-item").forEach(function(el) {
      var name = el.querySelector(".model-name").textContent;
      el.classList.toggle("active", name === nodeId);
    });
  }

  // Search
  document.getElementById("search-input").addEventListener("input", function() {
    buildSidebar();
  });

  // Select/Deselect all
  document.getElementById("select-all-btn").addEventListener("click", function() {
    nodes.forEach(function(n) { visibleModels.add(n.id); });
    buildSidebar();
    render();
  });

  document.getElementById("deselect-all-btn").addEventListener("click", function() {
    visibleModels.clear();
    buildSidebar();
    render();
  });

  // Toolbar buttons
  document.getElementById("zoom-in-btn").addEventListener("click", function() {
    svg.transition().duration(300).call(zoom.scaleBy, 1.3);
  });

  document.getElementById("zoom-out-btn").addEventListener("click", function() {
    svg.transition().duration(300).call(zoom.scaleBy, 0.7);
  });

  document.getElementById("fit-btn").addEventListener("click", fitToScreen);

  document.getElementById("theme-btn").addEventListener("click", function() {
    var html = document.documentElement;
    if (html.classList.contains("dark")) {
      html.classList.remove("dark");
      html.classList.add("light");
    } else if (html.classList.contains("light")) {
      html.classList.remove("light");
      html.classList.add("dark");
    } else {
      // Auto mode — detect current and flip
      var isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
      html.classList.add(isDark ? "light" : "dark");
    }
    buildMarkers();
  });

  // Rebuild markers when system theme changes
  window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", function() {
    buildMarkers();
  });

  function fitToScreen() {
    var bounds = container.node().getBBox();
    if (bounds.width === 0 || bounds.height === 0) return;

    var fullWidth = svgEl.clientWidth;
    var fullHeight = svgEl.clientHeight;
    var midX = bounds.x + bounds.width / 2;
    var midY = bounds.y + bounds.height / 2;
    var scale = 0.9 / Math.max(bounds.width / fullWidth, bounds.height / fullHeight);
    scale = Math.min(scale, 2);

    var transform = d3.zoomIdentity
      .translate(fullWidth / 2, fullHeight / 2)
      .scale(scale)
      .translate(-midX, -midY);

    svg.transition().duration(500).call(zoom.transform, transform);
  }

  // Keyboard shortcuts
  document.addEventListener("keydown", function(e) {
    // Don't intercept when typing in inputs
    if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA") {
      if (e.key === "Escape") {
        e.target.blur();
        deselectNode();
      }
      return;
    }

    switch (e.key) {
      case "/":
        e.preventDefault();
        document.getElementById("search-input").focus();
        break;
      case "Escape":
        deselectNode();
        break;
      case "+":
      case "=":
        svg.transition().duration(200).call(zoom.scaleBy, 1.3);
        break;
      case "-":
        svg.transition().duration(200).call(zoom.scaleBy, 0.7);
        break;
      case "f":
      case "F":
        fitToScreen();
        break;
    }
  });

  // Utility
  function escapeHtml(str) {
    var div = document.createElement("div");
    div.appendChild(document.createTextNode(str));
    return div.innerHTML;
  }

  // Init
  buildSidebar();
  render();

  // Fit after simulation settles
  setTimeout(function() { fitToScreen(); }, 1500);
})();
