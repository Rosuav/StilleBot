import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, BR, BUTTON, INPUT, DIV, DETAILS, LABEL, SUMMARY, TABLE, TR, TH, TD, SELECT, OPTION, FIELDSET, LEGEND, CODE} = choc;
fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: "formless"});

let lines = [];

on("input", "#content", e => {
	const l = e.match.value.split("\n");
	//Scan backwards to find the trailing matches
	let last_old = lines.length, last_new = l.length;
	while (last_old > 0 && last_new > 0 && lines[last_old - 1].content == l[last_new - 1]) {
		--last_old; --last_new;
	}
	if (!last_old && !last_new) return; //This change apparently did nothing - the trailing matches are the whole document.
	//Scan forwards to find the leading matches
	let i = 0;
	while (i < last_old && i < last_new && lines[i].content == l[i]) ++i;
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

const mle = DOM("#content");
export function render(data) {
	if (data.html) {
		//Rendered version, not editable
		mle.innerHTML = data.html;
		return;
	}
	const l = mle.value.split("\n");
	let startrow = 0, startcol = mle.selectionStart, endrow = 0, endcol = mle.selectionEnd;
	let starttail = "", endtail = "", startrowlen = 0, endrowlen = 0;
	const dir = mle.selectionDirection;
	for (let old of l) {
		if (startcol > old.length + 1) {++startrow; startcol -= old.length + 1;}
		else {starttail = old.slice(startcol); startrowlen = old.length; break;}
	}
	startrow = lines[startrow] ? lines[startrow].id : "";
	for (let old of l) {
		if (endcol > old.length + 1) {++endrow; endcol -= old.length + 1;}
		else {endtail = old.slice(endcol); endrowlen = old.length; break;}
	}
	endrow = lines[endrow] ? lines[endrow].id : "";
	if (data.id) {
		//Partial update
		const srv = data.data;
		if (srv.position < 0 || srv.position >= lines.length) {
			//Something's desynchronized. I don't care what, why, or how; just
			//request a full update.
			ws_sync.send({cmd: "refresh"});
			return;
		}
		lines[srv.position] = srv;
	}
	else {
		//Full/initial update
		lines = data.items;
	}
	mle.value = lines.map(item => item.content).join("\n");
	for (let now of lines) {
		if (now.id === startrow) {
			if (now.content.endsWith(starttail)) startcol += now.content.length - startrowlen;
			break;
		}
		startcol += now.content.length + 1;
	}
	for (let now of lines) {
		if (now.id === endrow) {
			if (now.content.endsWith(endtail)) endcol += now.content.length - endrowlen;
			break;
		}
		endcol += now.content.length + 1;
	}
	mle.setSelectionRange(startcol, endcol, dir);
}
