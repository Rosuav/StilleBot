import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, FORM, INPUT, TABLE, TR, TH, TD} = choc;

function update_monitors() {
	const rows = Object.keys(monitors).map(nonce => monitors[nonce] && TR([
		TD(FORM({id: "upd_" + nonce}, INPUT({size: 40, value: monitors[nonce], name: "text"}))),
		TD(INPUT({type: "submit", value: "Save", form: "upd_" + nonce})),
		//TODO: Actual delete button (not just "blank the text to delete")
		TD(A({href: "..."}, "Drag me to OBS")),
	]));
	const table = DOM("#monitors tbody");
	rows.unshift(table.firstChild);
	rows.push(table.lastElementChild);
	set_content(table, rows);
}
update_monitors();

on("submit", "#monitors form", async e => {
	e.preventDefault();
	console.log(e.match.elements);
	const text = e.match.elements.text.value;
	//if (text === "") error out, once we have a proper way to delete
	const nonce = e.match.id.slice(4);
	if (nonce === "") e.match.elements.text.value = "";
	console.log("Save this thing:");
	console.log(nonce, text);
	const res = await (await fetch("monitors", {
		method: "PUT",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify({nonce, text}),
	})).json();
	console.log(res);
	monitors[res.nonce] = res.text; //May now be null, which will suppress the display
	//TODO: Display res.sample somewhere
	update_monitors();
});
