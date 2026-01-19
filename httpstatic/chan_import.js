import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {B, BR, BUTTON, CODE, DETAILS, INPUT, LABEL, LI, P, TEXTAREA, UL} = lindt; //autoimport

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
	const warnings = Object.entries(msg.warnings).sort((a, b) => a[0].localeCompare(b[0]));
	replace_content("#deepbot_results", [
		P([
			LABEL([INPUT({type: "checkbox", class: "selectall", checked: true}), " Select All"]),
			" ",
			BUTTON({class: "import_selected"}, "Import selected"),
		]),
		warnings.length && P({class: "warning"}, [
			warnings.length + " commands have potential issues and have not been preselected for import. ",
			DETAILS(UL(warnings.map(([cmd, msgs]) => LI([CODE(B(cmd)), UL(msgs.map(m => LI(m)))])))),
		]),
		UL(msg.commands.map(cmd => LI([
			LABEL([INPUT({type: "checkbox", checked: !cmd.inactive && !msg.warnings[cmd.cmdname], "data-cmdname": cmd.cmdname, "data-mustard": cmd.mustard}), " ", CODE(cmd.cmdname)]),
			TEXTAREA({style: "height: 8em", readonly: true}, cmd.mustard),
		]))),
		P([
			LABEL([INPUT({type: "checkbox", class: "selectall", checked: true}), " Select All"]),
			" ",
			BUTTON({class: "import_selected"}, "Import selected"),
		]),
	]);
}

on("click", ".selectall", e => {
	const state = e.match.checked;
	//Note that this will catch both of the Select All checkboxes too
	DOM("#deepbot_results").querySelectorAll("input[type=checkbox]").forEach(cb => cb.checked = state);
});

let importme = [];
on("click", ".import_selected", e => {
	const commands = [];
	DOM("#deepbot_results").querySelectorAll("input[type=checkbox]:checked").forEach(cb =>
		cb.dataset.cmdname && commands.push({cmdname: cb.dataset.cmdname, mustard: cb.dataset.mustard}));
	if (!commands.length) {
		replace_content("#import_description", "No commands selected");
		DOM("#confirmimport").disabled = true;
	} else {
		replace_content("#import_description", [
			"Will import the following " + commands.length + " commands:",
			commands.map(cmd => [" ", CODE(cmd.cmdname)]),
			BR(),
			"Confirm that these should be imported, replacing any existing commands of the same names?",
		]);
		DOM("#confirmimport").disabled = false;
	}
	importme = commands;
	DOM("#importconfirmdlg").showModal();
});

on("click", "#confirmimport", e => {ws_sync.send({cmd: "deepbot_import", commands: importme}); DOM("#importconfirmdlg").close();});