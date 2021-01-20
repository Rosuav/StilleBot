import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, BR, BUTTON, DETAILS, SUMMARY, DIV, FORM, INPUT, OPTION, OPTGROUP, SELECT, TABLE, TR, TH, TD} = choc;
import update_display from "./monitor.js";

function set_values(info, elem, sample) {
	if (!info) return 0;
	for (let attr in info) {
		const el = elem.querySelector("[name=" + attr + "]");
		if (el) el.value = info[attr];
	}
	update_display(DOM("#preview"), info, sample);
}
if (nonce) set_values(info, document, sample);

on("submit", "form", async e => {
	e.preventDefault();
	if (!nonce) return; //TODO: Be nicer
	console.log(e.match.elements);
	const body = {nonce};
	("text " + css_attributes).split(" ").forEach(attr => {
		if (!e.match.elements[attr]) return;
		body[attr] = e.match.elements[attr].value;
	});
	info = await (await fetch("monitors", { //Uses same API backend as the main monitors page does
		method: "PUT",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify(body),
	})).json();
	set_values(info.text, document, info.sample);
});

on("change", "input,select", e => {
	//TODO: Map names the same way that update_display() does (see monitor.js)
	DOM("#preview").style[e.match.name] = e.match.value;
});

on("dragstart", ".monitorlink", e => {
	const url = `${e.match.href}&layer-name=StilleBot%20monitor&layer-width=120&layer-height=20`;
	e.dataTransfer.setData("text/uri-list", url);
});
