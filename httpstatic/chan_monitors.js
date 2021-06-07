import choc, {set_content, DOM, on, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, BR, BUTTON, DETAILS, SUMMARY, DIV, FORM, FIELDSET, LEGEND, INPUT, TEXTAREA, OPTION, OPTGROUP, SELECT, TABLE, TR, TH, TD} = choc;
fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: true});
import update_display from "$$static||monitor.js$$";
import {waitlate} from "$$static||utils.js$$";

/*
New plan: Bring graphical monitors into this module where they belong.
The main display will have:
* ID, invisible
* Preview (currently hidden)
* Edit button
* Delete button
* OBS-draggable link

All editing will be in a dialog.
*/

const editables = { };
function set_values(nonce, info, elem) {
	if (!info) return 0;
	for (let attr in info) {
		editables[nonce][attr] = info[attr];
		if (attr === "text" && info.type === "goalbar") { //FIXME: Probably broken after some other changes
			//For run distance, fracture this into the variable name and the actual text.
			const m = /^\$([^:$]+)\$:(.*)/.exec(info.text);
			console.log(info.text);
			console.log(m);
			const v = elem.querySelector("[name=varname]"); if (v) v.value = m[1];
			const t = elem.querySelector("[name=text]");    if (t) t.value = m[2];
			continue;
		}
		const el = elem.querySelector("[name=" + attr + "]");
		if (el) el.value = info[attr];
		if (attr === "lvlupcmd" && el) //Special case: the value might not work if stuff isn't loaded yet.
			el.dataset.wantvalue = info[attr]
	}
	if (info.type === "goalbar") {
		const el = elem.querySelector("[name=currentval]"); if (el) el.value = info.display.split(":")[0];
		update_tierpicker();
	}
	return elem;
}

export const render_parent = DOM("#monitors tbody");
export function render_item(msg, obj) {
	if (!msg) return 0;
	const nonce = msg.id;
	if (!editables[nonce] || msg.type) editables[nonce] = msg;
	else for (let attr in msg) editables[nonce][attr] = msg[attr]; //Partial update, keep the info we have
	const el = obj || TR({"data-nonce": nonce, "data-id": nonce}, [
		TD(DIV({className: "preview-frame"}, DIV({className: "preview-bg"}, DIV({className: "preview"})))),
		TD([
			BUTTON({type: "button", className: "editbtn"}, "Edit"),
			BUTTON({type: "button", className: "deletebtn", "data-nonce": nonce}, "Delete?"),
		]),
		TD(A({className: "monitorlink", href: "monitors?view=" + nonce}, "Drag me to OBS")),
	]);
	update_display(el.querySelector(".preview"), editables[nonce]);
	el.querySelector(".preview-bg").style.backgroundColor = editables[nonce].previewbg;
	const link = el.querySelector(".monitorlink");
	link.dataset.width = editables[nonce].width;
	link.dataset.height = editables[nonce].height;
	return el;
}
export function render_empty() {
	render_parent.appendChild(TR([
		TD({colSpan: 4}, "No monitors defined. Create one!"),
	]));
}
export function render(data) { }

//TODO: Build these from data in some much more maintainable way (cf commands advanced edit)
set_content("#edittext form div", TABLE({border: 1}, [
	TR([TH("Text"), TD(INPUT({size: 40, name: "text"}))]),
	TR([TH("Font"), TD([
		INPUT({name: "font", size: "28"}),
		SELECT({name: "fontweight"}, [OPTION("normal"), OPTION("bold")]),
		SELECT({name: "fontstyle"}, [OPTION("normal"), OPTION("italic")]),
		INPUT({name: "fontsize", type: "number", size: "3", value: "16"}),
		BR(), "Pick a font from Google Fonts or",
		BR(), "one that's already on your PC.",
	])]),
	TR([TH("Text color"), TD(INPUT({name: "color", type: "color"}))]),
	TR([TH("Preview bg"), TD(INPUT({name: "previewbg", type: "color"}))]),
	TR([TH("Border"), TD([
		"Width (px):", INPUT({name: "borderwidth", type: "number"}),
		"Color:", INPUT({name: "bordercolor", type: "color"}),
	])]),
	//TODO: Gradient?
	//TODO: Drop shadow?
	//TODO: Padding? Back end already supports padvert and padhoriz.
	TR([TH("Formatting"), TD(SELECT({name: "whitespace"}, [
		OPTGROUP({label: "Single line"}, [
			OPTION({value: "normal"}, "Wrapped"),
			OPTION({value: "nowrap"}, "No wrapping"),
		]),
		OPTGROUP({label: "Multi-line"}, [
			OPTION({value: "pre-line"}, "Normal"),
			OPTION({value: "pre"}, "Keep indents"),
			OPTION({value: "pre-wrap"}, "No wrapping"),
		]),
	]))]),
	TR([TH("Custom CSS"), TD(INPUT({name: "css", size: 40}))]),
]));

set_content("#editgoalbar form div", TABLE({border: 1}, [
	TR([TH("Variable"), TD(INPUT({name: "varname", size: 20}))]),
	TR([TH("Current"), TD([
		INPUT({name: "currentval", size: 10}),
		SELECT({name: "tierpicker"}),
		BUTTON({type: "button", id: "setval"}, "Set"),
		BR(), "NOTE: This will override any donations! Be careful!",
		BR(), "Changes made here are NOT applied with the Save button.",
	])]),
	TR([TH("Text"), TD([
		INPUT({name: "text", size: 60}),
		BR(), "Put a '#' where the current tier should go - it'll be replaced",
		BR(), "with the actual number.",
	])]),
	TR([TH("Goal(s)"), TD([
		INPUT({name: "thresholds", size: 60}),
		BR(), "For a tiered goal bar, set multiple goals eg '10 10 10 10 20 30 40 50'",
	])]),
	TR([TH("Font"), TD([
		INPUT({name: "font", size: 40}),
		SELECT({name: "fontweight"}, [OPTION("normal"), OPTION("bold")]),
		SELECT({name: "fontstyle"}, [OPTION("normal"), OPTION("italic")]),
		INPUT({name: "fontsize", type: "number", value: 16}),
		BR(), "Pick a font from Google Fonts or one that's",
		BR(), "already on your PC. (Name is case sensitive.)",
	])]),
	TR([TH("Colors"), TD(DIV({className: "optionset"}, [
		FIELDSET([LEGEND("Text"), INPUT({type: "color", name: "color"})]),
		FIELDSET([LEGEND("Bar"), INPUT({type: "color", name: "barcolor"})]),
		FIELDSET([LEGEND("Fill"), INPUT({type: "color", name: "fillcolor"})]),
		FIELDSET([LEGEND("Border"), INPUT({type: "color", name: "bordercolor"})]),
		FIELDSET([LEGEND("Preview bg"), INPUT({type: "color", name: "previewbg"})]),
	]))]),
	TR([TH("Bar size"), TD(DIV({className: "optionset"}, [
		FIELDSET([LEGEND("Width"), INPUT({type: "number", name: "width"})]),
		FIELDSET([LEGEND("H padding"), INPUT({type: "number", name: "padhoriz", min: 0, max: 2, step: "0.005"})]),
		FIELDSET([LEGEND("Height"), INPUT({type: "number", name: "height"})]),
		FIELDSET([LEGEND("V padding"), INPUT({type: "number", name: "padvert", min: 0, max: 2, step: "0.005"})]),
	]))]),
	TR([TH("Needle size"), TD([
		INPUT({name: "needlesize", type: "number", min: 0, max: 1, step: "0.005", value: 0.375}),
		"Thickness of the red indicator needle",
	])]),
	TR([TH("Format"), TD([
		SELECT({name: "format"}, [OPTION("plain"), OPTION("currency")]),
		"Display format for numbers. Currency uses cents - 2718 is $27.18.",
	])]),
	TR([TH("On level up"), TD([
		SELECT({name: "lvlupcmd", id: "cmdpicker"}, [OPTION("Loading...")]),
		BR(), "Add and edit commands ", A({href: "commands"}, "on the Commands page"),
	])]),
	TR([TH("Custom CSS"), TD(TEXTAREA({name: "css"}))]),
]));

on("submit", "dialog form", async e => {
	console.log(e.match.elements);
	const dlg = e.match.closest("dialog");
	const body = {nonce: dlg.dataset.nonce, type: dlg.id.slice(4)};
	("text varname " + css_attributes).split(" ").forEach(attr => {
		if (!e.match.elements[attr]) return;
		body[attr] = e.match.elements[attr].value;
	});
	console.log("Saving", body);
	const res = await fetch("monitors", {
		method: "PUT",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify(body),
	});
	if (!res.ok) console.error("Something went wrong in the save, check console"); //TODO: Report errors properly
});

on("click", "#add_text", e => {
	//TODO: Replace this with a ws message
	fetch("monitors", {method: "PUT", headers: {"Content-Type": "application/json"}, body: '{"text": ""}'});
});

on("click", "#add_goalbar", e => {
	fetch("monitors", {method: "PUT", headers: {"Content-Type": "application/json"}, body: '{"text": "$var$:...", "type": "goalbar"}'});
});

on("click", ".editbtn", e => {
	const nonce = e.match.closest("tr").dataset.id;
	const mon = editables[nonce];
	const dlg = DOM("#edit" + mon.type); if (!dlg) {console.error("Bad type", mon.type); return;}
	dlg.querySelector("form").reset();
	set_values(nonce, mon, dlg); //TODO: Break set_values into the part done on update and the part done here
	dlg.dataset.nonce = nonce;
	dlg.returnValue = "close";
	dlg.showModal();
});

on("click", ".deletebtn", waitlate(1000, 7500, "Really delete?", async e => {
	const nonce = e.match.dataset.nonce;
	console.log("Delete.");
	const res = await fetch("monitors", {
		method: "DELETE",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify({nonce}),
	});
	if (!res.ok) console.error("Something went wrong in the save, check console"); //TODO: Report errors properly
}));

on("dragstart", ".monitorlink", e => {
	const url = `${e.match.href}&layer-name=StilleBot%20monitor&layer-width=${e.match.dataset.width||400}&layer-height=${e.match.dataset.height||120}`;
	e.dataTransfer.setData("text/uri-list", url);
});

function update_tierpicker() {
	const thresholds = DOM("[name=thresholds]").value.split(" ");
	const pos = +DOM("[name=currentval]").value;
	const opts = [];
	thresholds.push(Infinity); //Place a known elephant in Cairo
	let val = -1, total = 0;
	for (let which = 0; which < thresholds.length; ++which) {
		//Record the *previous* total as the mark for this tier. If you pick
		//tier 3, the total should be set to the *start* of tier 3.
		const desc = which === thresholds.length - 1 ? "And beyond!" : "Tier " + (which + 1);
		const prevtotal = total;
		//TODO: Multiply by 100 only if working in currency
		//TODO: Do the multiplication by 100 only in the front end, as a visual thing,
		//and maybe even base it on the current locale's currency settings???
		total += 100 * +thresholds[which]; //What if thresholds[which] isn't numeric??
		opts.push(OPTION({value: prevtotal}, desc));
		if (val === -1 && pos < total) val = prevtotal;
	}
	set_content(DOM("[name=tierpicker]"), opts).value = val;
}
DOM("[name=thresholds]").onchange = DOM("[name=currentval]").onchange = update_tierpicker;
DOM("[name=tierpicker]").onchange = e => DOM("[name=currentval]").value = e.currentTarget.value;
DOM("#setval").onclick = async e => {
	const val = +DOM("[name=currentval]").value;
	if (val !== val) return; //TODO: Be nicer
	const rc = await fetch("run", {
		method: "PUT",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify({"var": DOM("[name=varname]").value, val}),
	});
	if (!rc.ok) {console.error("Couldn't update (TODO)"); return;}
}

function textify(cmd) {
	if (typeof cmd === "string") return cmd;
	if (Array.isArray(cmd)) return cmd.map(textify).filter(x => x).join(" // ");
	if (cmd.dest) return null; //Suppress special-destination sections
	return cmd.message;
}
function shorten(txt, len) {
	if (txt.length <= len) return txt;
	return txt.slice(0, len - 1) + "..."; //I really want a width-based shorten, but CSS won't max-width an option
}
const commands = { };
ws_sync.connect(ws_group, {
	ws_type: "chan_commands",
	select: DOM("#cmdpicker"),
	make_option: cmd => OPTION({"data-id": cmd.id, value: cmd.id.split("#")[0]}, "!" + cmd.id.split("#")[0] + " -- " + shorten(textify(cmd.message), 75)),
	is_recommended: cmd => cmd.access === "none" && cmd.visibility === "hidden",
	render: function(data) {
		if (data.id) {
			const opt = select.querySelector(`[data-id="${data.id}"]`);
			//Note that a partial update (currently) won't move a command between groups.
			if (opt) set_content(opt, "!" + cmd.id.split("#")[0] + " -- " + textify(cmd.message)); //TODO: dedup
			else this.groups[this.is_recommended(cmd) ? 1 : 2].appendChild(this.make_option(cmd));
			commands[data.id] = data;
			return;
		}
		if (!this.groups) set_content(this.select, this.groups = [
			OPTGROUP({label: "None"}, OPTION({value: ""}, "No response - levels will pass silently")),
			OPTGROUP({label: "Recommended"}),
			OPTGROUP({label: "Other"}),
		]);
		const blocks = [[], []];
		data.items.forEach(cmd => blocks[this.is_recommended(cmd) ? 0 : 1].push(this.make_option(commands[cmd.id] = cmd)));
		set_content(this.groups[1], blocks[0]);
		set_content(this.groups[2], blocks[1]);
		const want = this.select.dataset.wantvalue;
		if (want) this.select.value = want;
	},
});
