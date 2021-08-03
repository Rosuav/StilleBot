import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {CODE, BR, TABLE, TR, TH, TD, SPAN, DIV, DETAILS, SUMMARY, UL, LI, INPUT, LABEL, STYLE} = choc;
import {render_item as render_command, add_hook, sockmsg_validated} from "$$static||chan_commands.js$$";
export {sockmsg_validated};

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
		const row = render_command(data.data || {id: data.id, message: ""});
		row.dataset.tabid = obj.dataset.tabid;
		obj.replaceWith(row);
	}
	else {
		//Remap the data to be a lookup, then loop through the expected commands
		const resp = { };
		data.items.forEach(c => resp[c.id] = c);
		const rows = []; //Map each command to multiple TRs
		const tabs = [];
		commands.forEach(cmd => {
			const tab = cmd.tab.replace(" ", "-");
			if (!tabs[tab]) {tabs.push(tab); tabs[tab] = cmd.tab;}
			const row = render_command(resp[cmd.id] || {id: cmd.id, message: ""});
			row.dataset.tabid = tab;
			rows.push(
				TR({className: "gap", "data-tabid": tab}, []),
				row,
				TR({"data-tabid": tab}, TD({colSpan: 3}, DETAILS([
					SUMMARY("Happens when: " + cmd.desc),
					"Parameters: ",
					UL(describe_all_params(command_lookup[cmd.id] = cmd)),
				]))),
			);
		});
		set_content("#commands tbody", rows);
		set_content("#tabset", tabs.map(tab => {
			return DIV({className: "tab"}, [
				STYLE(`#commands[data-rb="tab-${tab}"] tr[data-tabid="${tab}"] {display: table-row;}`), //Who needs a medical degree when you can do this?
				INPUT({type: "radio", name: "tabselect", className: "tabradio", id: "tab-" + tab}),
				LABEL({htmlFor: "tab-" + tab, className: "tablabel"}, tabs[tab]),
			]);
		}));
		let tab = tabs[0];
		if (location.hash && tabs.includes(location.hash.slice(1))) tab = location.hash.slice(1);
		DOM("#commands").dataset.rb = "tab-" + tab;
		DOM("#tab-" + tab).checked = true;
	}
	return;
}
on("click", ".tabradio", e => {
	DOM("#commands").dataset.rb = e.match.id;
	history.replaceState(null, "", "#" + e.match.id.slice(4));
});

add_hook("open_advanced", cmd => set_content("#parameters", describe_all_params(command_lookup[cmd.id])));
