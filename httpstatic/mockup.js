//NOTE: This file only handles the actual mockup rendering.
//For the landing page and pixel art, both of which are also on /mockup,
//see mockup_landing.js and mockup_pixelart.js respectively.
import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BR, BUTTON, DIV, INPUT, LABEL, LEGEND, LI, OPTION, "svg:path": PATH, SPAN, "svg:svg": SVG, "svg:symbol": SYMBOL, UL, "svg:use": USE} = lindt; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

const clientid = Math.random() + "." + Math.random(); //If an update is caused by us, we ignore it

const SNAP_DISTANCE = 10; //Distance to permit snapping (pixels)
const SNAP_RANGE = SNAP_DISTANCE * SNAP_DISTANCE; //The distance squared is more useful in arithmetic
let curscene = "";
let state = { };
let element_position = { }; //Shorthand: element_position <=> state.scenes[curscene].elements
let element_transform = { }; //Transformation matrix for this element. Transform a point through this matrix to convert element-relative coordinates to canvas-relative.
let element_transform_inverse = { }; //Inverted transformation matrix for this element.
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

//Easier to do this in JS than Markdown, though currently it is fixed (aside from #scenename that gets independently updated).
replace_content("#positionselect", [
	LEGEND([
		"Position in ",
		SPAN({id: "scenename"}),
	]),
	LABEL([
		"Locked (undraggable) ",
		INPUT({type: "checkbox", id: "elementlocked"}),
		SVG({id: "lockopen", fill: "black", version: "1.1", xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 512 512", "enable-background": "new 0 0 512 512"}, [
			PATH({d: "m375,11c-66.3,0-120.2,53.9-120.2,120.1v64.1h-177.4c-33.4,0-60.5,27.1-60.5,60.5v184.7c0,33.4 27.2,60.5 60.5,60.5h227.8c33.4,0 60.5-27.1 60.5-60.5v-184.6c0-33.4-27.1-60.5-60.5-60.5h-9.5v-64.1c0-43.7 35.6-79.3 79.3-79.3 43.7,0 79.3,35.6 79.3,79.3v84.5c0,11.3 9.1,20.4 20.4,20.4s20.4-9.1 20.4-20.4v-84.5c0.1-66.3-53.8-120.2-120.1-120.2zm-50.2,244.8v184.7c0,10.8-8.8,19.7-19.7,19.7h-227.7c-10.9,0-19.7-8.8-19.7-19.7v-184.7c0-10.9 8.8-19.7 19.7-19.7h227.8c10.8-2.84217e-14 19.6,8.8 19.6,19.7z"}),
			PATH({d: "m191.3,430c11.3,0 20.4-9.1 20.4-20.4v-40.1c0-11.3-9.1-20.4-20.4-20.4-11.3,0-20.4,9.1-20.4,20.4v40.1c-0.1,11.3 9.1,20.4 20.4,20.4z"}),
		]),
		SVG({id: "lockclosed", fill: "black", version: "1.1", xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 512 512", "enable-background": "new 0 0 512 512"}, [
			PATH({d: "m399.7,460.2h-287.4v-215.6h287.3v215.6h0.1zm-234-318c0-49.8 40.5-90.3 90.3-90.3 49.8,0 90.3,40.5 90.3,90.3v61.6h-180.6v-61.6zm254.4,61.6h-32.9v-61.6c-5.68434e-14-72.4-58.9-131.2-131.2-131.2-72.3,0-131.2,58.8-131.2,131.2v61.6h-32.9c-11.3,0-20.4,9.1-20.4,20.4v256.4c0,11.3 9.1,20.4 20.4,20.4h328.1c11.3,0 20.4-9.1 20.4-20.4v-256.4c0.1-11.3-9.1-20.4-20.3-20.4z"}),
			PATH({d: "m256,420c11.3,0 20.4-9.1 20.4-20.4v-36.7c0-11.3-9.1-20.4-20.4-20.4s-20.4,9.1-20.4,20.4v36.7c2.84217e-14,11.2 9.1,20.4 20.4,20.4z"}),
		]),
	]), BR(),
	LABEL([
		"Angle: ",
		INPUT({type: "number", id: "angle"}),
		"degrees",
	]),
]);
let grabmode = "move";
replace_content("#modeselector", [
	"Mode: ",
	LABEL({title: "Move single element"}, [
		INPUT({type: "radio", name: "modeselector", checked: true, onclick: () => grabmode = "move"}),
		SVG({viewBox: "0 0 24 24", fill: "none", xmlns: "http://www.w3.org/2000/svg"}, [
			SYMBOL({id: "movearrow"},
				PATH({d: "M5 9L2 12M2 12L5 15M2 12H22M9 5L12 2M12 2L15 5M12 2V22M15 19L12 22M12 22L9 19M19 9L22 12M22 12L19 15", "stroke-width": "1"}),
			),
			USE({href: "#movearrow", stroke: "#000000"}),
		]),
	]),
	LABEL({title: "Move group of elements"}, [
		INPUT({type: "radio", name: "modeselector", onclick: () => grabmode = "multimove"}),
		SVG({viewBox: "0 0 24 24", xmlns: "http://www.w3.org/2000/svg"}, [
			//Place the shadowed ones first, with the main one last so it overdraws as needed
			USE({href: "#movearrow", x: "3", y: "3", stroke: "#888888"}),
			USE({href: "#movearrow", x: "1", y: "1", stroke: "#888888"}),
			USE({href: "#movearrow", x: "-1", y: "-1", stroke: "#000000"}), //The "real" one is in solid black, and is slightly moved from where the single-move arrow goes
		]),
	]),
	LABEL({title: "Rotate single element"}, [
		INPUT({type: "radio", name: "modeselector", onclick: () => grabmode = "rotate"}),
		SVG({viewBox: "0 0 24 24", xmlns: "http://www.w3.org/2000/svg"}, [
			SYMBOL({id: "rotatearrows", "stroke-width": "1", fill: "none"}, [
				PATH({d: "M22 12l-3 3-3-3"}),
				PATH({d: "M2 12l3-3 3 3"}),
				PATH({d: "M19.016 14v-1.95A7.05 7.05 0 0 0 8 6.22"}),
				PATH({d: "M16.016 17.845A7.05 7.05 0 0 1 5 12.015V10"}),
				PATH({"stroke-linecap": "round", d: "M5 10V9"}),
				PATH({"stroke-linecap": "round", d: "M19 15v-1"}),
			]),
			USE({href: "#rotatearrows", stroke: "#000000"}),
		])
	]),
	LABEL({title: "Rotate group of elements"}, [
		INPUT({type: "radio", name: "modeselector", onclick: () => grabmode = "multirotate"}),
		SVG({viewBox: "0 0 24 24", xmlns: "http://www.w3.org/2000/svg"}, [
			USE({href: "#rotatearrows", x: "2", y: "2", stroke: "#888888"}),
			USE({href: "#rotatearrows", x: "0.5", y: "0.5", stroke: "#888888"}),
			USE({href: "#rotatearrows", x: "-1", y: "-1", stroke: "#000000"}),
		])
	]),
]);
		
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
let dragging = null, dragbasex = 50, dragbasey = 10, dragorigx, dragorigy, draggroup = [];
let clicking = false;
const elements_by_zorder = [];

function element_matrix(x, y, xsize, ysize, angle) {
	//The object's position defines its midpoint, which is also the point
	//around which it rotates.
	//Rotation is negated because it feels better that way.
	//CAUTION: When rotating a canvas, the angle is specified in radians. When
	//rotating a matrix, though, it's in degrees. Don't get caught out.
	return (new DOMMatrixReadOnly()
		.translate(x, y)
		.rotate(-(angle||0))
		.translate(-xsize / 2, -ysize / 2)
	);
}

function draw_element(ctx, el, dx, dy, dtheta) {
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
	element_transform[el.id] = element_matrix(pos.x + (dx||0), pos.y + (dy||0), el.xsize, el.ysize, (pos.angle||0) + (dtheta||0));
	element_transform_inverse[el.id] = element_transform[el.id].inverse();
	ctx.setTransform(element_transform[el.id]);
	//Now that we have the transformation matrix set, all drawing is done at the origin.
	ctx.drawImage(img, 0, 0, el.xsize, el.ysize);
	if (dragging && ((pos.angle||0) - (element_position[dragging.id].angle||0)) % 90 === 0) {
		//If you're dragging something that is oriented compatibly to this one, draw snap markers.
		ctx.strokeRect(0, 0, el.xsize, el.ysize);
		//TODO: Do partial circles for the corners, only drawing the part outside
		for (let x = 0; x < 3; ++x) {
			for (let y = 0; y < 3; ++y) {
				ctx.beginPath();
				ctx.fillStyle = ctx.strokeStyle = x === 1 && y === 1 ? "cyan" : "blue"
				ctx.arc(el.xsize * x / 2, el.ysize * y / 2, 3, 0, 2 * Math.PI);
				ctx.fill();
			}
		}
	}
	if (el.id === hoverelement) {
		ctx.save();
		ctx.setLineDash([1, 1]);
		ctx.strokeStyle = "rebeccapurple";
		ctx.strokeRect(0, 0, el.xsize, el.ysize);
		ctx.restore();
	}
	ctx.restore();
	//If parent-child relationships are implemented, draw all this element's children
}

function repaint() {
	element_transform = { }; element_transform_inverse = { };
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
		if (!el.parent && el !== dragging && !draggroup.some(g => g.id === id)) draw_element(ctx, el);
	});
	//Anything being dragged gets drawn last, ensuring it is at the top of z-order.
	if (dragging) {
		const pos = element_position[dragging.id];
		if (grabmode === "multimove") {
			const dx = pos.x - dragorigx, dy = pos.y - dragorigy;
			draggroup.forEach(el => draw_element(ctx, el, dx, dy));
		} else if (grabmode === "multirotate") {
			//TODO: Rotate the grouped elements around the center of the *grabbed* element,
			//not around their own centers.
			const dtheta = pos.angle - dragorigx;
			draggroup.forEach(el => draw_element(ctx, el, 0, 0, dtheta));
		}
		draw_element(ctx, dragging); //With the thing you're actually holding at the very top
	}
}

function element_at_position(x, y, filter) {
	//Iterate through all elements, starting at the top of the z-order stack and going
	//to the bottom; the first one found containing the given position is returned.
	const point = new DOMPointReadOnly(x, y);
	for (let i = elements_by_zorder.length - 1; i >= 0; --i) {
		//TODO: Handle rotated clipping rectangles
		const el = elements_by_zorder[i];
		const p = point.matrixTransform(element_transform_inverse[el.id]);
		if (p.x >= 0 && p.y >= 0 && p.x < el.xsize && p.y < el.ysize && (!filter || filter(el))) return el;
	}
}

canvas.addEventListener("pointerdown", e => {
	if (e.button) return; //Only left clicks
	if (!mutation_allowed) return;
	e.preventDefault();
	dragging = null; draggroup = [];
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
	if (grabmode === "rotate" || grabmode === "multirotate") {
		//Duplicates work done by element_at_position but whatevs
		const point = new DOMPointReadOnly(e.offsetX, e.offsetY);
		const p = point.matrixTransform(element_transform_inverse[el.id]);
		//Reusing the x coordinate to store the angle - close enough
		dragbasex = Math.atan2(p.y - el.ysize / 2, p.x - el.xsize / 2) * -180 / Math.PI - (pos.angle||0);
		dragbasey = element_transform_inverse[el.id];
		dragorigx = pos.angle || 0;
	}
	draggroup = []; //In single modes, will always be empty; in multi modes, has zero or more additional elements to be moved around.
	if (grabmode === "multimove" || grabmode === "multirotate") {
		//Determine the current element group.
		//Elements are in the group if:
		//1) They are not locked
		//2) They are angled compatibly with the current element
		//3) They are snapped together.
		//To recognize elements that are snapped together, it is sufficient to test if they would
		//edge snap, as corner snapping will have them match on edges. Note that proximity is not
		//significant here, as snapped elements will have zero distance.
		//An element gets added to the group if it is snapped to any element already in the group,
		//and this grouping is transitive.
		//FIXME: This does not currently work correctly for rotated elements, for the same reason
		//that edge snapping itself doesn't. Fix both at once.
		const group = {[el.id]: el};
		let newgroup = [el];
		const angle = pos.angle || 0;
		while (newgroup.length) {
			const nextgroup = [];
			//Scan all elements to see if any of them snap to anything in newgroup.
			//We don't need to check what's in group, as they've already been checked against those.
			//Any new additions get added to nextgroup so they'll get checked as well.
			for (let el1 of elements_by_zorder) for (let el2 of newgroup) {
				if (group[el1.id]) continue; //Already in group, ignore it
				if (((element_position[el1.id].angle||0) - angle) % 90 !== 0) continue;
				found: for (let e1 = 0; e1 <= 1; ++e1) for (let e2 = 0; e2 <= 1; ++e2) {
					const p1 = new DOMPointReadOnly(e1 * el1.xsize, e1 * el1.ysize).matrixTransform(element_transform[el1.id]);
					const p2 = new DOMPointReadOnly(e2 * el2.xsize, e2 * el2.ysize).matrixTransform(element_transform[el2.id]);
					if (p1.x === p2.x || p1.y === p2.y) {
						group[el1.id] = el1;
						nextgroup.push(el1);
						draggroup.push(el1);
						break found;
					}
				}
			}
			newgroup = nextgroup;
		}
	}
});

//Corners and middles defined as proportions of the width/height
//[x fraction, y fraction, affinity]
const corners = [
	[0.0, 0.0, 1], [0.5, 0.0, 1], [1.0, 0.0, 1],
	[0.0, 0.5, 1], [0.5, 0.5, 2], [1.0, 0.5, 1],
	[0.0, 1.0, 1], [0.5, 1.0, 1], [1.0, 1.0, 1],
];

function snap_to_elements(baseelem, xpos, ypos, moresnap) {
	//NOTE: Previously we were doing a fast check against the bounding box before doing the full checks.
	//This is not currently happening, but if an axis-aligned bounding box is retained, this could allow
	//us to save some effort. Currently doing the full snap check against every element.
	const angle = element_position[baseelem.id].angle || 0;
	const basexfrm = element_matrix(xpos, ypos, baseelem.xsize, baseelem.ysize, angle);
	for (let el of elements_by_zorder) {
		if (el.id === baseelem.id) continue; //Don't snap to yourself
		if (draggroup.some(g => g.id === el.id)) continue; //Don't snap to something you're already carrying
		const pos = element_position[el.id];
		if (((pos.angle||0) - angle) % 90 !== 0) continue; //Only snap to things that are oriented compatibly

		//I could, in theory, make this more efficient. For now I won't bother. Let's go through some
		//possible snapping arrangements.
		for (let c1 of corners) for (let c2 of corners) {
			//Go through all nine corners and middles of each element. See if there's a good
			//snap to be found.
			//Normal snapping: The center only snaps to another center, but corners and
			//edge middles all snap to each other.
			//If any-snapping is active, affinities are ignored
			if (!moresnap && c1[2] !== c2[2]) continue;
			const p1 = new DOMPointReadOnly(c1[0] * baseelem.xsize, c1[1] * baseelem.ysize).matrixTransform(basexfrm);
			const p2 = new DOMPointReadOnly(c2[0] * el.xsize, c2[1] * el.ysize).matrixTransform(element_transform[el.id]);
			if ((p1.x - p2.x) ** 2 + (p1.y - p2.y) ** 2 <= SNAP_RANGE) {
				//Alright! Let's snap to that. So, how do we need to move in order
				//to place (x1, y1) onto (x2, y2)? Move the base position that far.
				return [xpos + p2.x - p1.x, ypos + p2.y - p1.y];
			}
		}
		//If we didn't find a corner to snap to, try snapping to an edge instead.
		//There are four edges, but each one only snaps to two (you don't snap the
		//top of one thing to the left of another).
		for (let e1 = 0; e1 <= 1; ++e1) for (let e2 = 0; e2 <= 1; ++e2) {
			const p1 = new DOMPointReadOnly(e1 * baseelem.xsize, e1 * baseelem.ysize).matrixTransform(basexfrm);
			const p2 = new DOMPointReadOnly(e2 * el.xsize, e2 * el.ysize).matrixTransform(element_transform[el.id]);
			//if (x1 - x2 <= SNAP_DISTANCE && x2 - x1 <= SNAP_DISTANCE) //Is it better to do two comparisons, to call Math.abs(), or to square the number?
			if ((p1.x - p2.x) ** 2 <= SNAP_RANGE) { //Going with squaring for consistency with the corner snaps.
				//Horizontal snapping (to a vertical edge)
				//First, check if the top and/or bottom corner of the base element can be found
				//within the size of the target. Two-step coordinate transform: first take (x, 0)
				//and (x, ysize) and translate them into physical coordinates, then translate those
				//into other-element-relative. The x coordinate post-transformation will be close to
				//our current location, and one of the y coordinates needs to be within the size of
				//the target element.
				const top = new DOMPointReadOnly(e1 * baseelem.xsize, 0).matrixTransform(basexfrm).matrixTransform(element_transform_inverse[el.id]);
				const bot = new DOMPointReadOnly(e1 * baseelem.xsize, baseelem.ysize).matrixTransform(basexfrm).matrixTransform(element_transform_inverse[el.id]);
				if ((top.y >= 0 && top.y <= el.ysize) || (bot.y >= 0 && bot.y <= el.ysize))
					//TODO: Figure out how to slew along the angle to meet the target. Currently
					//this isn't perfect when the elements are tilted.
					return [xpos + p2.x - p1.x, ypos];
				//If it's outside range, keep looking - there might be other matches.
			}
			if ((p1.y - p2.y) ** 2 <= SNAP_RANGE) {
				//Vertical snapping (to a horizontal edge), correspondingly.
				const lef = new DOMPointReadOnly(0, e1 * baseelem.ysize).matrixTransform(basexfrm).matrixTransform(element_transform_inverse[el.id]);
				const rig = new DOMPointReadOnly(baseelem.xsize, e1 * baseelem.ysize).matrixTransform(basexfrm).matrixTransform(element_transform_inverse[el.id]);
				if ((lef.x >= 0 && lef.x <= el.xsize) || (rig.x >= 0 && rig.x <= el.xsize))
					return [xpos, ypos + p2.y - p1.y];
			}
		}
	}
	return [xpos, ypos];
}

function update_drag_position(x, y, moresnap) {
	const pos = element_position[dragging.id];
	if (grabmode === "move" || grabmode === "multimove") {
		[pos.x, pos.y] = snap_to_elements(dragging, x - dragbasex, y - dragbasey, moresnap);
		return {x: pos.x, y: pos.y};
	} else if (grabmode === "rotate" || grabmode === "multirotate") {
		//TODO: Support snapping for rotation - snap to the angle of a nearby element.
		const point = new DOMPointReadOnly(x, y);
		const p = point.matrixTransform(dragbasey);
		let angle = Math.atan2(p.y - dragging.ysize / 2, p.x - dragging.xsize / 2) * -180 / Math.PI - dragbasex;
		//Quantize to a reduced set of available angles.
		angle -= angle % (moresnap ? 5 : 22.5);
		pos.angle = angle;
		return {angle: pos.angle};
	}
}

canvas.addEventListener("pointermove", e => {
	clicking = false;
	let cursor = "default";
	if (dragging) {
		cursor = "grabbing";
		update_drag_position(e.offsetX, e.offsetY, e.shiftKey);
		repaint();
	}
	else {
		const el = element_at_position(e.offsetX, e.offsetY);
		if (el && !element_position[el.id].locked) cursor = "grab";
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
			dragging = null; draggroup = [];
			if (grabmode === "move" || grabmode === "multimove") {pos.x = dragorigx; pos.y = dragorigy;}
			else if (grabmode === "rotate" || grabmode === "multirotate") pos.angle = dragorigx;
			repaint();
		}
		else if (e.key === "Shift") {
			const pos = element_position[dragging.id];
			if (grabmode === "move" || grabmode === "multimove")
				update_drag_position(pos.x, pos.y, e.shiftKey);
			//Not sure if pressing/releasing shift will do anything in rotation mode
			//If it does, we'll need to retain the coordinates, or synthesize them from the current angle
			//Currently, if you press/release shift while rotating, you have to move the mouse
			//a smidge to recalculate.
			repaint();
		}
	}
}

canvas.addEventListener("pointerup", e => {
	if (!dragging) return;
	e.target.releasePointerCapture(e.pointerId);
	if (!clicking) {
		const updates = update_drag_position(e.offsetX, e.offsetY, e.shiftKey);
		ws_sync.send({cmd: "move_element", scene: curscene, id: dragging.id, ...updates, clientid});
		if (grabmode === "multimove") {
			//For every other object moved, move it by the same vector.
			const dx = updates.x - dragorigx, dy = updates.y - dragorigy;
			for (let el of draggroup) {
				const pos = element_position[el.id];
				pos.x += dx; pos.y += dy;
				ws_sync.send({cmd: "move_element", scene: curscene, id: el.id, x: pos.x, y: pos.y, clientid});
			}
		} else if (grabmode === "multirotate") {
			//TODO: Reify the same rotation done by repaint
			for (let el of draggroup) {
				const pos = element_position[el.id];
				pos.angle = updates.angle;
				ws_sync.send({cmd: "move_element", scene: curscene, id: el.id, angle: pos.angle, clientid});
			}
		}
	}
	dragging = null; draggroup = [];
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
	DOM("#angle").value = element_position[elemid]?.angle || 0;
	DOM("#editelementdlg").showModal();
}

on("click", ".editelement", e => edit_element(e.match.dataset.cat, e.match.dataset.element));
//When you move an element via the dialog, DON'T send the client ID - we'll hear the echo-back and update locked status correctly.
on("click", "#elementlocked", e => ws_sync.send({cmd: "move_element", scene: curscene, id: editing_element, locked: e.match.checked}));
on("change", "#angle", e => ws_sync.send({cmd: "move_element", scene: curscene, id: editing_element, angle: e.match.value|0}));

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
