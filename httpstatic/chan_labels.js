import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {LI, SPAN} = choc; //autoimport

export const render_parent = DOM("#activelabels");
export function render_item(lbl, el) {
	return LI({"data-id": lbl.id}, [
		lbl.timefmt && SPAN({class: "timefmt"}, "[" + lbl.timefmt + "] "), //TODO
		lbl.label,
		//TODO: Text formatting
	]);
}

export function render(data) {console.log(data)}
