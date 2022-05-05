import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, ABBR, AUDIO, BR, BUTTON, CODE, DETAILS, DIV, FIGCAPTION, FIGURE, FORM, H3, HR, IMG, INPUT, LABEL, LI, OPTION, P, SELECT, SPAN, SUMMARY, TABLE, TD, TR} = choc; //autoimport
import {waitlate, TEXTFORMATTING} from "$$static||utils.js$$";

function THUMB(file) {
	if (!file.url) return DIV({className: "thumbnail"}, "uploading...");
	if (file.mimetype.startsWith("audio/")) return DIV({className: "thumbnail"}, AUDIO({src: file.url, controls: true}));
	return DIV({className: "thumbnail", style: "background-image: url(" + file.url + ")"});
}

const TRANSPARENT_IMAGE = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNgAAIAAAUAAen63NgAAAAASUVORK5CYII=";

const files = { };
const alerttypes = { }, alert_definitions = { };
const revert_data = {"default": { }};

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
			FIGCAPTION([
				A({href: file.url, target: "_blank"}, file.name),
				" ",
				BUTTON({type: "button", className: "renamefile", title: "Rename"}, "📝"),
			]),
			BUTTON({type: "button", className: "confirmdelete", title: "Delete"}, "🗑"),
		]),
	]);
}

let have_authkey = false;
export function sockmsg_authkey(msg) {
	DOM("#alertboxlink").href = "alertbox?key=" + msg.key;
	msg.key = "<hidden>";
	have_authkey = true;
	if (DOM("#previewdlg").open) DOM("#alertembed").src = DOM("#alertboxlink").href;
}

function load_data(type, attrs) {
	const par = alerttypes[type]; if (!par) return;
	revert_data[type] = attrs = {...revert_data["default"], ...attrs};
	if (par.classList.contains("unsaved-changes")) return; //TODO: Notify the user that server changes haven't been applied
	for (let el of par.elements) {
		if (!el.name) continue;
		if (el.type === "checkbox") el.checked = !!attrs[el.name];
		else el.value = attrs[el.name] || "";
		el.classList.remove("dirty");
		el.labels.forEach(l => l.classList.remove("dirty"));
		if (el.tagName === "SELECT" || el.type === "text" || el.type === "number") {
			el.classList.toggle("inherited", el.value === "");
			el.labels.forEach(l => l.classList.toggle("inherited", el.value === ""));
		}
	}
	par.querySelectorAll("[data-library]").forEach(el => el.src = attrs[el.dataset.library] || TRANSPARENT_IMAGE);
	update_layout_options(par, attrs.layout);
	document.querySelectorAll("input[type=range]").forEach(rangedisplay);
	par.querySelectorAll("[type=submit]").forEach(el => el.disabled = true);
	//For everything in this alert's MRO, disallow that thing inheriting from this one.
	//That makes reference cycles impossible (barring shenanigans, which would be caught
	//on the server by simply inheriting nothing).
	const mro = attrs.mro || [type];
	document.querySelectorAll("select[name=parent] option[value=" + type + "]").forEach(el =>
		el.disabled = mro.includes(el.closest(".alertconfig").dataset.type)
	);
}

let selecttab = location.hash.slice(1);
export function render(data) {
	if (data.authkey === "<REVOKED>") {
		have_authkey = false;
		if (DOM("#previewdlg").open) ws_sync.send({cmd: "getkey"});
	}
	if (data.alertdefaults) revert_data["default"] = data.alertdefaults;
	if (data.alerttypes) data.alerttypes.forEach(info => {
		const type = info.id;
		alert_definitions[type] = info;
		const placeholder_description = !info.placeholders ? [BR(), CODE("{text}"), " - the text used to trigger the alert"]
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
		const nondef = type !== "defaults"; //A lot of things are different for the defaults
		DOM("#newpersonal").before(LI([
			INPUT({type: "radio", name: "alertselect", id: "select-" + type, value: type}),
			LABEL({htmlFor: "select-" + type}, info.label),
		]));
		document.querySelectorAll("select[name=parent]").forEach(el => el.appendChild(OPTION({value: type}, info.label)));
		DOM("#alertconfigs").appendChild(alerttypes[type] = FORM({class: type === "defaults" ? "alertconfig no-inherit": "alertconfig", "data-type": type}, [
			H3({className: "heading"}, [
				info.heading, SPAN({className: "if-unsaved"}, " "),
				ABBR({className: "dirty if-unsaved", title: "Unsaved changes - click Save to apply them"}, "*"),
			]),
			P([
				!info.builtin && BUTTON({type: "button", className: "editpersonaldesc", title: "Edit"}, "📝"),
				SPAN({className: "description"}, info.description),
			]),
			HR(),
			info.condition_vars && DETAILS({class: "expandbox no-inherit", open: true}, [ //Remove {open: true} for production
				SUMMARY("Alert will be used (TODO) <always/never/by default/when alert set active>. Expand to configure."),
				P("If any alert variation (coming soon!) is used, the base alert will be replaced with it."),
				//Condition vars depend on the alert type. For instance, a sub alert
				//can check the tier, a cheer alert the number of bits. It's entirely
				//possible to have empty condition_vars, which will just have the
				//standard condition types.
				TABLE(info.condition_vars.map(c => TR([
					TD(c), //TODO: Replace with a description
					TD(SELECT({name: "cond-" + c + "-oper"}, [
						OPTION({value: ""}, "n/a"),
						OPTION({value: "=="}, "is exactly"),
						OPTION({value: ">="}, "is at least"),
					])),
					TD(INPUT({name: "cond-" + c + "-val", type: "number"})),
				]))),
				//Ultimately this will get a list of alert sets from the server
				P(LABEL(["Only if alert set active: (unimpl) ", SELECT({name: "cond-alertset"}, [
					OPTION({value: ""}, "n/a"),
					["Foo", "Bar"].map(s => OPTION(s)),
				])])),
				//Fully custom conditions. Currently disabled. Do we need them? Would it be
				//better to recommend that people use the full special+builtin system instead?
				/*P(LABEL([
					"Custom numeric condition: ",
					INPUT({name: "cond-numeric", size: 30}),
					" (blank to ignore)",
				])),
				P([
					"Custom text condition: ",
					INPUT({name: "cond-expr1", size: 20}),
					SELECT({name: "cond-type"}, [
						OPTION({value: ""}, "n/a"),
						OPTION({value: "string"}, "is exactly"),
						OPTION({value: "contains"}, "includes"),
						OPTION({value: "regexp"}, "matches regex"),
					]),
					INPUT({name: "cond-expr2", size: 20}),
				]),*/
			]),
			nondef && P([
				LABEL([INPUT({name: "active", type: "checkbox"}), " Active/enabled"]), BR(),
				LABEL(["Inherit settings from: ", SELECT({name: "parent"},
					Object.entries(alert_definitions).map(([t, x]) =>
						t === "defaults" ? OPTION({value: ""}, "None")
						: OPTION({value: t}, x.label)),
				)]),
			]),
			P([
				SELECT({name: "format"}, [
					OPTION({value: "text_image_stacked"}, "Text and image, stacked"),
					OPTION({value: "text_image_overlaid"}, "Text overlaid on image"),
				]),
				LABEL([" Size:", INPUT({name: "alertwidth", type: "number"})]),
				LABEL([" x ", INPUT({name: "alertheight", type: "number"}), " pixels"]),
			]),
			P(LABEL([
				"Layout: ",
				SELECT({name: "layout"}, [OPTION({value: "image_above"}, "Image above"), OPTION({value: "image_below"}, "Image below")]),
			])),
			P([
				LABEL(["Alert length: ", INPUT({name: "alertlength", type: "number", step: "0.5"}), " seconds; "]),
				LABEL(["gap before next alert: ", INPUT({name: "alertgap", type: "number", step: "0.25"}), " seconds"]),
			]),
			nondef && P([
				"Image: ",
				IMG({className: "preview", "data-library": "image"}),
				" ",
				BUTTON({type: "button", className: "showlibrary", "data-target": "image", "data-prefix": "image/"}, "Choose"),
			]),
			nondef && P([
				"Sound: ",
				AUDIO({className: "preview", "data-library": "sound", controls: true}),
				" ",
				BUTTON({type: "button", className: "showlibrary", "data-target": "sound", "data-prefix": "audio/"}, "Choose"),
				LABEL([
					" Volume: ",
					INPUT({name: "volume", type: "range", step: 0.05, min: 0, max: 1}),
					SPAN({className: "rangedisplay"}, ""),
				]),
			]),
			TEXTFORMATTING({
				textname: nondef ? "textformat" : "-",
				textdesc: SPAN({className: "placeholders"}, placeholder_description),
				blank_opts: nondef, //Add a blank option to selects, but not on the Defaults tab
			}),
			P([BUTTON({type: "submit", disabled: true}, "Save"), nondef && BUTTON({type: "button", className: "testalert", "data-type": type}, "Send test alert")]),
		]));
		load_data(type, { });
	});
	if (selecttab !== null && data.alerttypes && !DOM("input[name=alertselect]:checked")) {
		console.log("Trying to select", selecttab);
		if (!DOM("#select-" + selecttab))
			//Invalid or not specified? Use the first tab.
			selecttab = document.querySelectorAll("input[name=alertselect]")[0].id.replace("select-", "")
		DOM("#select-" + selecttab).checked = true;
		update_visible_form();
		selecttab = null;
	}
	if (data.alertconfigs) Object.entries(data.alertconfigs).forEach(([type, attrs]) => load_data(type, attrs));
	if (data.delpersonal) {
		//This isn't part of a normal stateful update, and is a signal that a personal
		//alert has gone bye-bye. Clean up our local state, matching what we'd have if
		//we refreshed the page.
		const type = data.delpersonal;
		alerttypes[type].replaceWith();
		delete alerttypes[type];
		delete revert_data[type];
		DOM("#select-" + type).closest("li").replaceWith();
		document.querySelectorAll("select[name=parent] option[value=" + type + "]").forEach(el => el.replaceWith());
		if (wanted_tab === type) {
			//The currently-selected one got deleted. Switch to the first available.
			document.querySelectorAll("input[name=alertselect]")[0].checked = true;
			update_visible_form();
		}
	}
}

let wanted_tab = null; //TODO: Allow this to be set from the page fragment (wait till loading is done)
function update_visible_form() {
	wanted_tab = DOM("input[name=alertselect]:checked").value;
	set_content("#selectalert", ".alertconfig[data-type=" + wanted_tab + "] {display: block;}");
	history.replaceState(null, "", "#" + wanted_tab);
}

function update_layout_options(par, layout) {
	const fmt = par.querySelector("[name=format]").value;
	const opts = {
		text_image_stacked: ["Image above", "Image below"],
		text_image_overlaid: ["Top left", "Top middle", "Top right", "Center left", "Center middle", "Center right", "Bottom left", "Bottom middle", "Bottom right"],
	}[fmt];
	if (!opts) return;
	const el = par.querySelector("[name=layout]");
	if (layout === "") layout = el.layout;
	const kwds = opts.map(o => o.toLowerCase().replace(" ", "_")); //TODO: Deduplicate
	if (!kwds.includes(layout)) layout = kwds[0];
	set_content(el, opts.map(o => OPTION({value: o.toLowerCase().replace(" ", "_")}, o)));
	setTimeout(() => el.value = layout, 1);
}

on("change", "select[name=format]", e => update_layout_options(e.match.closest("form"), ""));

function rangedisplay(el) {
	set_content(el.parentElement.querySelector(".rangedisplay"), Math.floor(el.value * 100) + "%");
	el.closest("form").querySelector("[data-library=sound]").volume = el.value ** 2;
}
on("input", "input[type=range]", e => rangedisplay(e.match));

function formchanged(e) {
	const frm = e.match.form; if (!frm || !frm.classList.contains("alertconfig")) return;
	frm.classList.add("unsaved-changes"); //Add "dirty" here to colour the entire form
	e.match.classList.add("dirty"); //Can skip this if dirty is applied to the whole form
	e.match.labels.forEach(l => l.classList.add("dirty"));
	const inh = e.match.value === "";
	e.match.classList.toggle("inherited", inh);
	e.match.labels.forEach(l => l.classList.toggle("inherited", inh));
	frm.querySelectorAll("[type=submit]").forEach(el => el.disabled = false);
}
on("input", "input", formchanged); on("change", "input,select", formchanged);

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
		if (librarytarget.src === TRANSPARENT_IMAGE) DOM("input[type=radio][data-special=None]").checked = true;
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
		let img = "";
		if (rb) switch (rb.dataset.special) {
			case "None": break;
			case "URL": img = DOM("#customurl").value; break;
			default: img = rb.parentElement.querySelector("a").href;
		}
		ws_sync.send({cmd: "alertcfg", type: librarytarget.closest(".alertconfig").dataset.type,
			[librarytarget.dataset.library]: img});
		librarytarget.src = img || TRANSPARENT_IMAGE;
		librarytarget = null;
	}
	DOM("#library").close();
});

on("submit", ".alertconfig", e => {
	e.preventDefault();
	const msg = {cmd: "alertcfg", type: e.match.dataset.type};
	for (let el of e.match.elements)
		if (el.name) msg[el.name] = el.type === "checkbox" ? el.checked : el.value;
	ws_sync.send(msg);
	e.match.classList.remove("unsaved-changes");
});

on("dragstart", "#alertboxlink", e => {
	//TODO: Set the width and height to the (individual) maximums of all alerts, incl defaults
	e.dataTransfer.setData("text/uri-list", `${e.match.href}&layer-name=Host%20Alerts&layer-width=600&layer-height=400`);
});

on("click", "#authpreview", e => {
	if (!have_authkey) ws_sync.send({cmd: "getkey"});
	else DOM("#alertembed").src = DOM("#alertboxlink").href;
	DOM("#previewdlg").showModal();
});
on("click", "#alertboxdisplay", e => {
	e.match.value = DOM("#alertboxlink").href;
	e.match.disabled = false;
	e.match.select();
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

let unsaved_form = null, unsaved_clickme = null;
on("click", "#unsaved-save,#unsaved-discard", e => {
	DOM("#unsaveddlg").close();
	//Asynchronicity note: There are three timestreams involved in a "save
	//and test" scenario, all independent, but all internally sequenced.
	//1) Here in the editor, we collect form data, then push that out on
	//   the websocket to the server. Then we send the "test alert" message.
	//2) On the server, the "alertcfg" message is received, and configuration
	//   is saved, and pushed out to all clients (including both the editor
	//   and the display). Then the "testalert" message is received, and the
	//   signal goes to the display to send a test alert.
	//3) In the display client, the update from the server is received, and
	//   all changes are immediately applied. Then the alert signal comes in,
	//   and the freshly-updated alert gets fired.
	//So even though we have two separations of asynchronicity, the sequencing
	//of "save, then test" actually still works, so long as requestSubmit() is
	//properly synchronous. (If that's not true on all browsers, just refactor
	//submission into a callable function and do the save directly.)
	if (e.match.id === "unsaved-save") unsaved_form.requestSubmit();
	else {
		const type = unsaved_form.dataset.type;
		unsaved_form.classList.remove("unsaved-changes");
		load_data(type, revert_data[type] || { });
	}
	unsaved_clickme.click();
	unsaved_form = unsaved_clickme = null;
});

on("click", ".testalert", e => {
	const type = e.match.dataset.type, frm = DOM("form[data-type=" + type + "]");
	if (frm.classList.contains("unsaved-changes")) {
		unsaved_form = frm; unsaved_clickme = e.match;
		set_content("#discarddesc", "Cannot send a test alert with unsaved changes.");
		DOM("#unsaveddlg").showModal();
		return;
	}
	ws_sync.send({cmd: "testalert", type});
});

on("click", "input[name=alertselect]", e => {
	const frm = DOM(".alertconfig[data-type=" + wanted_tab + "]");
	if (frm && frm.classList.contains("unsaved-changes")) {
		unsaved_form = frm; unsaved_clickme = e.match;
		set_content("#discarddesc", "Unsaved changes will be lost if you switch to another alert type.");
		DOM("#select-" + wanted_tab).checked = true; //Snap back to the other one
		DOM("#unsaveddlg").showModal();
		return;
	}
	update_visible_form();
});

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


on("click", "#addpersonal", e => {
	const frm = DOM(".alertconfig[data-type=" + wanted_tab + "]");
	if (frm && frm.classList.contains("unsaved-changes")) {
		unsaved_form = frm; unsaved_clickme = e.match;
		set_content("#discarddesc", "Unsaved changes will be lost if you create another alert type.");
		DOM("#unsaveddlg").showModal();
		return;
	}
	for (let el of DOM("#editpersonal").elements) el.value = "";
	set_content("#savepersonal", "Add");
	DOM("#delpersonal").disabled = true;
	DOM("#personaldlg").showModal();
});

on("click", ".editpersonaldesc", e => {
	const type = e.match.closest("form").dataset.type;
	const elem = DOM("#editpersonal").elements;
	const info = alert_definitions[type];
	for (let kwd in info) {
		if (elem[kwd]) elem[kwd].value = info[kwd];
	}
	elem.id.value = type;
	set_content("#savepersonal", "Save");
	DOM("#delpersonal").disabled = false;
	DOM("#personaldlg").showModal();
});

//TODO: Make a general handler in utils for all form[method=dialog]?
//Would need a data-cmd to bootstrap the message, or alternatively,
//some other type of hook that receives the form and an object of data.
//Maybe even have a "form dialog opening button", the entire thing??
//When it's clicked, it triggers a delayed event upon form submission.
on("submit", "#editpersonal", e => {
	e.preventDefault(); //Can't depend on method=dialog :(
	const msg = {cmd: "makepersonal"}; //Atwix's Legacy?
	for (let el of e.match.elements)
		if (el.name) msg[el.name] = el.type === "checkbox" ? el.checked : el.value;
	ws_sync.send(msg);
	DOM("#personaldlg").close();
});

on("click", "#delpersonal", waitlate(1000, 7500, "Really delete?", e => {
	ws_sync.send({cmd: "delpersonal", id: DOM("#editpersonal").elements.id.value});
	DOM("#personaldlg").close();
}));

on("click", ".renamefile", e => {
	const elem = DOM("#renameform").elements;
	const file = files[e.match.closest("[data-id]").dataset.id];
	if (!file) return;
	DOM("#renamefiledlg .thumbnail").replaceWith(THUMB(file));
	elem.id.value = file.id;
	elem.name.value = file.name;
	DOM("#renamefiledlg").showModal();
});

on("submit", "#renameform", e => {
	e.preventDefault();
	const msg = {cmd: "renamefile"};
	for (let el of e.match.elements)
		if (el.name) msg[el.name] = el.type === "checkbox" ? el.checked : el.value;
	ws_sync.send(msg);
	DOM("#renamefiledlg").close();
});
