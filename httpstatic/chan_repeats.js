import choc, {set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, CODE, INPUT, TD, TR} = choc; //autoimport
import {sockmsg_validated, render_command, commands, cmd_configure, open_advanced_view} from "$$static||command_editor.js$$";
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

function show_automation(msg) {
	const mate = typeof msg.automate === "number" ? [msg.automate, msg.automate, 0] : msg.automate; //Ancient legacy
	const target = mate[2] ? ("0" + mate[0]).slice(-2) + ":" + ("0" + mate[1]).slice(-2)
		: mate[0] === mate[1] ? ""+mate[0]
		: mate[0] + "-" + mate[1];
	return TD(CODE(target));
}
export const render_parent = DOM("#commandview tbody");
export function render_item(msg) {
	if (!msg.automate) return null;
	return render_command(msg, show_automation);
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
