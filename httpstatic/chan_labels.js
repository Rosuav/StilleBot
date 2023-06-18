import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {LI, SPAN} = choc; //autoimport

let countdown = null;

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
		if (then < now) {span.style.display = "none"; return;} //The server will probably remove it soon; until then, hide it.
		set_content(span, format_time(span.dataset.timefmt, span.dataset.bread - now));
		none_left = false;
	});
	if (none_left) {clearInterval(countdown); countdown = null; console.log("Ending ticker");}
}

export const render_parent = DOM("#activelabels");
export function render_item(lbl, el) {
	if (lbl.timefmt && !countdown) {console.log("Starting ticker"); countdown = setInterval(ticker, 1000);}
	return LI({"data-id": lbl.id}, [
		lbl.timefmt && SPAN({class: "timefmt", "data-timefmt": lbl.timefmt, "data-bread": lbl.bread},
			format_time(lbl.timefmt, lbl.bread - Math.floor(new Date() / 1000))),
		lbl.label,
		//TODO: Text formatting
	]);
}

export function render(data) {console.log(data)}
