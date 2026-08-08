import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {TD, TR} = lindt; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";
export function sockmsg_update_meta(msg) {meta = msg;}

//TODO: Store this in localStorage
const colors = [
	["#000000", "#0000ff", "#00ff00", "#ff0000", "#00ffff", "#ff00ff", "#ffff00", "#ffffff"],
	["#666666", "#000077", "#007700", "#770000", "#007777", "#770077", "#777700", "#cccccc"],
];

let curcolor = "#000000"; DOM("#curcolor").style.backgroundColor = curcolor;
const grid = [];
const xsize = 25, ysize = 25;
let dragging = null, line = { };
function repaint() {
	replace_content("#palette", colors.map(row => TR(row.map(col => TD({class: "pickcolor", "data-color": col, style: "background-color: " + col})))));
	if (grid.length > ysize) grid.length = ysize;
	while (grid.length < ysize) grid.push([]);
	for (let row of grid) {
		if (row.length > xsize) row.length = xsize;
		while (row.length < xsize) row.push("");
	}
	replace_content("#grid", grid.map((row, y) => TR(row.map((cell, x) => TD({
		style: "background-color: " + (line[x + "," + y] ? curcolor : cell || "transparent")
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

on("click", ".pickcolor", e => DOM("#curcolor").style.backgroundColor = (curcolor = e.match.dataset.color) || "transparent");

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

on("submit", "#saveimagedlg form", e => {
	ws_sync.send({cmd: "save_pixelart",
		name: e.match.elements.savename.value,
		grid,
	});
	e.match.reset();
});
