import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, BR, BUTTON, DETAILS, SUMMARY, DIV, FORM, INPUT, OPTION, OPTGROUP, SELECT, TABLE, TR, TH, TD} = choc;
import update_display from "$$static||monitor.js$$";
import {waitlate} from "$$static||utils.js$$";

/*
New plan: Bring graphical monitors into this module where they belong.
The main display will have:
* ID, invisible
* Preview (currently hidden)
* Edit button
* Delete button
* OBS-draggable link

All editing will be in a dialog.
*/

const editables = { };
function set_values(nonce, info, elem) {
	if (!info) return 0;
	const runmode = !elem.dataset || !elem.dataset.nonce;
	for (let attr in info) {
		editables[nonce][attr] = info[attr];
		if (attr === "text" && info.type === "goalbar" && runmode) { //FIXME: Probably broken after some other changes
			//For run distance, fracture this into the variable name and the actual text.
			const m = /^\$([^:$]+)\$:(.*)/.exec(info.text);
			console.log(info.text);
			console.log(m);
			elem.querySelector("[name=varname]").value = m[1];
			elem.querySelector("[name=text]").value = m[2];
			continue;
		}
		const el = elem.querySelector("[name=" + attr + "]");
		if (el) el.value = info[attr];
		if (attr === "lvlupcmd" && el) //Special case: the value might not work if stuff isn't loaded yet.
			el.dataset.wantvalue = info[attr]
	}
	if (runmode && info.type === "goalbar") {
		elem.querySelector("[name=currentval]").value = info.display.split(":")[0];
		window.update_milepicker();
	}
	const preview = elem.querySelector(".preview");
	if (preview) {
		update_display(preview, info);
		if (info.previewbg) elem.querySelector(".preview-bg").style.backgroundColor = info.previewbg;
	}
	return elem;
}

export const render_parent = DOM("#monitors tbody");
export function render_item(msg, obj) {
	const nonce = msg.id;
	if (!editables[nonce]) editables[nonce] = { };
	return set_values(nonce, msg, obj || TR({"data-nonce": nonce, "data-id": nonce}, [
		TD(DIV({className: "preview-frame"}, DIV({className: "preview-bg"}, DIV({className: "preview"})))),
		TD([
			BUTTON({type: "button", className: "editbtn"}, "Edit"),
			BUTTON({type: "button", className: "deletebtn", "data-nonce": nonce}, "Delete?"),
		]),
		TD(A({className: "monitorlink", href: "monitors?view=" + nonce}, "Drag me to OBS")),
	]));
}
export function render_empty() {
	render_parent.appendChild(TR([
		TD({colSpan: 4}, "No monitors defined. Create one!"),
	]));
}
export function render(data) { }

set_content("#edittext form div", TABLE({border: 1}, [
	TR([TD("Text:"), TD(INPUT({size: 40, name: "text"}))]),
	TR([
		TD("Font:"),
		TD([
			INPUT({name: "font", size: "28"}),
			SELECT({name: "fontweight"}, [OPTION("normal"), OPTION("bold")]),
			SELECT({name: "fontstyle"}, [OPTION("normal"), OPTION("italic")]),
			INPUT({name: "fontsize", type: "number", size: "3", value: "16"}),
		])
	]),
	TR([TD(), TD(["Pick a font from Google Fonts or", BR(), "one that's already on your PC."])]),
	TR([TD("Text color:"), TD(INPUT({name: "color", type: "color"}))]),
	TR([TD("Border:"), TD([
		"Width (px):", INPUT({name: "borderwidth", type: "number"}),
		"Color:", INPUT({name: "bordercolor", type: "color"}),
	])]),
	//TODO: Gradient?
	//TODO: Drop shadow?
	//TODO: Padding? Back end already supports padvert and padhoriz.
	TR([TD("Formatting:"), TD(SELECT({name: "whitespace"}, [
		OPTGROUP({label: "Single line"}, [
			OPTION({value: "normal"}, "Wrapped"),
			OPTION({value: "nowrap"}, "No wrapping"),
		]),
		OPTGROUP({label: "Multi-line"}, [
			OPTION({value: "pre-line"}, "Normal"),
			OPTION({value: "pre"}, "Keep indents"),
			OPTION({value: "pre-wrap"}, "No wrapping"),
		]),
	]))]),
	TR([TD("Custom CSS:"), TD(INPUT({name: "css", size: 40}))]),
]));

on("submit", "#edittext form", async e => {
	console.log(e.match.elements);
	const nonce = e.match.dataset.nonce;
	const body = {nonce};
	("text " + css_attributes).split(" ").forEach(attr => {
		if (!e.match.elements[attr]) return;
		body[attr] = e.match.elements[attr].value;
		if (nonce === "") e.match.elements[attr].value = "";
	});
	const res = await fetch("monitors", {
		method: "PUT",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify(body),
	});
	if (!res.ok) console.error("Something went wrong in the save, check console"); //TODO: Report errors properly
});

on("click", "#add_text", e => {
	//TODO: Replace this with a ws message
	fetch("monitors", {method: "PUT", headers: {"Content-Type": "application/json"}, body: '{"text": ""}'});
});

on("change", "[name=previewbg]", e => {
	e.match.closest("tr").querySelector(".preview-bg").style.backgroundColor = e.match.value;
});

on("click", ".editbtn", e => {
	const nonce = e.match.closest("tr").dataset.id;
	const mon = editables[nonce];
	const dlg = DOM("#edittext"); //TODO: Change this based on mon.type
	set_values(nonce, mon, dlg); //TODO: Break set_values into the part done on update and the part done here
	DOM("#edittext form").dataset.nonce = nonce;
	dlg.returnValue = "close";
	dlg.showModal();
});

on("click", ".deletebtn", waitlate(1000, 7500, "Really delete?", async e => {
	const nonce = e.match.dataset.nonce;
	console.log("Delete.");
	const res = await fetch("monitors", {
		method: "DELETE",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify({nonce}),
	});
	if (!res.ok) console.error("Something went wrong in the save, check console"); //TODO: Report errors properly
}));

on("dragstart", ".monitorlink", e => {
	const url = `${e.match.href}&layer-name=StilleBot%20monitor&layer-width=400&layer-height=120`;
	e.dataTransfer.setData("text/uri-list", url);
});
