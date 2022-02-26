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
	return LABEL({"data-id": file.id, "data-type": file.mimetype}, [
		INPUT({type: "radio", name: "chooseme", value: file.id}),
		FIGURE([
			THUMB(file),
			FIGCAPTION(A({href: file.url, target: "_blank"}, file.name)),
			BUTTON({type: "button", className: "confirmdelete", title: "Delete"}, "🗑"),
		]),
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
			P([
				LABEL(["Image: ", INPUT({name: "image", size: 100})]),
				" ",
				BUTTON({type: "button", className: "showlibrary", "data-target": "image", "data-prefix": "image/"}, "Choose"),
			]),
			P([
				LABEL([
					"Sound: ",
					INPUT({name: "sound", size: 100}),
				]),
				" ",
				BUTTON({type: "button", className: "showlibrary", "data-target": "sound", "data-prefix": "audio/"}, "Choose"),
				LABEL([
					" Volume: ",
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

let librarytarget = null;
on("click", ".showlibrary", e => {
	const mode = e.match.dataset.target;
	librarytarget = mode ? e.match.form.elements[mode] : null; //In case there are multiple forms, retain the exact object we're targeting
	let needvalue = !!librarytarget;
	const pfx = e.match.dataset.prefix || "";
	for (let el of render_parent.children) {
		if (!el.dataset.id) continue;
		const want = el.dataset.type.startsWith(pfx);
		el.classList.toggle("active", want);
		el.classList.toggle("inactive", !want); //Not sure which is going to be more useful. Pick a style and ditch the other.
		const rb = el.querySelector("input[type=radio]");
		rb.disabled = !want || pfx === "";
		if (needvalue && el.querySelector("a").href === librarytarget.value) {rb.checked = true; needvalue = false;}
	}
	if (needvalue) {
		//Didn't match against any of the library entries.
		if (librarytarget.value === "") DOM("input[type=radio][data-special=None]").checked = true;
		else {
			DOM("input[type=radio][data-special=URL]").checked = true;
			//TODO: Set the input to the URL
		}
	}
	DOM("#library").classList.toggle("noselect", DOM("#libraryselect").disabled = pfx === "");
	DOM("#library").showModal();
});

//Can the dialog be made into a form and this turned into a submit event? <form method=dialog>
//isn't very well supported yet, so I might have to do some of the work myself. Would improve
//keyboard accessibility though.
on("click", "#libraryselect", e => {
	if (librarytarget) {
		const rb = DOM("#library input[type=radio]:checked");
		if (rb) switch (rb.dataset.special) {
			case "None": librarytarget.value = ""; break;
			case "URL": librarytarget.value = "<...>"; break; //TODO
			default: librarytarget.value = rb.parentElement.querySelector("a").href;
		}
		librarytarget = null;
	}
	DOM("#library").close();
});

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
	deleteid = e.match.closest("[data-id]").dataset.id;
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
