import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {CODE, TR, TD, SPAN, INPUT} = choc;
import {render_item as render_command} from "./chan_commands.js"; //TODO: Can I hook the static updates handling?

let resp = { };
export function render(data) {
	if (data.id) {
		const obj = DOM("#commands tbody").querySelector(`[data-id="${data.id}"]`);
		if (!obj) return; //All objects should be created by the initial pass (see below)
		obj.replaceWith(render_command(data.data || {id: cmd.id, message: ""}, obj));
	}
	else {
		//Remap the data to be a lookup, then loop through the expected commands
		resp = { };
		data.items.forEach(c => resp[c.id] = c);
		const rows = []; //Map the commands to two TRs each
		commands.forEach(cmd => rows.push(TR({className: "gap"}, [
			TD(CODE("!" + cmd.id.split("#")[0])),
			TD(cmd.desc),
			TD(cmd.originator),
			TD(cmd.params),
		]), render_command(resp[cmd.id] || {id: cmd.id, message: ""})));
		set_content("#commands tbody", rows);
	}
	return;
}

