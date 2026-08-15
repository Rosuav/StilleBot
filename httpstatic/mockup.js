//NOTE: This file only handles the actual mockup rendering.
//For the landing page and pixel art, both of which are also on /mockup,
//see mockup_landing.js and mockup_pixelart.js respectively.
import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, DIV, LI, OPTION, UL} = lindt; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

const clientid = Math.random() + "." + Math.random(); //If an update is caused by us, we ignore it

const SNAP_DISTANCE = 10; //Distance to permit snapping (pixels)
const SNAP_RANGE = SNAP_DISTANCE * SNAP_DISTANCE; //The distance squared is more useful in arithmetic
let curscene = "";
let state = { };
let element_position = { }; //Shorthand: element_position <=> state.scenes[curscene].elements
let mutation_allowed = false; //If true, show buttons etc for read/write access, since the server's told us we're allowed to
export function sockmsg_mutation(msg) {mutation_allowed = msg.allowed; render(state);}
let hoverelement = null;

//Use &edit= to enable editing automatically. If a password has been set, this won't work.
//TODO: Allow the user to enter a password, which then gets saved here - on socket reconnect,
//the same password will be re-sent.
let mutate = new URLSearchParams(location.search).get("edit");
export function socket_connected(sock) {
	if (typeof mutate === "string") sock.send(JSON.stringify({cmd: "mutate", mutate}));
}

export function sockmsg_update_meta(msg) {
	meta = msg;
	replace_content("#imageselector", Object.entries(meta.icons)
		.map(([id, t]) => [t.title || id, id])
		.sort((a, b) => a[0].localeCompare(b[0]))
		.map(([title, id]) => OPTION({value: id}, title))
	);
	replace_content("#bgselector", Object.entries(meta.grids)
		.map(([id, t]) => [t.title || id, id])
		.sort((a, b) => a[0].localeCompare(b[0]))
		.map(([title, id]) => OPTION({value: id}, title))
	);
	if (meta.grids[state.bg]) repaint();
}
sockmsg_update_meta(meta);

const image_cache = { };
function preload_icon(url, needed) {
	image_cache[url] = choc.IMG({src: url, crossOrigin: "anonymous", onload: needed && repaint});
}

const canvas = DOM("canvas");
const ctx = canvas.getContext("2d");
let dragging = null, dragbasex = 50, dragbasey = 10, dragorigx, dragorigy;
let clicking = false;
const elements_by_zorder = [];
function draw_element(ctx, el) {
	elements_by_zorder.push(el);
	const url = meta.icons[el.image]?.url;
	if (!url) return;
	const img = image_cache[url];
	if (!img) {preload_icon(url, 1); return;}
	if (!img.naturalWidth) return; //Probably not loaded yet
	//If the element has not had its size/pos recorded, set it to the default,
	//but allow it to be changed later by rescaling.
	let pos = element_position[el.id];
	if (!pos) element_position[el.id] = pos = {x: 0, y: 0};
	el.xsize = el.xsize || img.naturalWidth;
	el.ysize = el.ysize || img.naturalHeight;
	ctx.save();
	if (el.angle) {
		//Rotate around the element's midpoint. Note that the rotation is negated
		//to make positive angles put us into the mathematical first quadrant,
		//despite increasing Y values taking us towards the bottom of the canvas.
		ctx.translate(pos.x + el.xsize / 2, pos.y + el.ysize / 2);
		ctx.rotate(el.angle * Math.PI / -180);
		ctx.translate(-pos.x - el.xsize / 2, -pos.y - el.ysize / 2);
	}
	ctx.drawImage(img, pos.x, pos.y, el.xsize, el.ysize);
	if (dragging) {
		ctx.strokeRect(pos.x, pos.y, el.xsize, el.ysize);
		//TODO: Do partial circles for the corners, only drawing the part outside
		for (let x = 0; x < 3; ++x) {
			for (let y = 0; y < 3; ++y) {
				ctx.beginPath();
				ctx.fillStyle = ctx.strokeStyle = x === 1 && y === 1 ? "cyan" : "blue"
				ctx.arc(pos.x + el.xsize * x / 2, pos.y + el.ysize * y / 2, 3, 0, 2 * Math.PI);
				ctx.fill();
			}
		}
	}
	if (el.id === hoverelement) {
		ctx.save();
		ctx.setLineDash([1, 1]);
		ctx.strokeStyle = "rebeccapurple";
		ctx.strokeRect(pos.x, pos.y, el.xsize, el.ysize);
		ctx.restore();
	}
	ctx.restore();
	//If parent-child relationships are implemented, draw all this element's children
}

function repaint() {
	ctx.clearRect(0, 0, canvas.width, canvas.height);
	const url = meta.grids[state.bg]?.url;
	if (url) {
		const img = image_cache[url];
		if (!img) preload_icon(url, 1);
		else ctx.drawImage(img, 0, 0);
	}
	elements_by_zorder.length = 0;
	const elem = Object.entries(state.elements).sort((a, b) => a[0].localeCompare(b[0])); //Sort by ID. May need a way to explicitly reorder them.
	ctx.strokeStyle = ctx.fillStyle = "blue"; //Draw the frames around elements in blue
	//Parent-child relationships not currently implemented, but maybe.
	//If an element is a child of another, it will always be drawn after its parent
	//and before any of its parent's siblings, and it will be positioned relative to
	//its parent rather than absolutely on the canvas.
	elem.forEach(([id, el]) => {
		el.id = id;
		if (!el.parent && el !== dragging) draw_element(ctx, el);
	});
	if (dragging) draw_element(ctx, dragging); //Anything being dragged gets drawn last, ensuring it is at the top of z-order.
}

function element_at_position(x, y, filter) {
	//Iterate through all elements, starting at the top of the z-order stack and going
	//to the bottom; the first one found containing the given position is returned.
	for (let i = elements_by_zorder.length - 1; i >= 0; --i) {
		//TODO: Handle rotated clipping rectangles
		const el = elements_by_zorder[i];
		const pos = element_position[el.id];
		if (x >= pos.x && y >= pos.y && x < pos.x + el.xsize && y < pos.y + el.ysize && (!filter || filter(el))) return el;
	}
}

canvas.addEventListener("pointerdown", e => {
	if (e.button) return; //Only left clicks
	if (!mutation_allowed) return;
	e.preventDefault();
	dragging = null;
	const el = element_at_position(e.offsetX, e.offsetY, el => !element_position[el.id].locked);
	if (!el) return;
	e.target.setPointerCapture(e.pointerId);
	clicking = true;
	if (e.ctrlKey) {
		//TODO: Hold Ctrl to take a copy of the element and start dragging that
		//el = clone_element(el);
	}
	const pos = element_position[el.id];
	dragging = el; dragbasex = e.offsetX - pos.x; dragbasey = e.offsetY - pos.y;
	dragorigx = pos.x; dragorigy = pos.y;
});

//Corners and middles defined as proportions of the width/height
//[x fraction, y fraction, affinity]
const corners = [
	[0.0, 0.0, 1], [0.5, 0.0, 1], [1.0, 0.0, 1],
	[0.0, 0.5, 1], [0.5, 0.5, 2], [1.0, 0.5, 1],
	[0.0, 1.0, 1], [0.5, 1.0, 1], [1.0, 1.0, 1],
];
function snap_to_elements(baseelem, xpos, ypos, moresnap) {
	//Start by defining the "search rectangle". If the base element is rotated, this should be the
	//axis-aligned bounding box.
	const left = xpos - SNAP_DISTANCE, top = ypos - SNAP_DISTANCE;
	const right = xpos + baseelem.xsize + SNAP_DISTANCE, bottom = ypos + baseelem.ysize + SNAP_DISTANCE;
	for (let el of elements_by_zorder) {
		if (el.id === baseelem.id) continue; //Don't snap to yourself
		const pos = element_position[el.id];
		//If the right edge of this element is to the left of the left edge of our bounding box,
		//there's no way that it's within snap range (since the bounding box includes snap size).
		if (pos.x + el.xsize < left || pos.x > right || pos.y + el.ysize < top || pos.y > bottom) continue;
		//Okay. So we have at least the plausibility of overlap.
		//I could, in theory, make this more efficient. For now I won't bother. Let's go through some
		//possible snapping arrangements.
		for (let c1 of corners) for (let c2 of corners) {
			//Go through all nine corners and middles of each element. See if there's a good
			//snap to be found.
			//Normal snapping: The center only snaps to another center, but corners and
			//edge middles all snap to each other.
			//If any-snapping is active, affinities are ignored
			if (!moresnap && c1[2] !== c2[2]) continue;
			const x1 = xpos + c1[0] * baseelem.xsize, y1 = ypos + c1[1] * baseelem.ysize;
			const x2 = pos.x + c2[0] * el.xsize, y2 = pos.y + c2[1] * el.ysize;
			if ((x1 - x2) ** 2 + (y1 - y2) ** 2 <= SNAP_RANGE) {
				//Alright! Let's snap to that. So, how do we need to move in order
				//to place (x1, y1) onto (x2, y2)? Move the base position that far.
				return [xpos + x2 - x1, ypos + y2 - y1];
			}
		}
		//If we didn't find a corner to snap to, try snapping to an edge instead.
		//There are four edges, but each one only snaps to two (you don't snap the
		//top of one thing to the left of another).
		for (let e1 = 0; e1 <= 1; ++e1) for (let e2 = 0; e2 <= 1; ++e2) {
			//e1 is 0 for left/top of the base element, 1 for right/bottom.
			//e2 is the corresponding for the test element.
			const x1 = xpos + e1 * baseelem.xsize, y1 = ypos + e1 * baseelem.ysize;
			const x2 = pos.x + e2 * el.xsize, y2 = pos.y + e2 * el.ysize;
			//if (x1 - x2 <= SNAP_DISTANCE && x2 - x1 <= SNAP_DISTANCE) //Is it better to do two comparisons, to call Math.abs(), or to square the number?
			if ((x1 - x2) ** 2 <= SNAP_RANGE) //Going with squaring for consistency with the corner snaps.
				//Horizontal snapping (to a vertical edge)
				return [xpos + x2 - x1, ypos];
			if ((y1 - y2) ** 2 <= SNAP_RANGE)
				//Vertical snapping (to a horizontal edge)
				return [xpos, ypos + y2 - y1];
		}
	}
	return [xpos, ypos];
}

canvas.addEventListener("pointermove", e => {
	clicking = false;
	let cursor = "default";
	if (dragging) {
		cursor = "grabbing";
		const pos = element_position[dragging.id];
		[pos.x, pos.y] = snap_to_elements(dragging, e.offsetX - dragbasex, e.offsetY - dragbasey, e.shiftKey);
		repaint();
	}
	else {
		const el = element_at_position(e.offsetX, e.offsetY);
		//if (e.ctrlKey && el) cursor = "copy"; //If copy is implemented, show it via the cursor
		canvas.title = el?.title || "";
	}
	canvas.style.cursor = cursor;
});
document.onkeydown = document.onkeyup = e => {
	if (dragging) {
		if (e.key === "Escape") {
			//Note that we don't release pointer capture until pointer up
			const pos = element_position[dragging.id];
			dragging = null; pos.x = dragorigx; pos.y = dragorigy;
			repaint();
		}
		else if (e.key === "Shift") {
			const pos = element_position[dragging.id];
			[pos.x, pos.y] = snap_to_elements(dragging, pos.x, pos.y, e.shiftKey);
			repaint();
		}
	}
}

canvas.addEventListener("pointerup", e => {
	if (!dragging) return;
	e.target.releasePointerCapture(e.pointerId);
	if (!clicking) {
		const pos = element_position[dragging.id];
		[pos.x, pos.y] = snap_to_elements(dragging, e.offsetX - dragbasex, e.offsetY - dragbasey, e.shiftKey);
		ws_sync.send({cmd: "move_element", scene: curscene, id: dragging.id, x: pos.x, y: pos.y, clientid});
	}
	dragging = null;
	repaint();
});

on("dblclick", "canvas", e => {
	const el = element_at_position(e.offsetX, e.offsetY);
	if (!el) return;
	edit_element("elements", el.id);
});

function EDITBUTTON(cat, id) {
	return BUTTON({class: "editelement", "data-cat": cat, "data-element": id},
		mutation_allowed ? "🖉" : "📄"); //It's the same button, but if mutation's not allowed, don't imply the potential to edit
}

export function render(data) {
	if (data.move_element) {
		//Reduced update that just moves one element.
		if (data.cause === clientid) return; //It's our own message. Ignore it (avoids rubberbanding if you drop and regrab an element).
		if (!state.scenes) return; //We don't have everything loaded yet, we'll get data soon
		element_position[data.id] = data.move_element;
		if (data.scene === curscene) repaint();
		return;
	}
	state = data; //Yes, this will include state.cmd == "update", no big deal
	if (state.deleted) return replace_content("#status", "Mockup deleted.");
	if (state.scenes && !state.scenes[curscene]) {
		//You aren't on any scene. Pick one. TODO: Have a "default scene" selector somewhere.
		curscene = Object.keys(state.scenes)[0];
	}
	element_position = state.scenes[curscene].elements;
	if (!element_position) element_position = state.scenes[curscene].elements = { };
	//This feels inefficient. Doing all this work every time anything changes, when it only
	//needs to be updated when a scene is added/removed/renamed, seems like overkill. *sigh*
	replace_content("#sceneselector",
		Object.entries(state.scenes).map(e => [e[0], e[1].title])
		.sort((a, b) => a[1].localeCompare(b[1]))
		.map(e => OPTION({value: e[0]}, e[1]))
	).value = curscene;
	replace_content("#scenebuttons", [
		EDITBUTTON("scenes", curscene),
		mutation_allowed && BUTTON({id: "new_scene", title: "Add new scene"}, "+"),
	]);
	DOM("#editelementdlg [type=submit]").hidden = !mutation_allowed;
	//Note that #deleteelement isn't hidden/unhidden here as it's done dynamically by category
	replace_content("#editelementdlg h3", mutation_allowed ? "Edit element" : "Element details");
	DOM("#elementtitle").readOnly = !mutation_allowed;
	DOM("#elementdesc").readOnly = !mutation_allowed;
	if (state.title) replace_content("#mockups", [ //This is the "# Mockups" default heading :)
		state.title, " ", EDITBUTTON("mockup", "*"),
	]);
	replace_content("#elementlist", [
		UL(Object.entries(state.elements).map(e => [e[0], e[1].title])
			.sort((a, b) => a[1].localeCompare(b[1]))
			.map(e => LI({"data-id": e[0]}, [e[1], " ", EDITBUTTON("elements", e[0])]))),
		mutation_allowed && DIV(BUTTON({class: "editelement", "data-cat": "elements", "data-element": ""}, "Add\xa0element")),
	]);
	DOM("#pixelartlink").hidden = !mutation_allowed || !ws_sync.get_userid();
	repaint();
}

on("change", "#sceneselector", e => {curscene = e.match.value; render(state);});

let editing_cat = null, editing_element = null;
function edit_element(cat, elemid) {
	editing_cat = cat;
	editing_element = elemid;
	const elem =
		editing_cat === "mockup" ? state //Category "mockup" has no ID, you are editing the mockup as a whole
		: editing_element === "" ? { } //Blank means "create new". Should there be defaults?
		: state[editing_cat][editing_element]; //Otherwise the cat is a key within the state, eg "elements" or "scenes"
	//Hide the delete button when you're looking at the overall mockup but you
	//aren't the creator. The back end only allows the creator to delete it.
	//(You also, unsurprisingly, can't delete if you can't mutate, nor can you
	//delete something that's new and not yet saved.)
	DOM("#deleteelement").hidden = !mutation_allowed || editing_element === "" || (editing_cat === "mockup" && ws_sync.get_userid() !== +state.created_by);
	DOM("#imageselect").hidden = DOM("#positionselect").hidden = editing_cat !== "elements";
	if (elem.image) {
		DOM("#imageselector").value = elem.image;
		const img = meta.icons[elem.image];
		if (img) {DOM("#xsize").value = img.xsize || 1; DOM("#ysize").value = img.ysize || 1;}
	}
	if (elem.xsize) DOM("#xsize").value = elem.xsize;
	if (elem.ysize) DOM("#ysize").value = elem.ysize;
	DOM("#bgselect").hidden = editing_cat !== "mockup";
	if (elem.bg) DOM("#bgselector").value = elem.bg;
	DOM("#elementtitle").value = elem.title || "";
	DOM("#elementdesc").value = elem.description || "";
	replace_content("#scenename", state.scenes[curscene].title || curscene);
	DOM("#elementlocked").checked = !!element_position[elemid]?.locked;
	DOM("#editelementdlg").showModal();
}

on("click", ".editelement", e => edit_element(e.match.dataset.cat, e.match.dataset.element));
//When you lock/unlock an element, DON'T send the client ID - we'll hear the echo-back and update locked status correctly.
on("click", "#elementlocked", e => ws_sync.send({cmd: "move_element", scene: curscene, id: editing_element, locked: e.match.checked}));

//TODO: On change of #imageselector, set xsize and ysize to its size, but only if the user hasn't customized the size already

on("submit", "#editelementdlg form", e => ws_sync.send({cmd: "update_element",
	cat: editing_cat, id: editing_element,
	image: DOM("#imageselector").value, //Irrelevant unless cat is "elements"
	xsize: DOM("#xsize").value, ysize: DOM("#ysize").value,
	bg: DOM("#bgselector").value, //Irrelevant unless cat is "mockup"
	title: DOM("#elementtitle").value,
	description: DOM("#elementdesc").value,
}));

on("click", "#new_scene", e => ws_sync.send({cmd: "new_scene"}));
export function sockmsg_select_scene(msg) {curscene = msg.id;} //Will take effect next update (which should be following shortly)

//This is capable of deleting a lot of different things. It may need a special case for the biggest
//things (scenes and the mockup itself) to have the user key in a thing.
on("click", "#deleteelement", simpleconfirm(
	e => editing_cat === "mockup" ? "Are you sure you want to delete THE ENTIRE MOCKUP? This is irreversible!"
		: editing_cat === "scenes" ? "Are you sure you want to delete the scene '" + state.scenes[editing_element].title + "'? This is irreversible!"
		: "Are you sure you want to delete this? This is irreversible.",
	e => {
		ws_sync.send({cmd: "update_element", cat: editing_cat, id: editing_element, "_delete": 1});
		DOM("#editelementdlg").close();
	})
);

on("mouseover", "#elementlist [data-id]", e => {hoverelement = e.match.dataset.id; repaint();});
on("mouseout", "#elementlist", e => {hoverelement = null; repaint();});
