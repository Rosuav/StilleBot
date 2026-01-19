import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {CODE, INPUT, LABEL, LI, P, TEXTAREA, UL} = lindt; //autoimport

export function render(data) {
}

on("click", "#import_deepbot", e => {
	try {
		//We could shortcut this and keep the raw text to send down the websocket, but
		//this way we get an immediate response in the front end if the JSON is malformed.
		const decoded = JSON.parse(DOM("#deepbot_commands").value);
		ws_sync.send({cmd: "deepbot_translate", commands: decoded, include_groups: DOM("#include_groups").checked});
	} catch (e) {
		replace_content("#deepbot_results", "ERROR: " + e);
	}
});

export function sockmsg_translated(msg) {
	replace_content("#deepbot_results", [
		P([
			LABEL([INPUT({type: "checkbox", id: "selectall", checked: true}), " Select All"]),
		]),
		UL(msg.commands.map(cmd => LI([
			LABEL([INPUT({type: "checkbox", checked: !cmd.inactive}), " ", CODE(cmd.cmdname)]),
			TEXTAREA({style: "height: 8em", readonly: true}, cmd.mustard),
		]))),
	]);
}

on("click", "#selectall", e => {
	const state = e.match.checked;
	DOM("#deepbot_results").querySelectorAll("input[type=checkbox]").forEach(cb => cb.checked = state);
});
