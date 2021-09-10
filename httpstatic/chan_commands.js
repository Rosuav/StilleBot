import choc, {set_content, DOM} from "https://rosuav.github.io/shed/chocfactory.js";
const {BR, BUTTON, CODE, INPUT, TR, TD} = choc;
import {sockmsg_validated, sockmsg_loadfavs, favcheck, render_command, commands, cmd_configure, open_advanced_view} from "$$static||command_editor.js$$";
export {sockmsg_validated, sockmsg_loadfavs};

cmd_configure({
	get_command_basis: cmd => {
		const cmdname = "!" + cmd.id.split("#")[0];
		set_content("#advanced_view h3", ["Edit command ", INPUT({id: "cmdname", value: cmdname})]);
		return {type: "anchor_command", command: cmdname};
	},
});

on("click", 'a[href="/emotes"]', e => {
	e.preventDefault();
	window.open("/emotes", "emotes", "width=900, height=700");
});

export const render_parent = DOM("#commandview tbody");
export const render_item = render_command;
export function render(data) {
	favcheck();
	if (DOM("#addcmd")) render_parent.appendChild(DOM("#addcmd").closest("TR")); //Move to end w/o disrupting anything
	else render_parent.appendChild(TR([
		TD(["Add: ", INPUT({id: "newcmd_name", size: 10, placeholder: "!hype"})]),
		TD(INPUT({id: "newcmd_resp", className: "widetext"})),
		TD(BUTTON({type: "button", id: "addcmd"}, "Add")),
	]));
}

function addcmd() {
	const newcmd = DOM("#newcmd_name");
	const cmdname = newcmd.value, response = DOM("#newcmd_resp").value;
	newcmd.value = DOM("#newcmd_resp").value = "";
	if (cmdname !== "" && response !== "") {
		ws_sync.send({cmd: "update", cmdname, response});
		newcmd.closest("tr").classList.remove("dirty");
	}
	else open_advanced_view({message: "", id: cmdname.replace("!", ""), template: true});
}
on("submit", "main > form", e => {e.preventDefault(); addcmd();});
on("click", "#addcmd", addcmd);
