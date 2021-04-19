import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {CODE, BR, TR, TD, SPAN, DIV, DETAILS, SUMMARY, UL, LI, INPUT} = choc;
import {render_item as render_command, add_hook} from "$$static||chan_commands.js$$";

let command_lookup = { };
function describe_param(p, desc) {
	//TODO: Make them clickable to insert that token in the current EF??
	return LI([CODE(p), " - " + desc]);
}

function describe_all_params(cmd) {
	return [describe_param("$$", cmd.originator)].concat(
		cmd.params.split(", ").map(p => p && describe_param("{" + p + "}", SPECIAL_PARAMS[p]))
	);
}

export function render(data) {
	if (data.id) {
		const obj = DOM("#commands tbody").querySelector(`[data-id="${data.id}"]`);
		if (!obj) return; //All objects should be created by the initial pass (see below)
		obj.replaceWith(render_command(data.data || {id: data.id, message: ""}, obj));
	}
	else {
		//Remap the data to be a lookup, then loop through the expected commands
		const resp = { };
		data.items.forEach(c => resp[c.id] = c);
		const rows = []; //Map the commands to two TRs each
		commands.forEach(cmd => rows.push(
			render_command(resp[cmd.id] || {id: cmd.id, message: ""}),
			TR(TD({colSpan: 3}, DETAILS([
				SUMMARY("Happens when: " + cmd.desc),
				"Parameters: ",
				UL(describe_all_params(command_lookup[cmd.id] = cmd)),
			]))),
			TR({className: "gap"}, []),
		));
		set_content("#commands tbody", rows);
	}
	return;
}

add_hook("open_advanced", cmd => set_content("#parameters", describe_all_params(command_lookup[cmd.id])));
