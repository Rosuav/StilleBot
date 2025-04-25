import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BR, BUTTON, CODE, DIV, FIELDSET, INPUT, LABEL, LEGEND, OPTGROUP, OPTION, P, SELECT, SPAN, TABLE, TD, TEXTAREA, TH, TR} = choc; //autoimport
import {update_display, formatters} from "$$static||monitor.js$$";
import {simpleconfirm, TEXTFORMATTING} from "$$static||utils.js$$";

const editables = { };
function set_values(nonce, info, elem) {
	if (!info) return 0;
	for (let attr in info) {
		if (attr === "text" && info.type === "goalbar") {
			//Fracture text into the variable name and the actual text.
			const m = /^\$([^:$]+)\$:(.*)/.exec(info.text) || [0, "???", info.text];
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
		fixformatting();
		update_preset();
	}
	return elem;
}

const preset_defaults = {
	format: "plain",
	bit: "", tip: "", follow: "",
	sub_t1: "", sub_t2: "", sub_t3: "",
	kofi_dono: "", kofi_member: "", kofi_renew: "", kofi_shop: "", kofi_commission: "",
	fw_dono: "", fw_member: "", fw_shop: "", fw_gift: "",
};
const presets = {
	Subscribers: {...preset_defaults,
		sub_t1: 1,
		sub_t2: 1,
		sub_t3: 1,
	},
	"Sub points": {...preset_defaults,
		format: "subscriptions",
		sub_t1: 500,
		sub_t2: 1000,
		sub_t3: 3000,
	},
	"Financial support": {...preset_defaults,
		format: "currency",
		bit: 1, tip: 1,
		sub_t1: 500, sub_t2: 1000, sub_t3: 2500,
		kofi_dono: 1, kofi_member: 1, kofi_shop: 1, kofi_commission: 1,
		fw_dono: 1, fw_member: 1, fw_shop: 1, fw_gift: 1,
	},
	Followers: {...preset_defaults,
		follow: 1,
	},
};

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
	return render_parent.appendChild(TR([
		TD({colSpan: 4}, "No monitors defined. Create one!"),
	]));
}
export function render(data) { }

set_content("#edittext form div", TEXTFORMATTING({use_preview: true}));
set_content("#editcountdown form div", [
	TEXTFORMATTING({use_preview: true, texts: [
		{label: "Active"},
		{name: "textcompleted", label: "Completed", desc: " If blank, same as Active"},
		{name: "textinactive", label: "Inactive", desc: " If blank, same as Active"},
	]}),
	TABLE({border: 1}, [
		TR(TH({colspan: 2}, "Automate timer based on...")),
		TR([TH("Scene"), TD([
			LABEL([INPUT({name: "startonscene", type: "checkbox"}),
				" Start the countdown when this scene is selected"]),
			P(["If this countdown is in an OBS scene and it becomes visible, the timer", BR(),
			"will be started or reset. Good for break/BRB scenes."]),
			LABEL(["Initial time ", INPUT({name: "startonscene_time", type: "number"}),
				" Will count down from this time (eg 600 = ten minutes)"]),
			P("For best results, configure OBS to shutdown source when not visible."), //And maybe refresh on visible? Or not needed?
		])]),
		TR([TH("Schedule"), TD([
			LABEL([INPUT({name: "twitchsched", type: "checkbox"}),
				" Tie this countdown to your Twitch schedule"]),
			P(["The countdown will always target the next nearest event on your ",
			A({href: "https://dashboard.twitch.tv/settings/channel/schedule"}, ["Twitch", BR(), "schedule"]),
			". Add an offset (positive or negative) to have it show that many seconds", BR(),
			"at the time of the event (eg 300 to count to five minutes after the event).", BR(),
			"Note that Inactive and Completed here should generally be set to the same text."]),
			LABEL(["Time offset ", INPUT({name: "twitchsched_offset", type: "number"})]),
		])]),
	]),
]);

set_content("#editgoalbar form div", TABLE({border: 1, "data-copystyles": 1}, [
	TR([TH("Active"), TD(LABEL([INPUT({name: "active", type: "checkbox", "data-nocopy": 1}), "Enable auto-advance and level up messages"]))]),
	TR([TH("Variable"), TD([
		SELECT({name: "varname", "data-nocopy": 1}, OPTION("loading...")),
		" Or create a new one: ",
		INPUT({id: "newvarname", size: 20, "data-nocopy": 1}),
		BUTTON({type: "button", id: "createvar"}, "Create"),
	])]),
	TR([TH("Current"), TD([
		"Value:", INPUT({name: "currentval", size: 10, "data-nocopy": 1}),
		"Or tier:", SELECT({name: "tierpicker", "data-nocopy": 1}),
		BUTTON({type: "button", id: "setval"}, "Set"),
		BR(), "NOTE: This will override any automatic advancement! Be careful!",
		BR(), "Changes made here are NOT applied with the Save button.",
	])]),
	TR([TH("Text"), TD([
		INPUT({name: "text", size: 60, "data-nocopy": 1}),
		BR(), "For tiered goals, put a '#' for the current tier - it'll be replaced",
		BR(), "with the actual number.",
	])]),
	TR([TH("Goal(s)"), TD([
		INPUT({name: "thresholds", size: 60, "data-nocopy": 1}),
		BR(), LABEL([INPUT({name: "progressive", type: "checkbox", "data-nocopy": 1}), "Progressive goals (begin each goal after the previous one)"]),
		BR(), LABEL([INPUT({name: "infinitier", type: "checkbox", "data-nocopy": 1}), "Infinite goals (generate more goals after these)"]),
		BR(), "To make a tiered goal bar, set multiple goals eg '", CODE("10 10 10 10 20 30 40 50"), "'",
		BR(), "For currency or subs, use values in cents (eg 1000 for $10 or 2 subs)",
		BR(), SPAN({id: "thresholds-formatted"}),
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
		FIELDSET([LEGEND("Alt"), INPUT({type: "color", name: "altcolor"})]),
		FIELDSET([LEGEND("Bar"), INPUT({type: "color", name: "barcolor"})]),
		FIELDSET([LEGEND("Fill"), INPUT({type: "color", name: "fillcolor"})]),
		FIELDSET([LEGEND("Border"),
			INPUT({name: "borderwidth", type: "number"}), " px ",
			INPUT({name: "bordercolor", type: "color"}),
			INPUT({name: "borderradius", type: "number"}), " curve",
		]),
		FIELDSET([LEGEND("Preview bg"), INPUT({type: "color", name: "previewbg"})]), //As per TEXTFORMATTING, should this be non-copiable?
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
		SELECT({name: "format", "data-nocopy": 1}, [
			OPTION({value: "plain"}, "plain - ordinary numbers"),
			OPTION({value: "currency"}, "currency - cents eg 2718 is $27.18"),
			OPTION({value: "subscriptions"}, "subs or sub points - 500 each (roughly USD cents)"),
			OPTION({value: "hitpoints"}, "Bit Boss hitpoints (complex, use as directed)")]),
		//TODO: Change the label according to the format (eg if Plain, say "scale factor")
		LABEL([SPAN(" Style: "), INPUT({name: "format_style"})]),
		BR(), "Select the desired display format; note that everything is managed in cents still.",
	])]),
	TR([TH("Auto-count"), TD([
		"Automatically advance the goal bar based on Twitch support",
		DIV({className: "optionset"}, [
			FIELDSET([LEGEND("Bits"), INPUT({type: "number", name: "bit", "data-nocopy": 1}), "per bit"]),
			FIELDSET([LEGEND("Tip (each cent)"), INPUT({type: "number", name: "tip", "data-nocopy": 1})]), //TODO: Show somewhere what it takes to make this work
			FIELDSET([LEGEND("Follow"), INPUT({type: "number", name: "follow", "data-nocopy": 1})]),
			//FIELDSET([LEGEND("Raid"), INPUT({type: "number", name: "raid"})]), //Maybe have a tiered system for size of raid???
		]),
		DIV({className: "optionset"}, [
			FIELDSET([LEGEND("T1 sub"), INPUT({type: "number", name: "sub_t1", "data-nocopy": 1})]),
			FIELDSET([LEGEND("T2 sub"), INPUT({type: "number", name: "sub_t2", "data-nocopy": 1})]),
			FIELDSET([LEGEND("T3 sub"), INPUT({type: "number", name: "sub_t3", "data-nocopy": 1})]),
			FIELDSET([LEGEND("Gift & Prime"), LABEL([
				INPUT({type: "checkbox", name: "exclude_gifts", "data-nocopy": 1}),
				" Exclude",
			])]),
		]),
		"Similarly for Ko-fi support (all scaled by number of cents)",
		DIV({className: "optionset"}, [
			FIELDSET([LEGEND("Donation"), INPUT({type: "number", name: "kofi_dono", "data-nocopy": 1})]),
			FIELDSET([LEGEND("Membership"), INPUT({type: "number", name: "kofi_member", "data-nocopy": 1})]),
			FIELDSET([LEGEND("Renewal"), INPUT({type: "number", name: "kofi_renew", "data-nocopy": 1})]),
			FIELDSET([LEGEND("Shop sale"), INPUT({type: "number", name: "kofi_shop", "data-nocopy": 1})]),
			FIELDSET([LEGEND("Commission"), INPUT({type: "number", name: "kofi_commission", "data-nocopy": 1})]),
		]),
		"And for Fourth Wall support (all scaled by number of cents)",
		DIV({className: "optionset"}, [
			FIELDSET([LEGEND("Donation"), INPUT({type: "number", name: "fw_dono", "data-nocopy": 1})]),
			FIELDSET([LEGEND("Membership"), INPUT({type: "number", name: "fw_member", "data-nocopy": 1})]),
			FIELDSET([LEGEND("Shop sale"), INPUT({type: "number", name: "fw_shop", "data-nocopy": 1})]),
			FIELDSET([LEGEND("Gift"), INPUT({type: "number", name: "fw_gift", "data-nocopy": 1})]),
		]),
		"For events not listed, create a command or trigger.",
		DIV(["Select preset: ", SELECT({name: "preset", "data-nocopy": 1}, [
			OPTION("Custom"), //Must be first
			Object.keys(presets).map(p => OPTION(p)),
		])]),
	])]),
	TR([TH("Leaderboard"), TD([
		LABEL([INPUT({type: "checkbox", name: "record_leaderboard", "data-nocopy": 1}), " Track per-user contributions"]),
		//TODO: Have a "Show" button here that gives the same info as in the Variables page
		//TODO: "Reset leaderboard" which will query all users and remove the per-user var for all of them
	])]),
	TR([TH("On level up"), TD([
		SELECT({name: "lvlupcmd", id: "cmdpicker", "data-nocopy": 1}, [OPTION("Loading...")]),
		BR(), "Add and edit commands ", A({href: "commands"}, "on the Commands page"),
	])]),
	TR([TH("Custom CSS"), TD(TEXTAREA({name: "css", "data-nocopy": 1}))]),
	TR([TH("Share styles"), TD([BUTTON({type: "button", class: "copystyles"}, "Copy to clipboard"), BUTTON({type: "button", class: "pastestyles"}, "Paste from clipboard")])]),
]));

on("click", "#createvar", e => {
	const varname = /^[A-Za-z]*/.exec(DOM("#newvarname").value);
	if (!varname || varname[0] === "") return;
	DOM("[name=varname]").appendChild(OPTION(varname[0]));
	DOM("[name=varname]").value = varname[0];
	ws_sync.send({cmd: "createvar", varname: varname[0]});
});

on("submit", "dialog form", async e => {
	const dlg = e.match.closest("dialog");
	const body = {cmd: "updatemonitor", nonce: dlg.dataset.nonce, type: dlg.id.slice(4)};
	for (let el of e.match.elements)
		if (el.name) body[el.name] = el.type === "checkbox" ? el.checked : el.value;
	ws_sync.send(body);
});

on("click", ".add_monitor", e => ws_sync.send({cmd: "addmonitor", type: e.match.dataset.type}));

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

on("click", ".deletebtn", simpleconfirm("Delete this monitor?", e =>
	ws_sync.send({cmd: "deletemonitor", nonce: e.match.dataset.nonce})));

on("dragstart", ".monitorlink", e => {
	const url = `${e.match.href}&layer-name=Mustard%20Mine%20monitor&layer-width=${e.match.dataset.width||400}&layer-height=${e.match.dataset.height||120}`;
	e.dataTransfer.setData("text/uri-list", url);
});

function update_tierpicker() { //TODO: If infinite tiers, add one more past the current tier
	const thresholds = DOM("[name=thresholds]").value.split(" ");
	const pos = +DOM("[name=currentval]").value;
	const opts = [];
	let val = -1, total = 0;
	const progressive = DOM("[name=progressive]").checked;
	const infinitier = DOM("[name=infinitier]").checked;
	if (!infinitier) thresholds.push(Infinity); //Place a known elephant in Cairo
	for (let which = 0; which < thresholds.length; ++which) {
		//Record the *previous* total as the mark for this tier. If you pick
		//tier 3, the total should be set to the *start* of tier 3.
		const desc = which === thresholds.length - 1 && !infinitier ? "And beyond!" : "Tier " + (which + 1);
		const prevtotal = total;
		if (progressive) total = +thresholds[which];
		else total += +thresholds[which]; //What if thresholds[which] isn't numeric??
		//If you have a progressive bar with two equal tier values, or a non-progressive
		//bar with a zero, that tier will be skipped. Show it as an inaccessible tier.
		if (total === prevtotal) opts.push(OPTION({value: "(" + prevtotal + ")", disabled: true}, "(" + desc + ")"));
		else opts.push(OPTION({value: prevtotal}, desc));
		if (which === thresholds.length - 1 && infinitier && val === -1) {
			//Hack: If we have infinite tiers, append more as we need them.
			//Do this until we find the currently-selected tier, and then one more
			//after that (so you can always advance to the next tier).
			if (progressive) {
				const delta = +thresholds[which] - +(thresholds[which - 1]||0);
				if (delta > 0) thresholds.push(+thresholds[which] + delta);
			}
			else if (thresholds[which] > 0) thresholds.push(thresholds[which]);
		}
		if (val === -1 && pos < total) val = prevtotal;
	}
	set_content(DOM("[name=tierpicker]"), opts).value = val;
}
DOM("[name=thresholds]").onchange = DOM("[name=currentval]").onchange = DOM("[name=progressive]").onclick = update_tierpicker;
DOM("[name=tierpicker]").onchange = e => DOM("[name=currentval]").value = e.currentTarget.value;
DOM("#setval").onclick = e => {
	const val = +DOM("[name=currentval]").value;
	if (val !== val) return; //TODO: Be nicer
	ws_sync.send({cmd: "setvar", varname: DOM("[name=varname]").value, val});
	if (DOM("[name=infinitier]").checked) update_tierpicker(); //If you select a different tier, adjust the number of tiers shown in the dropdown.
}

function fixformatting() {
	const fmt = DOM("[name=format]").value;
	const formatter = formatters[fmt] || formatters.plain;
	const sty = DOM("[name=format_style]").value;
	const thresholds = DOM("[name=thresholds]").value
		.split(" ")
		.map(th => formatter(+th, sty))
		.join(" ")
		+ (DOM("[name=infinitier]").checked ? " ..." : "");
	const label = fmt === "subscriptions" ? " subs" : ""; //TODO: Generalize this
	set_content("#thresholds-formatted", "Shown as: " + thresholds + label);
}
on("input", "[name=thresholds]", fixformatting);
on("change", "[name=format],[name=thresholds],[name=infinitier]", fixformatting);

on("change", "[name=preset]", e => {
	const preset = presets[e.match.value];
	if (!preset) return; //If you click Custom, don't clear everything
	Object.entries(preset).forEach(([k, v]) => DOM("[name=" + k + "]").value = v);
});

function update_preset() {
	//See if one of the presets is valid. This is inefficient but I don't really care.
	for (let name in presets) {
		const preset = presets[name];
		let match = true;
		for (let k in preset)
			if (DOM("[name=" + k + "]").value !== ""+preset[k]) {match = false; break;}
		if (match) {DOM("[name=preset]").value = name; return;}
	}
	DOM("[name=preset]").selectedIndex = 0;
}
on("change", "input", e => e.match.name in preset_defaults && update_preset());

function textify(cmd) {
	if (typeof cmd === "string") return cmd;
	if (Array.isArray(cmd)) return cmd.map(textify).filter(x => x).join(" // ");
	if (cmd.dest) return null; //Suppress special-destination sections
	return textify(cmd.message);
}
function shorten(txt, len) {
	if (!txt || txt.length <= len) return txt;
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
	render_item: (v, obj) => obj || OPTION({"data-id": v.id}, v.id),
	render: function(data) { },
});
