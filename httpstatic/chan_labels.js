import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {LI, SPAN, UL} = choc; //autoimport
import {TEXTFORMATTING, ensure_font, simpleconfirm} from "$$static||utils.js$$";

let countdown = null;
let csstext = "";

function format_time(timefmt, target) {
	let min = "";
	switch (timefmt) {
		case "": return "";
		case "mmss":
			min = ("0" + Math.floor(target / 60)).slice(-2) + ":";
			target %= 60;
		case "ss":
			return min + ("0" + target).slice(-2) + " ";
	}
}

function ticker() {
	const now = Math.floor(new Date() / 1000);
	let none_left = true;
	document.querySelectorAll(".timefmt").forEach(span => {
		const then = +span.dataset.bread;
		if (then < now) {span.parentElement.style.display = "none"; return;} //The server will probably remove it soon; until then, hide it.
		set_content(span, format_time(span.dataset.timefmt, span.dataset.bread - now));
		none_left = false;
	});
	if (none_left) {clearInterval(countdown); countdown = null;}
}

export const render_parent = DOM("#display").appendChild(UL({id: "activelabels"}));
export function render_item(lbl, el) {
	if (lbl.timefmt && !countdown) countdown = setInterval(ticker, 1000);
	return LI({"data-id": lbl.id, "style": csstext}, [
		lbl.timefmt && SPAN({class: "timefmt", "data-timefmt": lbl.timefmt, "data-bread": lbl.bread},
			format_time(lbl.timefmt, lbl.bread - Math.floor(new Date() / 1000))),
		lbl.label,
	]);
}


const fmtfrm = DOM("form");
if (fmtfrm) fmtfrm.prepend(TEXTFORMATTING({textname: "-"}));
export function render(data) {
	if (fmtfrm && data.style) for (let attr in data.style) {
		const elem = fmtfrm.querySelector("[name=" + attr + "]");
		if (elem) elem.value = data.style[attr] || "";
	}
	if (data.css) {
		csstext = data.css;
		render_parent.childNodes.forEach(el => el.style = csstext);
	}
	if (data.style && data.style.font) ensure_font(data.style.font);
}

on("submit", "form", e => {
	e.preventDefault();
	const msg = {cmd: "update"};
	for (let el of e.match.elements)
		if (el.name) msg[el.name] = el.value;
	ws_sync.send(msg);
});

on("dragstart", "#displaylink", e => {
	e.dataTransfer.setData("text/uri-list", `${e.match.href}&layer-name=On%20Screen%20Labels&layer-width=600&layer-height=400`);
});

on("click", "#revokeauth", simpleconfirm("Revoking this key will disable your in-OBS labels until you update the URL. Proceed?",
	e => ws_sync.send({cmd: "revokekey"})));
export function sockmsg_authkey(msg) {
	DOM("#displaylink").href = "labels?key=" + msg.key;
	msg.key = "<hidden>";
}
