import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, BR, BUTTON, DETAILS, SUMMARY, DIV, FORM, INPUT, OPTION, OPTGROUP, SELECT, TABLE, TR, TH, TD} = choc;
import update_display from "./monitor.js";

function update_milepicker() {
	const thresholds = DOM("[name=thresholds]").value.split(" ");
	const pos = +DOM("[name=currentval]").value;
	const opts = [];
	thresholds.push(Infinity); //Place a known elephant in Cairo
	let val = -1, total = 0;
	for (let which = 0; which < thresholds.length; ++which) {
		//Record the *previous* total as the mark for this mile. If you pick
		//mile 3, the total should be set to the *start* of mile 3.
		const desc = which === thresholds.length - 1 ? "And beyond!" : "Mile " + (which + 1);
		const prevtotal = total;
		total += 100 * +thresholds[which]; //What if thresholds[which] isn't numeric??
		opts.push(OPTION({value: prevtotal}, desc));
		if (val === -1 && pos < total) val = prevtotal;
	}
	set_content(DOM("[name=milepicker]"), opts).value = val;
}
DOM("[name=thresholds]").onchange = DOM("[name=currentval]").onchange = update_milepicker;
DOM("[name=milepicker]").onchange = e => DOM("[name=currentval]").value = e.currentTarget.value;
DOM("#setval").onclick = async e => {
	const val = +DOM("[name=currentval]").value;
	if (val !== val) return; //TODO: Be nicer
	const rc = await fetch("run", {
		method: "PUT",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify({"var": DOM("[name=varname]").value, val}),
	});
	if (!rc.ok) {console.error("Couldn't update (TODO)"); return;}
	update_display(DOM("#preview"), {}, val + ":" + DOM("[name=text]").value);
}

function set_values(info, elem, sample) {
	if (!info) return 0;
	for (let attr in info) {
		if (attr === "text") {
			//Fracture this into the variable name and the actual text
			const m = /^\$([^:$]+)\$:(.*)/.exec(info.text)
			elem.querySelector("[name=varname]").value = m[1];
			elem.querySelector("[name=text]").value = m[2];
			continue;
		}
		const el = elem.querySelector("[name=" + attr + "]");
		if (el) el.value = info[attr];
	}
	elem.querySelector("[name=currentval]").value = sample.split(":")[0];
	update_milepicker();
	update_display(DOM("#preview"), info, sample);
}
if (nonce) set_values(info, document, sample);

on("submit", "form", async e => {
	e.preventDefault();
	if (!nonce) return; //TODO: Be nicer
	console.log(e.match.elements);
	const body = {nonce};
	css_attributes.split(" ").forEach(attr => {
		if (!e.match.elements[attr]) return;
		body[attr] = e.match.elements[attr].value;
	});
	body.text = `$${e.match.elements.varname.value}$:${e.match.elements.text.value}`;
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
