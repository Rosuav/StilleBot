import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, BR, BUTTON, CODE, DIV, FIELDSET, LEGEND, LABEL, INPUT, TEXTAREA, OPTION, OPTGROUP, SELECT, TABLE, TR, TH, TD} = choc;
import update_display from "$$static||monitor.js$$";
import {waitlate} from "$$static||utils.js$$";

const editables = { };
function set_values(nonce, info, elem) {
	if (!info) return 0;
	for (let attr in info) {
		if (attr === "text" && info.type === "goalbar") {
			//Fracture text into the variable name and the actual text.
			const m = /^\$([^:$]+)\$:(.*)/.exec(info.text);
			const v = elem.querySelector("[name=varname]"); if (v) v.value = m[1];
			const t = elem.querySelector("[name=text]");    if (t) t.value = m[2];
			continue;
		}
		const el = elem.querySelector("[name=" + attr + "]");
		if (!el) continue;
		if (el.type === "checkbox") el.checked = info[attr];
		else el.value = info[attr];
		if (attr === "lvlupcmd") //Special case: the value might not work if stuff isn't loaded yet.
			el.dataset.wantvalue = info[attr];
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
	setTimeout(() => { //Wait till the preview has rendered, then measure it for the link
		const box = el.querySelector(".preview").getBoundingClientRect();
		const link = el.querySelector(".monitorlink");
		link.dataset.width = Math.round(box.width);
		link.dataset.height = Math.round(box.height);
	}, 50);
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
	TR([TH("Active"), TD(LABEL([INPUT({name: "active", type: "checkbox"}), "Enable auto-advance and level up messages"]))]),
	TR([TH("Variable"), TD([
		SELECT({name: "varname"}, OPTION("loading...")),
		" Or create a new one: ",
		INPUT({id: "newvarname", size: 20}),
		BUTTON({type: "button", id: "createvar"}, "Create"),
	])]),
	TR([TH("Current"), TD([
		"Value:", INPUT({name: "currentval", size: 10}),
		"Or tier:", SELECT({name: "tierpicker"}),
		BUTTON({type: "button", id: "setval"}, "Set"),
		BR(), "NOTE: This will override any automatic advancement! Be careful!",
		BR(), "Changes made here are NOT applied with the Save button.",
	])]),
	TR([TH("Text"), TD([
		INPUT({name: "text", size: 60}),
		BR(), "For tiered goals, put a '#' for the current tier - it'll be replaced",
		BR(), "with the actual number.",
	])]),
	TR([TH("Goal(s)"), TD([
		INPUT({name: "thresholds", size: 60}),
		BR(), "To make a tiered goal bar, set multiple goals eg '", CODE("10 10 10 10 20 30 40 50"), "'",
		BR(), "For currency, use values in cents (eg 1000 for $10)",
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
		FIELDSET([LEGEND("Width"), INPUT({type: "number", name: "width"}), "px"]),
		FIELDSET([LEGEND("H padding"), INPUT({type: "number", name: "padhoriz", min: 0, max: 2, step: "0.005"}), "em"]),
		FIELDSET([LEGEND("Height"), INPUT({type: "number", name: "height"}), "px"]),
		FIELDSET([LEGEND("V padding"), INPUT({type: "number", name: "padvert", min: 0, max: 2, step: "0.005"}), "em"]),
	]))]),
	TR([TH("Needle size"), TD([
		INPUT({name: "needlesize", type: "number", min: 0, max: 1, step: "0.005", value: 0.375}),
		"Thickness of the red indicator needle",
	])]),
	TR([TH("Format"), TD([
		SELECT({name: "format"}, [OPTION("plain"), OPTION("currency")]),
		"Display format for numbers. Currency uses cents - 2718 is $27.18.",
		BR(), "TODO: Allow selection of currency eg GBP to change the displayed unit",
	])]),
	TR([TH("Auto-count"), TD([
		"Automatically advance the goal bar based on stream support",
		DIV({className: "optionset"}, [
			FIELDSET([LEGEND("Bits"), INPUT({type: "number", name: "bit"}), "per bit"]),
			FIELDSET([LEGEND("T1 sub"), INPUT({type: "number", name: "sub_t1"})]),
			FIELDSET([LEGEND("T2 sub"), INPUT({type: "number", name: "sub_t2"})]),
			FIELDSET([LEGEND("T3 sub"), INPUT({type: "number", name: "sub_t3"})]),
			FIELDSET([LEGEND("Tip (each cent)"), INPUT({type: "number", name: "tip"})]), //TODO: Show somewhere what it takes to make this work
			FIELDSET([LEGEND("Follow"), INPUT({type: "number", name: "follow"})]),
			//FIELDSET([LEGEND("Raid"), INPUT({type: "number", name: "raid"})]), //Maybe have a tiered system for size of raid???
		]),
		"For events not listed, create a command or trigger (TODO - example)",
	])]),
	TR([TH("On level up"), TD([
		SELECT({name: "lvlupcmd", id: "cmdpicker"}, [OPTION("Loading...")]),
		BR(), "Add and edit commands ", A({href: "commands"}, "on the Commands page"),
	])]),
	TR([TH("Custom CSS"), TD(TEXTAREA({name: "css"}))]),
]));

on("click", "#createvar", e => {
	const varname = /^[A-Za-z]*/.exec(DOM("#newvarname").value);
	if (!varname || varname[0] === "") return;
	DOM("[name=varname]").appendChild(OPTION(varname[0]));
	DOM("[name=varname]").value = varname[0];
	ws_sync.send({cmd: "createvar", varname: varname[0]});
});

on("submit", "dialog form", async e => {
	console.log(e.match.elements);
	const dlg = e.match.closest("dialog");
	const body = {nonce: dlg.dataset.nonce, type: dlg.id.slice(4)};
	("text varname " + css_attributes).split(" ").forEach(attr => {
		const el = e.match.elements[attr]; if (!el) return;
		body[attr] = el.type === "checkbox" ? el.checked : el.value;
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
	fetch("monitors", {method: "PUT", headers: {"Content-Type": "application/json"}, body: '{"text": "Achieve a goal!", "type": "goalbar"}'});
});

on("click", ".editbtn", e => {
	const nonce = e.match.closest("tr").dataset.id;
	const mon = editables[nonce];
	const dlg = DOM("#edit" + mon.type); if (!dlg) {console.error("Bad type", mon.type); return;}
	dlg.querySelector("form").reset();
	set_values(nonce, mon, dlg);
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
		total += +thresholds[which]; //What if thresholds[which] isn't numeric??
		opts.push(OPTION({value: prevtotal}, desc));
		if (val === -1 && pos < total) val = prevtotal;
	}
	set_content(DOM("[name=tierpicker]"), opts).value = val;
}
DOM("[name=thresholds]").onchange = DOM("[name=currentval]").onchange = update_tierpicker;
DOM("[name=tierpicker]").onchange = e => DOM("[name=currentval]").value = e.currentTarget.value;
DOM("#setval").onclick = e => {
	const val = +DOM("[name=currentval]").value;
	if (val !== val) return; //TODO: Be nicer
	ws_sync.send({cmd: "setvar", varname: DOM("[name=varname]").value, val});
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
			const opt = this.select.querySelector(`[data-id="${data.id}"]`);
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
const variables = { };
ws_sync.connect(ws_group, {
	ws_type: "chan_variables",
	render_parent: DOM("[name=varname]"),
	render_item: (v, obj) => {console.log("render var", v, obj); return obj || OPTION({"data-id": v.id}, v.id)},
	render: function(data) {console.log("Got variables", data);},
});
