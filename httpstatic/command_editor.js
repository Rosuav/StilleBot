//Command advanced editor framework, and Raw mode editor
import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {B, BR, BUTTON, CANVAS, CODE, DIALOG, DIV, EM, FORM, H3, HEADER, INPUT, LABEL, LI, P, SECTION, SPAN, TD, TEXTAREA, TR, U, UL} = choc; //autoimport
const tablist = ["Classic", "Graphical", "Raw"];
let defaulttab = "graphical"; //Can be overridden with prefs
document.body.appendChild(DIALOG({id: "advanced_view"}, SECTION([
	HEADER([
		H3("Edit trigger"),
		DIV(BUTTON({type: "button", className: "dialog_cancel"}, "x")),
		UL({id: "cmdviewtabset", className: "buttonbox"}, [...tablist.map(tab => LI(LABEL([
			INPUT({type: "radio", name: "editor", value: tab.toLowerCase(), accessKey: tab[0]}),
			SPAN([U(tab[0]), tab.slice(1)]),
		]))),
			LI(BUTTON({id: "makedefault"}, "Make default")),
		]),
	]),
	FORM({autocomplete: "off"}, [
		DIV({id: "command_details"}),
		DIV({id: "command_frame"}, [
			P({style: "margin: 0.5em 0 0 0"}, [ //Hack: Try removing some margin to save space. Will prob unhack this eventually.
				"Drag elements around and snap them into position to build a command. ",
				B("Double-click"),
				" an element to make changes to it.",
			]),
			CANVAS({id: "command_gui", width: "800", height: "600"}),
		]),
		UL({className: "buttonbox"}, [
			LI(BUTTON({type: "button", id: "save_advanced"}, "Save")),
			LI(BUTTON({type: "button", className: "dialog_close"}, "Cancel")),
			LI(BUTTON({type: "button", id: "delete_advanced"}, "Delete?")),
		]),
	]),
])));
//Delay the import of command_gui until the above code has executed, because JS is stupid and overly-eagerly
//imports all modules. Thanks, JS. You're amazing.
let gui_load_message, gui_save_message;
async function getgui() {
	({gui_load_message, gui_save_message} = await import("$$static||command_gui.js$$"));
}
if (document.readyState !== "loading") getgui();
else window.addEventListener("DOMContentLoaded", getgui);
//End arbitrarily messy code to do what smarter languages do automatically.
import {cls_load_message, cls_save_message} from "$$static||command_classic.js$$";
import {waitlate} from "$$static||utils.js$$";
ws_sync.prefs_notify("cmd_defaulttab", tab => {
	if (tablist.some(t => t.toLowerCase() === tab)) defaulttab = tab;
});

export const commands = { }; //Deprecated. Need to try to not have this exported mapping.
const config = {get_command_basis: cmd => ({ })};
export function cmd_configure(cfg) {Object.assign(config, cfg);}

let cmd_editing = null, mode = "", cmd_id = "", cmd_basis = { };
function get_message_details() {
	switch (mode) {
		case "classic": return cls_save_message();
		case "graphical": return gui_save_message();
		case "raw": {
			let response;
			try {response = JSON.parse(DOM("#raw_text").value);}
			catch (e) {set_content("#raw_error", "JSON format error: " + e.message); return null;}
			set_content("#raw_error", "");
			return response;
		}
		case "": return null;
	}
}
function change_tab(tab) {
	let response = get_message_details();
	if (response) ws_sync.send({cmd: "validate", cmdname: "changetab_" + tab, response}, "cmdedit");
	else select_tab(tab, cmd_editing);
}

//If we try to open graphical view before it's loaded, twiddle our thumbs for a while.
function try_gui_load_message(basis, editing) {
	if (gui_load_message) return gui_load_message(basis, editing);
	setTimeout(try_gui_load_message, 0.025, basis, editing);
}

function select_tab(tab, response) {
	mode = tab; cmd_editing = response;
	history.replaceState(null, "", "#" + cmd_id.split("#")[0].replace("!", "") + "/" + tab);
	DOM("#command_frame").style.display = tab == "graphical" ? "block" : "none"; //Hack - hide and show the GUI rather than destroying and creating it.
	switch (tab) {
		case "classic": cls_load_message(cmd_basis, cmd_editing); break;
		case "graphical": {
			set_content("#command_details", "");
			try_gui_load_message(cmd_basis, cmd_editing);
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
on("click", "#makedefault", e => ws_sync.send({cmd: "prefs_update", cmd_defaulttab: mode}));

export function open_advanced_view(cmd, tab) {
	mode = ""; cmd_id = cmd.id; cmd_basis = config.get_command_basis(cmd);
	if (!tablist.some(t => t.toLowerCase() === tab)) tab = defaulttab;
	DOM('[name="editor"][value="' + tab + '"]').checked = true; select_tab(tab, cmd);
	DOM("#advanced_view").style.cssText = "";
	DOM("#advanced_view").showModal();
}

//Can't use on() for this as the event doesn't bubble
DOM("#advanced_view").addEventListener("close", () => history.replaceState(null, "", " "));

on("click", "#save_advanced", async e => {
	const info = get_message_details();
	document.getElementById("advanced_view").close();
	const el = DOM("#cmdname");
	ws_sync.send({cmd: "update", cmdname: el ? el.value : cmd_id, original: cmd_id, response: info}, "cmdedit");
});

on("click", "#delete_advanced", waitlate(750, 5000, "Really delete?", e => {
	ws_sync.send({cmd: "delete", cmdname: cmd_id}, "cmdedit");
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

let pending_command = null;
if (location.hash && location.hash.includes("/")) pending_command = location.hash.slice(1).split("/", 2);

//Command summary view
function scan_message(msg, msgstatus, parent, key) {
	if (typeof msg === "string") {
		if (msgstatus.replacetext) parent[key] = msgstatus.replacetext;
		if (msg === "") return null;
		return msg;
	}
	if (Array.isArray(msg)) {
		//Map recurse, filter out any empty strings or null returns.
		return [].concat(...msg.map((m,i) => scan_message(m, msgstatus, msg, i)).filter(m => m));
	}
	if (!msg || typeof msg !== "object") return null; //Not sure what this could mean, but we can't handle it. Probably a null entry or something.
	if (msg.dest === "/w") msgstatus.whisper = true;
	else if (msg.dest) return null; //Anything with a special destination (eg Variable, Private Message) shouldn't be shown this way.
	if (msg.mode === "random") msgstatus.oneof = true;
	if (msg.conditional && msg.conditional !== "cooldown") {
		//Combine both the branches of the conditional and, if there's only one thing
		//to say, assume we say that. (A conditional that sometimes suppresses, or a
		//cooldown, is considered to be just a message with flags.)
		const oth = scan_message(msg.otherwise, msgstatus, msg, "otherwise");
		msg = scan_message(msg.message, msgstatus, msg, "message");
		if (!msg || !oth) return msg || oth; //If either is missing, use the other. (Or null if both are, but that shouldn't happen.)
		//Both branches have text. Say that it'll be "one of" these.
		msgstatus.oneof = true;
		return [].concat(msg, oth);
	}
	return scan_message(msg.message, msgstatus, msg, "message");
}
export function render_command(msg) {
	//All commands are objects with (at a minimum) an id and a message.
	//A simple command is one which is non-conditional and has a single message. Anything
	//else is a non-simple command and will be non-editable in the table - it can only be
	//edited using the Advanced View popup.
	const response = [];
	let editid = msg.id;
	if (msg.alias_of) {
		response.push(CODE("Alias of !" + msg.alias_of));
		editid = msg.alias_of + "#" + msg.id.split("#")[1];
	}
	else {
		const msgstatus = { };
		let simpletext = scan_message(msg, msgstatus);
		//Special case (pun intended): A completely empty message (no flags or anything) can show up as empty.
		if (msg.message === "" && msg.id && Object.keys(msg).length === 2) simpletext = "";
		if (msgstatus.whisper) response.push(EM("Response will be whispered"), BR());
		if (msgstatus.oneof) response.push(EM("One of:"), BR());
		if (typeof simpletext === "string") response.push(INPUT({value: simpletext, className: "widetext"}));
		else if (!simpletext) response.push(CODE("(Special command, unable to summarize)")); //Not going to be common. Get some examples before rewording this.
		else simpletext.forEach(m => response.push(CODE(m), BR()));
	}
	commands[msg.id] = msg;
	if (pending_command && pending_command[0].replace("!", "") === msg.id.split("#")[0].replace("!", "")) {
		//Let everything else finish loading before opening advanced view
		setTimeout(open_advanced_view, 0.025, msg, pending_command[1]);
		pending_command = null;
	}
	return TR({"data-id": msg.id, "data-editid": editid}, [
		TD(CODE("!" + msg.id.split("#")[0])),
		TD(response),
		TD(BUTTON({type: "button", className: "advview", title: "Open editor"}, "\u2699")),
	]);
}

on("click", "button.advview", e => {
	const tr = e.match.closest("[data-id]");
	open_advanced_view(commands[tr.dataset.editid || tr.dataset.id]);
});
on("input", "tr[data-id] input", e => e.match.closest("tr").classList.add("dirty"));
on("submit", "main > form", e => {
	e.preventDefault();
	document.querySelectorAll("tr.dirty[data-id]").forEach(tr => {
		const msg = tr.querySelector("input").value;
		if (!msg.length) {
			ws_sync.send({cmd: "delete", cmdname: tr.dataset.id}, "cmdedit");
			return;
		}
		//Take a copy of the original command (we're going to JSON-encode it anyway, so this should
		//be safe) and inject the new message text into it.
		let response = JSON.parse(JSON.stringify(commands[tr.dataset.id]));
		if (typeof response === "string") response = msg;
		else scan_message(response, {replacetext: msg});
		ws_sync.send({cmd: "update", cmdname: tr.dataset.id, response}, "cmdedit");
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
