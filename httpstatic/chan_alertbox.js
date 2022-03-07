import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, AUDIO, BR, BUTTON, CODE, DIV, FIGCAPTION, FIGURE, FORM, H3, IMG, INPUT, LABEL, LI, OPTION, P, SELECT, SPAN} = choc; //autoimport
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

let have_authkey = false;
export function sockmsg_authkey(msg) {
	DOM("#alertboxlink").href = "alertbox?key=" + msg.key;
	msg.key = "<hidden>";
	have_authkey = true;
}

export function render(data) {
	if (data.authkey === "<REVOKED>" || !have_authkey) ws_sync.send({cmd: "getkey"});
	if (data.alerttypes) data.alerttypes.forEach(info => {
		const type = info.id;
		const placeholder_description = !info.placeholders ? ""
			: Object.entries(info.placeholders).map(([k,d]) => [BR(), CODE("{" + k + "}"), " - " + d]);
		if (alerttypes[type]) {
			for (let kwd in info) {
				let txt = info[kwd];
				if (kwd === "placeholders") txt = placeholder_description;
				const elem = alerttypes[type].querySelector("." + kwd);
				if (elem) set_content(elem, txt);
			}
			set_content("label[for=select-" + type + "]", info.label);
			return;
		}
		//TODO: Allow inherits?!? It would be really cool if you could say "bighostalert"
		//is "hostalert" with a different sound effect, for instance.
		//If inherits can be chained, this would allow alert schemes to be done by having
		//several top-level configs, then second tier selection that defines which is the
		//active scheme, and finally the lowest tier defines variants, using inherits for
		//everything that should follow the scheme.
		DOM("#alertselectors").appendChild(LI([
			INPUT({type: "radio", name: "alertselect", id: "select-" + type, value: type,
				checked: !DOM("input[name=alertselect]:checked")}),
			LABEL({htmlFor: "select-" + type}, info.label),
		]));
		update_visible_form();
		DOM("#alertconfigs").appendChild(alerttypes[type] = FORM({className: "alertconfig", "data-type": type}, [
			H3({className: "heading"}, info.heading),
			P({className: "description"}, info.description),
			P([
				SELECT({name: "format"}, [
					OPTION({value: "text_image_stacked"}, "Text and image, stacked"),
					OPTION({value: "text_image_overlaid"}, "Text overlaid on image"),
				]),
				LABEL([" Size:", INPUT({name: "alertwidth", type: "number", value: "250"})]),
				LABEL([" x ", INPUT({name: "alertheight", type: "number", value: "250"}), " pixels"]),
			]),
			P(LABEL([
				"Layout: ",
				SELECT({name: "layout"}, [OPTION({value: "image_above"}, "Image above"), OPTION({value: "image_below"}, "Image below")]),
			])),
			P([
				LABEL(["Alert length: ", INPUT({name: "alertlength", type: "number", value: "6", step: "0.5"}), " seconds; "]),
				LABEL(["gap before next alert: ", INPUT({name: "alertgap", type: "number", value: "1", step: "0.25"}), " seconds"]),
			]),
			P([
				"Image: ",
				IMG({className: "preview", "data-library": "image"}),
				" ",
				BUTTON({type: "button", className: "showlibrary", "data-target": "image", "data-prefix": "image/"}, "Choose"),
			]),
			P([
				"Sound: ",
				AUDIO({className: "preview", "data-library": "sound", controls: true}),
				" ",
				BUTTON({type: "button", className: "showlibrary", "data-target": "sound", "data-prefix": "audio/"}, "Choose"),
				LABEL([
					" Volume: ",
					INPUT({name: "volume", type: "range", step: 0.05, min: 0, max: 1, value: 0.5}),
					SPAN({className: "rangedisplay"}, "50%"),
				]),
			]),
			TEXTFORMATTING({
				textname: "textformat",
				textdesc: SPAN({className: "placeholders"}, placeholder_description),
			}),
			P([BUTTON({type: "submit"}, "Save"), BUTTON({type: "button", className: "testalert", "data-type": type}, "Send test alert")]),
		]));
	});
	if (data.alertconfigs) Object.entries(data.alertconfigs).forEach(([type, attrs]) => {
		const par = alerttypes[type]; if (!par) return;
		Object.entries(attrs).forEach(([attr, val]) => par.elements[attr] && (par.elements[attr].value = val));
		par.querySelectorAll("[data-library]").forEach(el => el.src = attrs[el.dataset.library]);
		update_layout_options(par, attrs.layout);
		document.querySelectorAll("input[type=range]").forEach(rangedisplay);
	});
}

function update_visible_form() {
	const sel = DOM("input[name=alertselect]:checked").value;
	set_content("#selectalert", ".alertconfig[data-type=" + sel + "] {display: block;}");
}
on("click", "input[name=alertselect]", update_visible_form);

function update_layout_options(par, layout) {
	const fmt = par.querySelector("[name=format]").value;
	const opts = {
		text_image_stacked: ["Image above", "Image below"],
		text_image_overlaid: ["Top left", "Top middle", "Top right", "Center left", "Center middle", "Center right", "Bottom left", "Bottom middle", "Bottom right"],
	}[fmt];
	if (!opts) return;
	const el = par.querySelector("[name=layout]");
	if (layout === "") layout = el.layout;
	set_content(el, opts.map(o => OPTION({value: o.toLowerCase().replace(" ", "_")}, o)));
	setTimeout(() => el.value = layout, 1);
}

on("change", "select[name=format]", e => update_layout_options(e.match.closest("form"), ""));

function rangedisplay(el) {
	set_content(el.parentElement.querySelector(".rangedisplay"), Math.floor(el.value * 100) + "%");
	el.closest("form").querySelector("[data-library=sound]").volume = el.value ** 2;
}
on("input", "input[type=range]", e => rangedisplay(e.match));

let librarytarget = null;
on("click", ".showlibrary", e => {
	const mode = e.match.dataset.target;
	librarytarget = mode ? e.match.form.querySelector("[data-library=" + mode + "]") : null; //In case there are multiple forms, retain the exact object we're targeting
	let needvalue = !!librarytarget;
	const pfx = e.match.dataset.prefix || "";
	for (let el of render_parent.children) {
		if (!el.dataset.id) continue;
		const want = el.dataset.type.startsWith(pfx);
		el.classList.toggle("active", want);
		el.classList.toggle("inactive", !want); //Not sure which is going to be more useful. Pick a style and ditch the other.
		const rb = el.querySelector("input[type=radio]");
		rb.disabled = !want || pfx === "";
		if (needvalue && el.querySelector("a").href === librarytarget.src) {rb.checked = true; needvalue = false;}
	}
	if (needvalue) {
		//Didn't match against any of the library entries.
		if (librarytarget.src === "") DOM("input[type=radio][data-special=None]").checked = true;
		else {
			DOM("input[type=radio][data-special=URL]").checked = true;
			DOM("#customurl").value = librarytarget.src;
		}
	}
	DOM("#library").classList.toggle("noselect", DOM("#libraryselect").disabled = pfx === "");
	DOM("#library").showModal();
});

//Select radio buttons as appropriate when you manipulate the URL box
DOM("#customurl").onfocus = e => e.target.value !== "" && (DOM("input[type=radio][data-special=URL]").checked = true);
on("input", "#customurl", e => DOM("input[type=radio][data-special=" + (e.target.value !== "" ? "URL" : "None") + "]").checked = true);

//Can the dialog be made into a form and this turned into a submit event? <form method=dialog>
//isn't very well supported yet, so I might have to do some of the work myself. Would improve
//keyboard accessibility though.
on("click", "#libraryselect", e => {
	if (librarytarget) {
		const rb = DOM("#library input[type=radio]:checked");
		if (rb) switch (rb.dataset.special) {
			case "None": librarytarget.src = ""; break;
			case "URL": librarytarget.src = DOM("#customurl").value; break;
			default: librarytarget.src = rb.parentElement.querySelector("a").href;
		}
		ws_sync.send({cmd: "alertcfg", type: librarytarget.closest(".alertconfig").dataset.type,
			[librarytarget.dataset.library]: librarytarget.src});
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
	e.dataTransfer.setData("text/uri-list", `${e.match.href}&layer-name=Host%20Alerts&layer-width=600&layer-height=400`);
});

on("click", "#alertboxlink", e => {
	e.preventDefault();
	DOM("#alertembed").src = e.match.href;
	DOM("#previewdlg").showModal();
});

//Unload the preview when the dialog closes
DOM("#previewdlg").onclose = e => DOM("#alertembed").src = "";

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

on("click", ".testalert", e => ws_sync.send({cmd: "testalert", type: e.match.dataset.type}));

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

on("click", "#revokekey", e => DOM("#revokekeydlg").showModal());
on("click", "#confirmrevokekey", e => {ws_sync.send({cmd: "revokekey"}); DOM("#revokekeydlg").close();});
