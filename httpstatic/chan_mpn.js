import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, BR, BUTTON, INPUT, DIV, DETAILS, LABEL, SUMMARY, TABLE, TR, TH, TD, SELECT, OPTION, FIELDSET, LEGEND, CODE} = choc;
fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: true});

let lines = [];

on("input", "#content", e => {
	console.log("Change!");
	const l = e.match.value.split("\n");
	//Scan backwards to find the trailing matches
	let last_old = lines.length, last_new = l.length;
	while (last_old > 0 && last_new > 0 && lines[last_old - 1] == l[last_new - 1]) {
		--last_old; --last_new;
	}
	if (!last_old && !last_new) return; //This change apparently did nothing - the trailing matches are the whole document.
	//Scan forwards to find the leading matches
	let i = 0;
	while (i < last_old && i < last_new && lines[i] == l[i]) ++i;
	//Okay, we now have the changes.
	while (i < last_old && i < last_new) {
		//Consider this to be a changed line
		ws_sync.send({cmd: "update", id: lines[i].id, content: l[i]});
		++i;
	}
	while (i < last_old) {
		//We've run out of new lines (hah!) so these need to be deleted.
		ws_sync.send({cmd: "update", id: lines[i].id});
		++i;
	}
	const before = last_old < lines.length ? lines[last_old].id : "0";
	while (i < last_new) {
		//We've run out of old lines so these get inserted.
		ws_sync.send({cmd: "update", id: "0", before, content: l[i]});
		++i;
	}
});

export function render(data) {
	if (data.id) {
		console.log("Partial update");
	}
	else {
		console.log("Full/initial update");
		//TODO: Get cursor position as line,col and restore it after
		lines = data.items;
		DOM("#content").value = lines.map(item => item.content).join("\n");
	}
}
