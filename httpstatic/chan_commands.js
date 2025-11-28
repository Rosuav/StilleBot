import choc, {set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, INPUT, TR, TD} = choc;
import {render_command, commands, cmd_configure, open_advanced_view} from "$$static||command_editor.js$$";

cmd_configure({
	get_command_basis: cmd => {
		const cmdname = "!" + cmd.id.split("#")[0];
		set_content("#advanced_view h3", ["Edit command ", INPUT({autocomplete: "off", id: "cmdname", value: cmdname})]);
		check_save();
		return {type: "anchor_command"};
	},
});
ws_sync.send({cmd: "subscribe", type: "cmdedit", group: ""});

function check_save() {DOM("#save_advanced").disabled = DOM("#cmdname").value.replace("!", "").trim() === "";}
on("input", "#cmdname", check_save);

export const render_parent = DOM("#commandview tbody");
export const render_item = render_command;
export function render(data) {
	if (DOM("#addcmd")) render_parent.appendChild(DOM("#addcmd").closest("TR")); //Move to end w/o disrupting anything
	else render_parent.appendChild(TR([
		TD(["Add: ", INPUT({id: "newcmd_name", size: 10, placeholder: "!hype"})]),
		TD(INPUT({id: "newcmd_resp", className: "widetext"})),
		TD(BUTTON({type: "button", id: "addcmd"}, "Add")),
	]));
}

function addcmd(mode) {
	const newcmd = DOM("#newcmd_name");
	const cmdname = newcmd.value, response = DOM("#newcmd_resp").value;
	newcmd.value = DOM("#newcmd_resp").value = "";
	if (cmdname !== "" && response !== "") {
		ws_sync.send({cmd: "update", cmdname, response});
		newcmd.closest("tr").classList.remove("dirty");
	}
	else if (mode !== "saveall" || cmdname || response)
		open_advanced_view({message: response, id: cmdname.replace("!", ""), template: true});
}
on("click", "#saveall", e => {e.preventDefault(); addcmd("saveall");});
on("click", "#addcmd", addcmd);

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
