import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, B, BUTTON, CODE, DETAILS, DIV, INPUT, LABEL, LI, STYLE, SUMMARY, TD, TR, UL} = choc; //autoimport
import {render_command, cmd_configure, sockmsg_validated} from "$$static||command_editor.js$$";
export {sockmsg_validated};

let command_lookup = { };

const describe_param = (p, desc) => LI([CODE(p), " - " + desc]);
function describe_all_params(cmd) {
	return [describe_param("$$", cmd.originator), describe_param("{uid}", "ID of that person")].concat(
		cmd.params.split(", ").map(p => p && describe_param("{" + p + "}", SPECIAL_PARAMS[p]))
	);
}

const TAB_HEADINGS = {
	"Giveaways": () => ["Make giveaways happen ", A({href: "giveaway"}, "via their own page")],
	"Ko-fi": () => [B("NOTE:"), " Ko-fi integrations require setup - ", A({href: "kofi"}, "see here")],
};

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
			if (!tabs[tab]) {
				tabs.push(tab);
				tabs[tab] = cmd.tab;
				if (TAB_HEADINGS[cmd.tab]) rows.push(
					TR({className: "gap", "data-tabid": tab}, []),
					TR({"data-tabid": tab}, TD({colSpan: 3}, TAB_HEADINGS[cmd.tab]()))
				);
			}
			const row = render_command(resp[cmd.id] || {id: cmd.id, message: ""});
			row.dataset.tabid = tab;
			rows.push(
				TR({className: "gap", "data-tabid": tab}, []),
				row,
				TR({"data-tabid": tab}, TD({colSpan: 3}, [
					DETAILS([
						SUMMARY("Happens when: " + cmd.desc),
						"Parameters: ",
						UL(describe_all_params(command_lookup[cmd.id] = cmd)),
					]),
					cmd.scopes_required === "bcaster" ? [
						B("NOTE:"),
						" Requires broadcaster authentication. This trigger will not currently be functional.",
					] : cmd.scopes_required && [
						B("NOTE:"),
						"Requires authentication. ",
						BUTTON({class: "twitchlogin", "data-scopes": cmd.scopes_required}, "Authenticate"),
					],
					//Link to https://sikorsky.rosuav.com/reauth?bcaster=channel:read:polls or whatever scope is needed
				])),
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
		//NOTE: If the hash is requesting that the editor be opened, we won't select a tab here.
		//Instead, get_command_basis() below will do the tab selection.
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

DOM("#advanced_view").addEventListener("close", () => {
	//On the specials page, we use hash links for the tabs, as well as the individual commands.
	history.replaceState(null, "", "#" + DOM("#commands").dataset.rb.slice(4));
});

cmd_configure({
	get_command_basis: command => {
		const cmd = command_lookup[command.id], basis = {type: "anchor_special"};
		//Select the appropriate tab for this command
		const tab = cmd.tab.replace(" ", "-");
		DOM("#commands").dataset.rb = "tab-" + tab;
		DOM("#tab-" + tab).checked = true;
		set_content("#advanced_view h3", ["Edit special response ", CODE("!" + command.id.split("#")[0])]);
		const params = {"{username}": cmd.originator, "{uid}": "ID of that person"};
		cmd.params.split(", ").forEach(p => p && (params["{" + p + "}"] = SPECIAL_PARAMS[p]));
		basis._provides = params;
		basis._desc = "Happens when: " + cmd.desc;
		basis._shortdesc = cmd.desc; //Needs to be even shorter though
		return basis;
	},
});
