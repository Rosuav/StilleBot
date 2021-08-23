//Command advanced editor framework, and Raw mode editor
import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {BR, BUTTON, CODE, DIV, INPUT, LABEL, LI, P, SPAN, TEXTAREA, UL, TR, TD} = choc;
import {gui_load_message, gui_save_message, load_favourites} from "$$static||command_gui.js$$";
import {cls_load_message, cls_save_message} from "$$static||command_classic.js$$";
import {waitlate} from "$$static||utils.js$$";

export const commands = { }; //Deprecated. Need to try to not have this exported mapping.

const hooks = {open_advanced: []}; //Deprecated, will be reworked into oblivion
export function add_hook(name, func) {
	if (!hooks[name]) return false;
	return hooks[name].push(func);
}

const tablist = ["Classic", "Graphical", "Raw"], defaulttab = "Classic";

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

export function open_advanced_view(cmd) {
	cmd_editing = cmd; mode = ""; cmd_id = cmd.id; cmd_basis = { };
	if (cmd.id[0] !== '!') cmd_basis.command = "!" + cmd.id.split("#")[0];
	set_content("#cmdname", "!" + cmd.id.split("#")[0]);
	if (!DOM("#cmdviewtabset")) DOM("#advanced_view header").appendChild(UL({id: "cmdviewtabset"}));
	set_content("#cmdviewtabset", tablist.map(tab => LI(LABEL([
		INPUT({type: "radio", name: "editor", value: tab.toLowerCase(), checked: tab === defaulttab}),
		SPAN(tab),
	]))));
	change_tab(defaulttab.toLowerCase());
	hooks.open_advanced.forEach(f => f(cmd, cmd_basis));
	DOM("#advanced_view").style.cssText = "";
	DOM("#advanced_view").showModal();
}

on("click", "#save_advanced", async e => {
	let info = get_message_details();
	/*
	const cmd = commands[document.getElementById("cmdname").innerText.slice(1)];
	console.log("WAS:", cmd);
	console.log("NOW:", info);
	return;
	// */
	document.getElementById("advanced_view").close();
	const el = document.getElementById("cmdname").firstChild;
	const cmdname = !el ? "" : el.nodeType === 3 ? el.data : el.value; //Not sure if text nodes' .data attribute is the best way to do this
	ws_sync.send({cmd: "update", cmdname, response: info});
});

on("click", "#delete_advanced", waitlate(750, 5000, "Really delete?", e => {
	const el = document.getElementById("cmdname").firstChild;
	const cmdname = el.nodeType === 3 ? el.data : el.value; //Duplicated from above
	ws_sync.send({cmd: "delete", cmdname});
	DOM("#advanced_view").close();
}));

on("click", ".raw_view", e => {
	let response;
	try {response = JSON.parse(DOM("#raw_text").value);}
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
	//A simple command is one which is non-conditional, and whose message  is either
	//a string or an array of strings. Anything else is a non-simple command and will
	//be non-editable in the table - it can only be edited using the Advanced View popup.
	const response = [], cmd = msg.id.split("#")[0];
	let addbtn = "";
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
		addbtn = BUTTON({type: "button", className: "addline", title: "Add another line"}, "+");
	}
	else {
		//Complex message. Return a non-editable row.
		collect_messages(msg, m => response.push(CODE(m), BR()), "");
	}
	response.pop(); //There should be a BR at the end.
	commands[msg.id] = msg;
	return TR({"data-id": msg.id, "data-editid": editid}, [
		TD(CODE("!" + cmd)),
		TD(response),
		TD([
			BUTTON({type: "button", className: "advview", title: "Advanced"}, "\u2699"),
			addbtn,
		]),
	]);
}

on("click", "button.addline", e => {
	let parent = e.match.closest("td").previousElementSibling;
	parent.appendChild(BR());
	parent.appendChild(INPUT({className: "widetext"}));
});

on("click", "button.advview", e => { //FIXME: Needs to be different for different files
	const tr = e.match.closest("tr");
	open_advanced_view(commands[tr.dataset.editid || tr.dataset.id]);
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
	const template = complex_templates[cmdname] || {message: text.innerText.trim()};
	open_advanced_view({...template, id: cmdname.slice(1)});
	if (cmdname[0] === '!') set_content("#cmdname", INPUT({value: cmdname}));
	else set_content("#cmdname", "");
});
