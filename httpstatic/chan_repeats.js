import choc, {set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BR, BUTTON, CODE, EM, INPUT, TD, TR} = choc; //autoimport
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
	if (typeof simpletext === "string") response.push(INPUT({value: simpletext, class: "text widetext"}));
	else if (!simpletext) response.push(CODE("(Special command, unable to summarize)")); //Not going to be common. Get some examples before rewording this.
	else simpletext.forEach(m => response.push(CODE(m), BR()));
	commands[msg.id] = msg;
	const mate = typeof msg.automate === "number" ? [msg.automate, msg.automate, 0] : msg.automate; //Ancient legacy
	const target = mate[2] ? ("0" + mate[0]).slice(-2) + ":" + ("0" + mate[1]).slice(-2)
		: mate[0] === mate[1] ? ""+mate[0]
		: mate[0] + "-" + mate[1];
	return TR({"data-id": msg.id, "data-editid": msg.id}, [
		TD(CODE("!" + msg.id.split("#")[0])),
		TD(INPUT({value: target, class: "automate narrow"})),
		TD({class: "wrap"}, response),
		TD(BUTTON({type: "button", className: "advview", title: "Open editor"}, "\u2699")),
	]);
}
export function render(data) {
	if (DOM("#addcmd")) render_parent.appendChild(DOM("#addcmd").closest("TR")); //Move to end w/o disrupting anything
	else render_parent.appendChild(TR([
		TD("Add new"),
		TD(INPUT({id: "newcmd_automate", class: "automate narrow"})),
		TD(INPUT({id: "newcmd_resp", class: "widetext"})),
		TD(BUTTON({type: "button", id: "addcmd"}, "Add")),
	]));
}

function addcmd(mode) {
	const automate = DOM("#newcmd_automate").value, response = DOM("#newcmd_resp").value;
	DOM("#newcmd_automate").value = DOM("#newcmd_resp").value = "";
	//Generate a command name: "!autoNN" where NN increments till it isn't found
	let cmdname;
	for (let i = 1; commands[(cmdname = "auto" + i) + ws_group]; ++i) ;
	if (automate !== "" && response !== "") {
		ws_sync.send({cmd: "update", cmdname, response: {automate, access: "none", message: response}});
		DOM("#newcmd_automate").closest("tr").classList.remove("dirty");
	}
	else if (mode !== "saveall" || automate || response)
		open_advanced_view({automate, access: "none", message: response, id: cmdname, template: true});
}
on("click", "#addcmd", addcmd);

//Very similar to, but not compatible with, #saveall handling in command_editor.js
on("click", "#savechanges", e => {
	e.preventDefault();
	addcmd("saveall");
	document.querySelectorAll("tr.dirty[data-id]").forEach(tr => {
		//Take a copy of the original command (we're going to JSON-encode it anyway, so this should
		//be safe) and inject the new message text into it.
		let response = JSON.parse(JSON.stringify(commands[tr.dataset.id]));
		const inp = tr.querySelector("input.text");
		if (inp) {
			const msg = inp.value;
			if (!msg) {
				ws_sync.send({cmd: "delete", cmdname: tr.dataset.id}, "cmdedit");
				return;
			}
			if (typeof response === "string") response = msg;
			else scan_message(response, {replacetext: msg});
		}
		const automate = tr.querySelector("input.automate").value;
		if (!automate) {
			//If you blank the automation and the command has no other invocations,
			//remove the command. TODO: Prompt the user first?
			//Ensure that this always gets other invocations added to it.
			if (response.access === "none" && !response.redemption) {
				ws_sync.send({cmd: "delete", cmdname: tr.dataset.id}, "cmdedit");
				return;
			}
		}
		response.automate = automate; //Push to the back end as a string; it comes back as an array.
		ws_sync.send({cmd: "update", cmdname: tr.dataset.id, response}, "cmdedit");
		//Note that the dirty flag is not reset. A successful update will trigger
		//a broadcast message which, when it reaches us, will rerender the command
		//completely, thus effectively resetting dirty.
	});
});
