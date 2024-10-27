import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BR, BUTTON, CODE, INPUT, LABEL, LI, OPTION, SELECT, SPAN, UL} = choc; //autoimport

export const autorender = {
	form_parent: DOM("#forms"),
	form(f) {return LI({"data-id": f.id}, [ //extcall
		f.id, " ", f.formtitle,
	]);},
	form_empty() {return DOM("#forms").appendChild(LI([
		"No forms yet - create one!",
	]));},
}

export function render(data) { }

on("click", "#createform", e => ws_sync.send({cmd: "createform"}));
