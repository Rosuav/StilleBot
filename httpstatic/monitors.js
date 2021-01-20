import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, BR, BUTTON, DETAILS, SUMMARY, DIV, FORM, INPUT, OPTION, OPTGROUP, SELECT, TABLE, TR, TH, TD} = choc;
import update_display from "./monitor.js";

function set_values(info, elem) {
	if (!info) return 0;
	if (info.barcolor) return 0; //HACK: Disable accidental editing of bars. TODO: Link to ./run instead?
	for (let attr in info) {
		const el = elem.querySelector("[name=" + attr + "]");
		if (el) el.value = info[attr];
	}
	update_display(elem.querySelector(".preview"), info);
	if (info.previewbg) elem.querySelector(".preview-bg").style.backgroundColor = info.previewbg;
	return elem;
}

function update_monitors() {
	const rows = Object.keys(monitors).map(nonce => set_values(monitors[nonce], TR({"data-nonce": nonce}, [
		TD(INPUT({size: 40, name: "text", form: "upd_" + nonce})),
		TD(DETAILS([SUMMARY("Expand"), FORM({id: "upd_" + nonce}, TABLE([
			TR([
				TD("Font:"),
				TD([INPUT({name: "font", size: "30"}), INPUT({name: "fontsize", type: "number", size: "4", value: "16"})])
			]),
			TR([TD(), TD(["Pick a font from Google Fonts or", BR(), "one that's already on your PC."])]),
			TR([TD("Text color:"), TD(INPUT({name: "color", type: "color"}))]),
			//TODO: Gradient?
			//TODO: Border?
			//TODO: Drop shadow?
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
		]))])),
		TD([
			INPUT({type: "submit", value: "Save", form: "upd_" + nonce}),
			BUTTON({type: "button", className: "deletebtn", "data-nonce": nonce}, "Delete?"),
		]),
		TD(DETAILS({className: "preview-expander"}, [SUMMARY("Expand"),
			DIV([
				"Background color:",
				INPUT({name: "previewbg", form: "upd_" + nonce, type: "color"}),
				"(preview only)",
			]),
			DIV({className: "preview-frame"}, DIV({className: "preview-bg"}, DIV({className: "preview", id: "preview_" + nonce}))),
			DIV({className: "size"}, "Estimated size: (unknown)"),
		])),
		TD(A({className: "monitorlink", href: "monitors?view=" + nonce}, "Drag me to OBS")),
	])));
	const table = DOM("#monitors tbody");
	rows.unshift(table.firstChild);
	rows.push(table.lastElementChild);
	set_content(table, rows);
}
update_monitors();

on("submit", "#monitors form", async e => {
	e.preventDefault();
	console.log(e.match.elements);
	const nonce = e.match.id.slice(4);
	const body = {nonce};
	("text " + css_attributes).split(" ").forEach(attr => {
		if (!e.match.elements[attr]) return;
		body[attr] = e.match.elements[attr].value;
		if (nonce === "") e.match.elements[attr].value = "";
	});
	const res = await (await fetch("monitors", {
		method: "PUT",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify(body),
	})).json();
	monitors[res.nonce] = res.text; //May now be null, which will suppress the display
	//TODO: Update with less flicker in the common cases (eg not a deletion)
	update_monitors();
	update_display(DOM("#preview_" + nonce), {text: res.sample});
});

on("change", "[name=previewbg]", e => {
	e.match.closest("tr").querySelector(".preview-bg").style.backgroundColor = e.match.value;
});
on("change", "input,select", e => {
	//TODO: Map names the same way that update_display() does (see monitor.js)
	e.match.closest("tr[data-nonce]").querySelector(".preview").style[e.match.name] = e.match.value;
});
document.addEventListener("toggle", e => {
	if (!e.target.matches(".preview-expander")) return;
	const preview = e.target.querySelector(".preview");
	e.target.querySelector(".size").innerHTML = "Estimated size: " + preview.offsetWidth + " x " + preview.offsetHeight;
}, true); //Capturing phase only - event does not bubble.

const deleting = { };
on("click", ".deletebtn", async e => {
	const nonce = e.match.dataset.nonce;
	const confirm = deleting[nonce] || 0;
	if (confirm > +new Date) {
		//Actually delete
		console.log("Delete.");
		await fetch("monitors", {
			method: "DELETE",
			headers: {"Content-Type": "application/json"},
			body: JSON.stringify({nonce}),
		}); //TODO: Check that it succeeded
		monitors[nonce] = 0;
		update_monitors();
		return;
	}
	deleting[nonce] = 10000 + +new Date;
	e.match.innerHTML = "Confirm?";
	setTimeout(btn => btn.innerHTML = "Delete?", 10000, e.match);
});

on("dragstart", ".monitorlink", e => {
	const url = `${e.match.href}&layer-name=StilleBot%20monitor&layer-width=400&layer-height=120`;
	e.dataTransfer.setData("text/uri-list", url);
});
