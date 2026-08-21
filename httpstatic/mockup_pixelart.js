import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, INPUT, LI, OPTION, TD, TIME, TR} = lindt; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

//Set the order for core colours, shown in bright and dark forms
const core_colors = ["#000000", "#000011", "#001100", "#110000", "#001111", "#110011", "#111100", "#111111"];
let hue = "#111111";
const shaderows = ["f", "7"]; //Bright and dark initially (also used for selecting hue for the next two rows)
const shades = [["0", "1", "2", "3", "4", "5", "6", "7"], ["8", "9", "a", "b", "c", "d", "e", "f"]];
let custom_colors = ["#a0f0c0"];
try {custom_colors = JSON.parse(localStorage.getItem("mockup_custom_colors") || '["#a0f0c0"]');} catch (e) {}

//let curcolor = "#000000";
let curcolor = "";
let grid = [];
let image_type = "icon"; //TODO: Block UI elements inappropriate to the type
//Grids shouldn't get antialias resized
//Tiles should be locked to 25x25
let xsize = 25, ysize = 25; //Grid size
let cellsize = [1, 1]; //Size of an individual cell. If [1, 1], we're making an image out of pixels; if larger, we're making a grid.
let gridborder = 1; //Applicable only in grid mode, defines the thickness of the lines between cells
let gridcolor = "#000000";
let dragging = null, line = { };
function color(hue, brightness) {
	//Special-case a couple.
	if (hue === "#000000" && brightness === "7") return "#666666";
	if (hue === "#ffffff" && brightness === "7") return "#cccccc";
	return hue.replace(/1/g, brightness);
}
function color_to_background(col) {
	if (!col) return "transparent";
	if (col[0] === "#") return col;
	const img = meta.tiles[col];
	if (img) return "url(" + img.url + ")"
	return "transparent";
}
DOM("#curcolor").style.background = color_to_background(curcolor);
function repaint() {
	//Note that "tile mode" also covers icons
	document.body.classList = (cellsize[0] === 1 && cellsize[1] === 1) ? "tilemode" : "gridmode";
	replace_content("#palette", [
		//Bright and dark colors
		shaderows.map(s => TR(core_colors.map(col => TD({
			class: "pickcolor",
			"data-hue": col === "#000000" ? "#111111" : col,
			"data-color": color(col, s), style: "background: " + color(col, s),
		})))),
		//Shades of the selected hue
		shades.map(row => TR(row.map(s => TD({class: "pickcolor", "data-color": hue.replace(/1/g, s), style: "background: " + hue.replace(/1/g, s)})))),
		TR([
			custom_colors.map(col => TD({class: "pickcolor", "data-color": col, style: "background: " + col})),
			TD({style: "padding: 0 0 0 8px", colSpan: 8 - custom_colors.length}, BUTTON({type: "button", id: "pickcustoms", title: "Pick custom colors"}, "\u2699")),
		]),
	]);
	if (grid.length > ysize) grid.length = ysize;
	while (grid.length < ysize) grid.push([]);
	for (let row of grid) {
		if (row.length > xsize) row.length = xsize;
		while (row.length < xsize) row.push("");
	}
	DOM("#xsize").value = xsize;
	DOM("#ysize").value = ysize;
	replace_content("#grid", grid.map((row, y) => TR(row.map((cell, x) => TD({
		style: "background: " + color_to_background(line[x + "," + y] ? curcolor : cell)
	})))));
}

function update_line() {
	line = { };
	if (!dragging) {repaint(); return;}
	let [x1, y1, x2, y2, constrain] = dragging;
	//There are several possibilities to handle here.
	//1) Are we moving more horizontally or more vertically?
	//2) Is the shift key held?
	//Note that currently, a constrained line will only be horizontal or vertical.
	//Allowing a constrained line to run at 45° would require testing whether the
	//line is "more horizontal, more diagonal, or more vertical", instead of the
	//simpler two-way test that is also important for the unconstrained line.
	let dx = x2 - x1, dy = y2 - y1;
	//Ahh, Bresenham's algorithm, my good friend.
	const flip = Math.abs(dx) > Math.abs(dy);
	if (flip) [x1, x2, dx, y1, y2, dy] = [y1, y2, dy, x1, x2, dx];
	if (constrain) {dx = 0; x2 = x1;}
	//So now we know that dx is the smaller value, but if we're flipping, we put
	//the coordinates into the output backwards :)
	if (y1 > y2) [x1, y1, x2, y2, dx, dy] = [x2, y2, x1, y1, -dx, -dy];
	//And now we are guaranteed that y1 <= y2, so we can iterate easily.
	const ratio = dx / dy;
	let x = x1, frac = dx < 0 ? -0.5 : 0.5;
	for (let y = y1; y <= y2; y++) {
		if (flip) line[y + "," + x] = 1;
		else line[x + "," + y] = 1;
		frac += ratio;
		if (frac > +1) {frac -= 1; ++x;}
		if (frac < -1) {frac += 1; --x;}
	}
	repaint();
}

export function render(data) {
	//Nothing to socket-synchronize as yet
	repaint();
}

on("click", ".pickcolor", e => {
	DOM("#curcolor").style.background = color_to_background(curcolor = e.match.dataset.color);
	if (e.match.dataset.hue) {hue = e.match.dataset.hue; repaint();}
});

on("pointerdown", "#grid", e => {
	if (e.button) return; //Only left clicks
	e.preventDefault();
	const x = e.target.cellIndex, y = e.target.parentElement.rowIndex;
	dragging = [x, y, x, y, e.shiftKey];
	update_line();
});
on("pointermove", "#grid", e => {
	if (!dragging) return;
	const x = e.target.cellIndex, y = e.target.parentElement.rowIndex;
	if (dragging[2] !== x || dragging[3] !== y || dragging[4] !== e.shiftKey) {
		dragging[2] = x;
		dragging[3] = y;
		dragging[4] = e.shiftKey;
		update_line();
	}
});
document.onkeydown = document.onkeyup = e => {
	if (dragging && e.key === "Escape") {dragging = null; update_line();} //Note that we don't release pointer capture until pointer up
	if (dragging && dragging[4] !== e.shiftKey) {dragging[4] = e.shiftKey; update_line();}
}
on("pointerup", "#grid", e => {
	e.target.releasePointerCapture(e.pointerId);
	if (!dragging) return;
	//"Harden" the line into being real.
	grid.forEach((row, y) => row.forEach((cell, x) => line[x + "," + y] && (row[x] = curcolor)));
	dragging = null;
	update_line();
});

on("submit", "#saveimage", e => {
	ws_sync.send({cmd: "save_image",
		type: image_type,
		name: e.match.elements.savename.value,
		grid, cellsize, gridborder, gridcolor,
	});
});

function DATE(d) {
	if (!d) return "(unknown)";
	const date = new Date(d * 1000);
	let day = date.getDate();
	switch (day) {
		case 1: case 21: day += "st"; break;
		case 2: case 22: day += "nd"; break;
		case 3: case 23: day += "rd"; break;
		default: day += "th";
	}
	return TIME({datetime: date.toISOString(), title: date.toLocaleString()}, [
		//This abbreviated format assumes English and shows just the date. The hover uses your locale.
		"Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(" ")[date.getMonth()] + " " + day,
	]);
}

function imagelist(type) {
	return Object.entries(meta[type + "s"])
		.sort((a, b) => a[0].localeCompare(b[0]))
		.map(([id, img]) => LI({class: "type-" + type}, [
			img.title || id,
			//For grids, show the size in cells rather than pixels
			img.grid ? " (" + img.grid[0].length + "x" + img.grid.length + ")" : " (" + img.xsize + "x" + img.ysize + ") ",
			"(", DATE(img.created_at), ") ",
			//TODO: Check img.created_by, show if it was created by you
			//Maybe show the user name that created it? Would need serverside help.
			BUTTON({"data-id": id, "data-type": type, class: "loadimg"}, "Load"),
			BUTTON({type: "button", class: "deleteimage", title: "Delete", "data-id": id}, "🗑"),
		]))
}
export function sockmsg_update_meta(msg) {
	meta = msg;
	const tiles = Object.entries(meta.tiles).sort((a, b) => a[0].localeCompare(b[0]));
	replace_content("#imagelist", [
		//Order here doesn't matter - only one block should ever be visible at a time
		imagelist("tile"),
		imagelist("icon"),
		imagelist("grid"),
	]).className = "showtype-" + image_type;
	let row = [], toolbox = [];
	for (let [id, img] of tiles) {
		if (img.xsize !== 25 || img.ysize !== 25) continue; //TODO: Use the configured tile size, not hard-coded 25x25
		if (row.length >= 10) {toolbox.push(TR(row)); row = [];}
		row.push(TD({class: "pickcolor", "data-color": id, title: id, style: "background: url(" + img.url + ")"}));
	}
	if (!row.length) row.push(TD("(none)"));
	toolbox.push(TR(row));
	replace_content("#toolbox", toolbox);
}
sockmsg_update_meta(meta);

function hex(n) {return ("0" + n.toString(16)).slice(-2);}

on("click", ".loadimg", e => {
	//Grids are easy to load, we already have what we need.
	if (image_type === "grid") {
		const img = meta.grids[e.match.dataset.id];
		if (!img) return; // ?? Somehow not found for loading
		DOM("#saveimage [name=savename]").value = e.match.dataset.id;
		grid = img.grid;
		xsize = grid[0].length;
		ysize = grid.length;
		gridborder = img.gridborder;
		if (img.gridcolor) gridcolor = "#" + hex(img.gridcolor[0]) + hex(img.gridcolor[1]) + hex(img.gridcolor[2])
		else gridcolor = "";
		repaint();
		DOM("#configuredlg").close();
	}
	//We do have the data URL for the image already, but it's easier to let Pike decode it and
	//turn it into a nice collection of pixel colours for us.
	else ws_sync.send({cmd: "load_image", type: e.match.dataset.type, id: e.match.dataset.id});
});
export function sockmsg_image_loaded(msg) { //Also, curiously, triggered by a rescale request :)
	DOM("#configuredlg").close();
	if (msg.type) image_type = msg.type;
	if (msg.id) DOM("#saveimage [name=savename]").value = msg.id;
	grid = msg.grid;
	xsize = grid[0].length;
	ysize = grid.length;
	repaint();
}

on("submit", "#resizedlg form", e => {
	if (DOM("#antialias").checked) {
		//Rescale. So, I could implement a nice complicated algorithm to rescale an
		//image.... or.... I could sing out "hey Pike, can you rescale this for me?"
		//Yes, that does introduce network latency, but that's a whole lot easier.
		ws_sync.send({cmd: "rescale",
			xsize: +DOM("#xsize").value,
			ysize: +DOM("#ysize").value,
			grid,
		});
	} else if (DOM("#scale").checked) {
		//Multiplicative rescale. Much simpler than antialiasing and retains the
		//color palette, but introduces jaggedness when you do small adjustments.
		const xs = +DOM("#xsize").value, ys = +DOM("#ysize").value;
		const dx = xsize / xs, dy = (ysize + 1) / (ys + 1);
		let ypos = 0.5;
		const g = [];
		for (let y = 0; y < ys; ++y, ypos += dy) {
			const row = [];
			let xpos = 0.5;
			for (let x = 0; x < xs; ++x, xpos += dx)
				row.push(grid[ypos|0][xpos|0]);
			g.push(row);
		}
		grid = g; xsize = xs; ysize = ys;
		repaint();
	} else {
		//Simple resize - crop or add transparency
		xsize = +DOM("#xsize").value;
		ysize = +DOM("#ysize").value;
		repaint();
	}
});

on("click", ".deleteimage", simpleconfirm("Delete this image? This cannot be undone!",
	e => ws_sync.send({cmd: "delete_image", type: image_type, id: e.match.dataset.id})));

function update_custom_colors(colors) {
	replace_content("#colorlist", [
		colors.map((col, idx) => LI([INPUT({type: "color", value: col}), BUTTON({type: "button", class: "deletecolor", "data-idx": idx, title: "Delete"}, "🗑")])),
		LI(BUTTON({type: "button", id: "addcolor"}, "Add")),
	]);
}
on("click", "#pickcustoms", e => {
	update_custom_colors(custom_colors);
	DOM("#customcolordlg").showModal();
});
function fetch_custom_colors() {
	const colors = [];
	document.querySelectorAll("#colorlist input[type=color]").forEach(el => colors.push(el.value));
	return colors;
}

on("click", "#addcolor", e => {
	const colors = fetch_custom_colors();
	colors.push("#ffffff");
	update_custom_colors(colors);
});

on("click", ".deletecolor", e => {
	const colors = fetch_custom_colors();
	colors.splice(e.match.dataset.idx, 1);
	update_custom_colors(colors);
});

on("submit", "#customcolordlg form", e => {
	custom_colors = fetch_custom_colors();
	repaint();
	localStorage.setItem("mockup_custom_colors", JSON.stringify(custom_colors));
});

on("click", "#configurebtn", e => {
	DOM("#gridvisible").checked = gridcolor !== "";
	DOM("#gridcolor").value = gridcolor || "#000000";
	DOM("#gridborder").value = gridborder || 0;
	DOM("#" + image_type + "mode").checked = 1;
	DOM("#configuredlg").showModal();
});

on("click", "[name=mode]", e => {
	image_type = e.match.id.slice(0, 4);
	DOM("#imagelist").className = "showtype-" + image_type;
	cellsize = image_type === "grid" ? [25, 25] : [1, 1];
	repaint();
});
on("change", "#gridcolor", e => {
	gridcolor = e.match.value;
	DOM("#gridvisible").checked = false;
});
on("click", "#gridvisible", e => gridcolor = e.match.checked ? DOM("#gridcolor").value : "");
on("change", "#gridborder", e => gridborder = e.match.value|0);

//TODO: Deduplicate this with pages.js and make a convenient "file accept" system
//with a callback that can do the actual work. It'll need to receive e.match.
function upload(f) {
	const r = new FileReader();
	r.onload = () => ws_sync.send({cmd: "import", name: f.name, base64: r.result.split(",")[1]});
	r.readAsDataURL(f);
	DOM("#importdlg").close();
}

on("change", ".fileuploader", e => {
	for (let f of e.match.files) upload(f);
	e.match.value = "";
});
on("dragover", ".filedropzone", e => e.preventDefault());
on("drop", ".filedropzone", e => {
	e.preventDefault();
	for (let f of e.dataTransfer.items) upload(f.getAsFile());
});

on("submit", "#importdlg form", e => ws_sync.send({cmd: "import", url: e.match.elements.importurl.value}));
