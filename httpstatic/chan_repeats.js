import choc, {set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, CODE, INPUT, TD, TR} = choc; //autoimport
import {sockmsg_validated, scan_message, commands, cmd_configure, open_advanced_view} from "$$static||command_editor.js$$";
export {sockmsg_validated};

cmd_configure({
	get_command_basis: cmd => {
		const cmdname = "!" + cmd.id.split("#")[0];
		set_content("#advanced_view h3", ["Edit command ", INPUT({autocomplete: "off", id: "cmdname", value: cmdname})]);
		check_save();
		return {type: "anchor_command"};
	},
	location_format: (cmd_id, tab) => null, //Disable insertion of command IDs into the location hash
});

function check_save() {DOM("#save_advanced").disabled = DOM("#cmdname").value.replace("!", "").trim() === "";}
on("input", "#cmdname", check_save);

export const render_parent = DOM("#commandview tbody");
export function render_item(msg) {
	if (!msg.automate || msg.alias_of) return null;
	const response = [];
	const msgstatus = { };
	let simpletext = scan_message(msg, msgstatus);
	if (msgstatus.oneof) response.push(EM("One of:"), BR());
	if (typeof simpletext === "string") response.push(INPUT({value: simpletext, className: "widetext"}));
	else if (!simpletext) response.push(CODE("(Special command, unable to summarize)")); //Not going to be common. Get some examples before rewording this.
	else simpletext.forEach(m => response.push(CODE(m), BR()));
	commands[msg.id] = msg;
	const mate = typeof msg.automate === "number" ? [msg.automate, msg.automate, 0] : msg.automate; //Ancient legacy
	const target = mate[2] ? ("0" + mate[0]).slice(-2) + ":" + ("0" + mate[1]).slice(-2)
		: mate[0] === mate[1] ? ""+mate[0]
		: mate[0] + "-" + mate[1];
	return TR({"data-id": msg.id, "data-editid": msg.id}, [
		TD(INPUT({value: target, class: "narrow"})),
		TD(CODE("!" + msg.id.split("#")[0])),
		TD(response),
		TD(BUTTON({type: "button", className: "advview", title: "Open editor"}, "\u2699")),
	]);
}
export function render(data) {
	return;
	//TODO: Have an add that does something like this but not so generic
	if (DOM("#addcmd")) render_parent.appendChild(DOM("#addcmd").closest("TR")); //Move to end w/o disrupting anything
	else render_parent.appendChild(TR([
		TD(CODE("--")),
		TD(["Add: ", INPUT({id: "newcmd_name", size: 10, placeholder: "!hype"})]),
		TD(INPUT({id: "newcmd_resp", className: "widetext"})),
		TD(BUTTON({type: "button", id: "addcmd"}, "Add")),
	]));
}
//TODO: When gear-opening a thing, open its basis immediately
