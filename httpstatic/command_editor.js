//Command advanced editor framework, and Raw mode editor
import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {BR, BUTTON, CANVAS, CODE, DIALOG, DIV, HEADER, H3, INPUT, LABEL, LI, P, SECTION, SPAN, TEXTAREA, UL, TR, TD} = choc;
const tablist = ["Classic", "Graphical", "Raw"], defaulttab = "classic";
document.body.appendChild(DIALOG({id: "advanced_view"}, SECTION([
	HEADER([
		H3("Edit trigger"),
		DIV(BUTTON({type: "button", className: "dialog_cancel"}, "x")),
		UL({id: "cmdviewtabset"}, tablist.map(tab => LI(LABEL([
			INPUT({type: "radio", name: "editor", value: tab.toLowerCase()}),
			SPAN(tab),
		])))),
	]),
	DIV([
		UL({id: "parameters"}),
		DIV({id: "command_details"}),
		DIV({id: "command_frame"}, [
			P("Drag elements around and snap them into position to build a command. Double-click an element to change its text etc."),
			CANVAS({id: "command_gui", width: "800", height: "600"}),
		]),
		P([
			BUTTON({type: "button", id: "save_advanced"}, "Save"),
			BUTTON({type: "button", className: "dialog_close"}, "Cancel"),
			BUTTON({type: "button", id: "delete_advanced"}, "Delete?"),
		]),
	]),
])));
//Delay the import of command_gui until the above code has executed, because JS is stupid and overly-eagerly
//imports all modules. Thanks, JS. You're amazing.
let gui_load_message, gui_save_message, pending_favourites, load_favourites = f => pending_favourites = f;
async function getgui() {
	({gui_load_message, gui_save_message, load_favourites} = await import("$$static||command_gui.js$$"));
	if (pending_favourites) load_favourites(pending_favourites);
}
if (document.readyState !== "loading") getgui();
else window.addEventListener("DOMContentLoaded", getgui);
//End arbitrarily messy code to do what smarter languages do automatically.
import {cls_load_message, cls_save_message} from "$$static||command_classic.js$$";
import {waitlate} from "$$static||utils.js$$";

export const commands = { }; //Deprecated. Need to try to not have this exported mapping.
const config = {get_command_basis: cmd => ({ })};
export function cmd_configure(cfg) {Object.assign(config, cfg);}

function checkpos() {
	const dlg = DOM("#advanced_view");
	const html = DOM("html");
	dlg.style.left = Math.max(html.clientWidth - dlg.clientWidth, 0) / 2 + "px";
	dlg.style.top = Math.max(html.clientHeight - dlg.clientHeight, 0) / 2 + "px";
	dlg.style.margin = "0";
}

let cmd_editing = null, mode = "", cmd_id = "", cmd_basis = { };
function get_message_details() {
	switch (mode) {
		case "classic": return cls_save_message();
		case "graphical": return gui_save_message();
		case "raw": {
			let response;
			try {response = JSON.parse(DOM("#raw_text").value);}
			catch (e) {set_content("#raw_error", "JSON format error: " + e.message); return null;}
			set_content("#raw_error", ""); //TODO: Show errors somewhere else (maybe in the header??)
			return response;
		}
		case "": return null;
	}
}
function change_tab(tab) {
	console.log("Previous:", mode);
	let response = get_message_details();
	if (response) ws_sync.send({cmd: "validate", cmdname: "changetab_" + tab, response});
	else select_tab(tab, cmd_editing);
}
function select_tab(tab, response) {
	mode = tab; cmd_editing = response;
	console.log("Selected:", tab, response);
	DOM("#command_frame").style.display = tab == "graphical" ? "block" : "none"; //Hack - hide and show the GUI rather than destroying and creating it.
	switch (tab) {
		case "classic": cls_load_message(cmd_basis, cmd_editing); break;
		case "graphical": {
			set_content("#command_details", "");
			//TODO: Load up more info into the basis object (and probably keep it around)
			//Notably, specials need a ton more info
			gui_load_message(cmd_basis, cmd_editing);
			break;
		}
		case "raw": set_content("#command_details", [
			P("Copy and paste entire commands in JSON format. Make changes as desired!"),
			DIV({className: "error", id: "raw_error"}),
			DIV([BUTTON({className: "raw_view compact", type: "button"}, "Compact"),
				BUTTON({className: "raw_view pretty", type: "button"}, "Pretty-print")]),
			TEXTAREA({id: "raw_text", rows: 25, cols: 100}, JSON.stringify(cmd_editing)),
		]); break;
		default: set_content("#command_details", "Unknown tab " + tab);
	}
}
on("change", "#cmdviewtabset input", e => change_tab(e.match.value));

function describe_params(params) {
	//TODO: Make them clickable to insert that token in the current EF??
	return Object.keys(params).map(p => LI([CODE(p), " - " + params[p]]));
}

export function open_advanced_view(cmd) {
	mode = ""; cmd_id = cmd.id; cmd_basis = config.get_command_basis(cmd);
	if (DOM("#parameters")) set_content("#parameters", describe_params(cmd_basis.provides || { }));
	DOM('[name="editor"][value="' + defaulttab + '"]').checked = true; select_tab(defaulttab, cmd);
	DOM("#advanced_view").style.cssText = "";
	DOM("#advanced_view").showModal();
}

on("click", "#save_advanced", async e => {
	const info = get_message_details();
	document.getElementById("advanced_view").close();
	const el = DOM("#cmdname");
	ws_sync.send({cmd: "update", cmdname: el ? el.value : cmd_id, response: info});
});

on("click", "#delete_advanced", waitlate(750, 5000, "Really delete?", e => {
	ws_sync.send({cmd: "delete", cmdname: cmd_id});
	DOM("#advanced_view").close();
}));

on("click", ".raw_view", e => {
	let response = DOM("#raw_text").value;
	//Hack: """long text""" allows multiline text, Python-style. It can ONLY handle text.
	if (response.startsWith('"""')) {
		response = response.split('"""')[1].split("\n").map(l => l.trim()).filter(l => l !== "");
	}
	else try {response = JSON.parse(response);}
	catch (e) {set_content("#raw_error", "JSON format error: " + e.message); return;}
	set_content("#raw_error", "");
	DOM("#raw_text").value = JSON.stringify(response, null, e.match.classList.contains("pretty") ? 4 : 0);
});
export function sockmsg_validated(data) {
	if (data.cmdname.startsWith("changetab_")) select_tab(data.cmdname.replace("changetab_", ""), data.response);
}
export function sockmsg_loadfavs(data) {load_favourites(data.favs);}

let favourites_loaded = false;
export function favcheck() {
	if (!favourites_loaded) {favourites_loaded = true; ws_sync.send({cmd: "loadfavs"});}
}

//Command summary view
function collect_messages(msg, cb, pfx) {
	if (typeof msg === "string") cb(pfx + msg);
	else if (Array.isArray(msg)) msg.forEach(line => collect_messages(line, cb, pfx));
	else if (typeof msg !== "object") return; //Not sure what this could mean, but we can't handle it. Probably a null entry or something.
	else if (msg.conditional && msg.otherwise) { //Hide the Otherwise if there isn't any (either a normal command with "" or a trigger with undefined)
		collect_messages(msg.message, cb, pfx + "?) ");
		collect_messages(msg.otherwise, cb, pfx + "!) ");
	}
	else collect_messages(msg.message, cb, pfx);
}
export function render_command(msg) {
	//All commands are objects with (at a minimum) an id and a message.
	//A simple command is one which is non-conditional and has a single message. Anything
	//else is a non-simple command and will be non-editable in the table - it can only be
	//edited using the Advanced View popup.
	const response = [];
	let editid = msg.id;
	if (msg.alias_of) {
		response.push(CODE("Alias of !" + msg.alias_of), BR());
		editid = msg.alias_of + "#" + msg.id.split("#")[1];
	}
	else if (!msg.conditional && (
		typeof msg.message === "string" ||
		(Array.isArray(msg.message) && !msg.message.find(r => typeof r !== "string"))
	)) {
		//Simple message. Return an editable row.
		collect_messages(msg.message, m => response.push(INPUT({value: m, className: "widetext"}), BR()), "");
	}
	else {
		//Complex message. Return a non-editable row.
		collect_messages(msg, m => response.push(CODE(m), BR()), "");
	}
	response.pop(); //There should be a BR at the end.
	commands[msg.id] = msg;
	return TR({"data-id": msg.id, "data-editid": editid}, [
		TD(CODE("!" + msg.id.split("#")[0])),
		TD(response),
		TD(BUTTON({type: "button", className: "advview", title: "Open editor"}, "\u2699")),
	]);
}

on("click", "button.advview", e => {
	const tr = e.match.closest("tr");
	open_advanced_view(commands[tr.dataset.editid || tr.dataset.id]);
});
on("input", "tr[data-id] input", e => e.match.closest("tr").classList.add("dirty"));
on("submit", "main > form", e => {
	e.preventDefault();
	document.querySelectorAll("tr.dirty[data-id]").forEach(tr => {
		const msg = [];
		tr.querySelectorAll("input").forEach(inp => inp.value && msg.push(inp.value));
		if (!msg.length) {
			ws_sync.send({cmd: "delete", cmdname: tr.dataset.id});
			return;
		}
		const response = {message: msg};
		//In order to get here, we had to render a simple command. That means its
		//message is pretty much all there is to it, but there might be some flags.
		const prev = commands[tr.dataset.id];
		for (let flg of ["mode", "access", "visibility", "delay", "dest", "target", "action"])
			if (prev[flg]) response[flg] = prev[flg];
		ws_sync.send({cmd: "update", cmdname: tr.dataset.id, response});
		//Note that the dirty flag is not reset. A successful update will trigger
		//a broadcast message which, when it reaches us, will rerender the command
		//completely, thus effectively resetting dirty.
	});
});

//Not applicable on all callers, but if it is, it should behave consistently
on("click", "#examples", e => {
	e.preventDefault();
	document.getElementById("templates").showModal();
});
on("click", "#templates tbody tr", e => {
	e.preventDefault();
	document.getElementById("templates").close();
	const [cmd, text] = e.match.children;
	const cmdname = cmd.innerText.trim();
	let template = complex_templates[cmdname] || text.innerText.trim();
	if (typeof template !== "object" || Array.isArray(template)) template = {message: template};
	const id = cmdname.startsWith("!") ? cmdname.slice(1) : ""; //Triggers don't get IDs until the server assigns them
	open_advanced_view({...template, id, template: true});
});
