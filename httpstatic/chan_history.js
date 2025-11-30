import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BR, BUTTON, CODE, EM, INPUT, OPTION, TD, TR} = choc; //autoimport
import {scan_message, commands, cmd_configure, open_advanced_view} from "$$static||command_editor.js$$";

cmd_configure({
	subscribe: "",
	get_command_basis: cmd => {
		if (cmd.cmdname[0] === "!") ; //TODO: Show specials differently
		set_content("#advanced_view h3", [
			"Command: ", INPUT({readonly: "true", autocomplete: "off", id: "cmdname", value: "!" + cmd.cmdname}),
		]);
		set_content("#save_advanced", "Revert to");
		DOM("#delete_advanced").hidden = true;
		return {type: "anchor_command"};
	},
});

const cmdnames = { };

let selected_command = "", search_filter = [], current_commands_only = false;
function is_hidden(msg) {
	if (selected_command !== "" && msg.cmdname !== selected_command) return true;
	for (let term of search_filter)
		if (!msg.searchme.includes(term)) return true;
	if (current_commands_only && !msg.active) return true;
}

export const render_parent = DOM("#commandview tbody");
export function render_item(msg) {
	cmdnames[msg.cmdname] = 1;
	msg.searchme = JSON.stringify(msg.message).toLowerCase(); //TODO maybe: Represent this in some more human-readable way
	const response = [];
	const msgstatus = { };
	let simpletext = scan_message(msg, msgstatus);
	if (msgstatus.whisper) response.push(EM("Response would be whispered"), BR());
	if (msgstatus.oneof) response.push(EM("One of:"), BR());
	if (typeof simpletext === "string") response.push(CODE(simpletext));
	else if (!simpletext) response.push(CODE("(Special command, unable to summarize)"));
	else simpletext.forEach(m => response.push(CODE(m), BR()));
	return TR({key: msg.id, "data-id": msg.id, ".hidden": is_hidden(msg)}, [
		TD(msg.created), //TODO: Use a date element and more human-friendly formatting
		TD(msg.active ? {} : {style: "font-style: italic", title: "Replaced/deleted version of this command"},
			CODE("!" + msg.cmdname)),
		TD(response),
		TD(BUTTON({type: "button", class: "advview", title: "Open editor"}, "\u2699")),
	]);
}
export function render(data) {
	const val = DOM("#pickcommand").value;
	set_content("#pickcommand", [
		OPTION({value: ""}, "- all -"),
		Object.keys(cmdnames).sort().map(cmd => OPTION(cmd)),
	]).value = val;
}

function update_visibility() {
	render_parent.querySelectorAll("tr").forEach(tr =>
		tr.hidden = is_hidden(commands[tr.dataset.id]));
}

on("change", "#pickcommand", e => {selected_command = e.match.value; update_visibility();});
function update_filter(e) {
	//TODO: Split in such a way that quoted strings remain together, and maybe
	//aren't case-folded. Search term ==> word word "this is a phrase"
	//Search filter ==> ["word", "word", "this is a phrase"]
	search_filter = e.match.value.toLowerCase().split(" ");
	update_visibility();
}
on("change", "#filter", update_filter);
on("input", "#filter", update_filter);
on("click", "#currentonly", e => {current_commands_only = e.match.checked; update_visibility();});
