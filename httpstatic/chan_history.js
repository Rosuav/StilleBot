import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BR, BUTTON, CODE, EM, INPUT, TD, TR} = choc; //autoimport
import {scan_message, register_command, commands, cmd_configure, open_advanced_view} from "$$static||command_editor.js$$";

cmd_configure({
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

export const render_parent = DOM("#commandview tbody");
export function render_item(msg) {
	register_command(msg);
	//commands[msg.id] = msg.content;
	const response = [];
	const msgstatus = { };
	let simpletext = scan_message(msg, msgstatus);
	if (msgstatus.whisper) response.push(EM("Response would be whispered"), BR());
	if (msgstatus.oneof) response.push(EM("One of:"), BR());
	if (typeof simpletext === "string") response.push(CODE(simpletext));
	else if (!simpletext) response.push(CODE("(Special command, unable to summarize)"));
	else simpletext.forEach(m => response.push(CODE(m), BR()));
	return TR({key: msg.id, "data-id": msg.id}, [
		TD(msg.created), //TODO: Use a date element and more human-friendly formatting
		TD(msg.active ? {} : {style: "font-style: italic", title: "Replaced/deleted version of this command"},
			CODE("!" + msg.cmdname)),
		TD(response),
		TD(BUTTON({type: "button", class: "advview", title: "Open editor"}, "\u2699")),
	]);
}
export function render(data) { }
