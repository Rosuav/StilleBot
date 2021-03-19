import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {CODE, BR, TR, TD, SPAN, INPUT} = choc;
import {render_item as render_command} from "$$static||chan_commands.js$$";

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
			TR(TD({colSpan: 3}, [
				"Happens when: " + cmd.desc, BR(),
				CODE("$$"), ": ", cmd.originator, BR(),
				"Other parameters: " + cmd.params,
			])),
		));
		set_content("#commands tbody", rows);
	}
	return;
}

