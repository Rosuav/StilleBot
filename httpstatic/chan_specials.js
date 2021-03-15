import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {CODE, TR, TD, SPAN, INPUT} = choc;

let resp = { };
export function render(data) {
	if (data.id) resp[data.id] = data.data; //TODO: Properly handle partial updates
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
		]), TR({"data-id": cmd.id}, TD({colSpan: "4"}, [
			//TODO: Embed a command editor, including its Advanced button
			"Response:", SPAN({className: "gap"}), //Do I need this span still?
			INPUT({value: resp[cmd.id] ? resp[cmd.id].message : "", className: "widetext"}),
		]))));
		set_content("#commands tbody", rows);
	}
	return;
}

