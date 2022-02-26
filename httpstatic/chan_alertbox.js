import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, AUDIO, BR, BUTTON, CODE, DIV, FIGCAPTION, FIGURE, FORM, H3, INPUT, LABEL, OPTION, P, SELECT, SPAN} = choc; //autoimport
import {TEXTFORMATTING} from "$$static||utils.js$$";

function THUMB(file) {
	if (!file.url) return DIV({className: "thumbnail"}, "uploading...");
	if (file.mimetype.startsWith("audio/")) return DIV({className: "thumbnail"}, AUDIO({src: file.url, controls: true}));
	return DIV({className: "thumbnail", style: "background-image: url(" + file.url + ")"});
}

const files = { };
const alerttypes = { };

//NOTE: Item rendering applies to uploaded files. Other things are handled by render() itself.
//NOTE: Since newly-uploaded files will always go to the end, this should always be sorted by
//order added, as a documented feature. The server will need to ensure this.
export const render_parent = DOM("#uploads");
export function render_item(file, obj) {
	//TODO: If obj, reduce flicker by reconfiguring it, without doing any changes to the
	//thumbnail if the URL hasn't changed.
	files[file.id] = file;
	return FIGURE({"data-id": file.id}, [
		THUMB(file),
		FIGCAPTION(A({href: file.url}, file.name)),
		BUTTON({type: "button", className: "confirmdelete", title: "Delete"}, "🗑"),
	]);
}

export function render(data) {
	if (data.authkey) DOM("#alertboxlink").href = "alertbox?key=" + data.authkey;
	if (data.alerttypes) Object.entries(data.alerttypes).forEach(([type, desc]) => {
		if (alerttypes[type]) return; //TODO: Update its description?
		DOM("#alertconfigs").appendChild(alerttypes[type] = FORM({className: "alertconfig", "data-type": type}, [
			H3(desc),
			P([
				SELECT({name: "format"}, OPTION({value: "text_under"}, "Text under image")),
				" (Currently only one option, more Coming Soon™)",
			]),
			P(LABEL([
				"Image: ",
				//TODO: Have a thing that will enable a "Choose" button in the FIGURE section above?
				INPUT({name: "image", size: 80}),
				" (Coming soon: Selection from the above images)",
			])),
			P([
				LABEL([
					"Sound: ",
					INPUT({name: "sound", size: 80}),
				]),
				LABEL([
					"Volume: ",
					INPUT({name: "volume", type: "range", step: 0.05, min: 0, max: 1}),
					SPAN({className: "rangedisplay"}, "50%"),
				]),
			]),
			TEXTFORMATTING({
				textname: "textformat",
				textdesc: [BR(), CODE("{NAME}"), " for the channel name, and ", CODE("{VIEWERS}"), " for the view count."],
			}),
			P([BUTTON({type: "submit"}, "Save")]),
		]));
	});
	if (data.alertconfigs) Object.entries(data.alertconfigs).forEach(([type, attrs]) => {
		const par = alerttypes[type]; if (!par) return;
		Object.entries(attrs).forEach(([attr, val]) => par.elements[attr] && (par.elements[attr].value = val));
		document.querySelectorAll("input[type=range]").forEach(rangedisplay);
	});
}

function rangedisplay(el) {set_content(el.parentElement.querySelector(".rangedisplay"), el.value * 100 + "%");}
on("input", "input[type=range]", e => rangedisplay(e.match));

on("submit", ".alertconfig", e => {
	e.preventDefault();
	const msg = {cmd: "alertcfg", type: e.match.dataset.type};
	for (let el of e.match.elements)
		if (el.name) msg[el.name] = el.value; //TODO: Support checkboxes
	ws_sync.send(msg);
});

on("dragstart", "#alertboxlink", e => {
	e.dataTransfer.setData("text/uri-list", `${e.match.href}&layer-name=Host%20Alerts&layer-width=300&layer-height=300`);
});

let deleteid = null;
on("click", ".confirmdelete", e => {
	deleteid = e.match.closest("figure").dataset.id;
	const file = files[deleteid];
	DOM("#confirmdeletedlg .thumbnail").replaceWith(THUMB(file));
	set_content("#confirmdeletedlg a", file.name).href = file.url;
	DOM("#confirmdeletedlg").showModal();
});

on("click", "#delete", e => {
	if (deleteid) ws_sync.send({cmd: "delete", id: deleteid});
	DOM("#confirmdeletedlg").close();
});

on("click", "#testalert", e => ws_sync.send({cmd: "testalert"}));

const uploadme = { };
export async function sockmsg_upload(msg) {
	const file = uploadme[msg.name];
	if (!file) return;
	delete uploadme[msg.name];
	const resp = await (await fetch("alertbox?id=" + msg.id, { //The server guarantees that the ID is URL-safe
		method: "POST",
		body: file,
		credentials: "same-origin",
	})).json();
	console.log(resp);
}

on("change", "input[type=file]", e => {
	console.log(e.match.files);
	for (let f of e.match.files) {
		ws_sync.send({cmd: "upload", name: f.name, size: f.size, mimetype: f.type});
		uploadme[f.name] = f;
	}
	e.match.value = "";
});
