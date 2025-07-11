import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, B, BR, BUTTON, CODE, DIV, FIELDSET, FIGCAPTION, FIGURE, IFRAME, IMG, INPUT, LABEL, LEGEND, OPTGROUP, OPTION, P, SELECT, SPAN, TABLE, TD, TEXTAREA, TH, TR} = choc; //autoimport
import {update_display, formatters} from "$$static||monitor.js$$";
import {simpleconfirm, TEXTFORMATTING, upload_to_library} from "$$static||utils.js$$";
import {commands, register_command, cmd_configure, open_advanced_view} from "$$static||command_editor.js$$";

//TODO: Make cmd_configure know about some standard types of configuration
//Even better, have the command basis figured out from something inherent in the command
cmd_configure({
	get_command_basis: cmd => {
		const cmdname = "!" + cmd.id.split("#")[0];
		set_content("#advanced_view h3", ["Command name ", INPUT({autocomplete: "off", id: "cmdname", value: cmdname})]);
		return {type: "anchor_command"};
	},
});

//Search a command recursively for a monitor action
function search_command(node, id, action) {
	if (!node || typeof node === "string") return false;
	if (Array.isArray(node)) return node.some(n => search_command(n, id, action));
	if (node.dest === "/set" && node.destcfg === "add" && node.target === id && action === "+=")
		return true;
	if (node.builtin === "chan_monitors" && Array.isArray(node.builtin_param)
		&& node.builtin_param[0] === id && node.builtin_param[1] === action)
			return true;
	//Note that we will scan naively here, even if the 'otherwise' node cannot be executed
	//eg if this isn't even conditional. A properly-validated command should not have such
	//quirks in it.
	return search_command(node.message, id, action) || search_command(node.otherwise, id, action);
}

function update_activations(elem, id, action) {
	elem = set_content(elem, Object.values(commands)
		.filter(cmd => search_command(cmd, id, action))
		.map(cmd => BUTTON({type: "button", class: "advview", "data-id": cmd.id}, "!" + cmd.id))
	);
	elem.dataset.activationid = id;
	elem.dataset.activationaction = action;
}
function update_activation_lists() {
	document.querySelectorAll("[data-activationid]").forEach(elem =>
		update_activations(elem, elem.dataset.activationid, elem.dataset.activationaction))
}

const editables = { }, vargroups = { }, variables = { };
function set_values(info, elem) {
	if (!info) return 0;
	for (let attr in info) {
		if (attr === "text" && elem.querySelector("[name=varname]")) {
			//Fracture text into the variable name and the actual text.
			const m = /^\$([^:$]+)\$:(.*)/.exec(info.text) || [0, "???", info.text];
			const v = elem.querySelector("[name=varname]"); if (v) v.value = m[1];
			const t = elem.querySelector("[name=text]");    if (t) t.value = m[2];
			continue;
		}
		elem.querySelectorAll("[data-content=" + attr + "]").forEach(el => set_content(el, info[attr]));
		const el = elem.querySelector("[name=" + attr + "]");
		if (!el) continue;
		if (el.type === "checkbox") el.checked = info[attr];
		else el.value = info[attr];
		if (attr === "lvlupcmd") //Special case: the value might not work if stuff isn't loaded yet.
			el.dataset.wantvalue = info[attr];
	}
	//Anything that wasn't updated, set it to its default value
	elem.querySelectorAll("[defaultvalue][name]").forEach(el => !(el.name in info) && (el.value = el.getAttribute("defaultvalue")));
	if (info.type === "goalbar") {
		const el = elem.querySelector("[name=currentval]"); if (el) el.value = info.display.split(":")[0];
		update_tierpicker();
		fixformatting();
		update_preset();
	}
	if (info.type === "pile") {
		//Instead of updating individual elements, build a set of preview tiles
		const qty = vargroups[info.varname + ":"] || { };
		set_content("#pilethings", info.things.map(thing => DIV({class: "pilething", "data-thingid": thing.id}, [
			B("ID: " + thing.id),
			DIV({class: "thingpreview", style: "background-image: url(" + (thing.images[0]?.url || "/static/MustardMineAvatar.png") + ")"}),
			DIV([
				"Qty: ",
				INPUT({class: "thingqty", type: "number", step: 1, value: qty[thing.id] || 0}),
			]),
			DIV({class: "buttonbox", style: "justify-content: space-around"}, [
				BUTTON({type: "button", class: "editpilecat"}, "\u2699"),
				BUTTON({type: "button", class: "deletething", title: "Delete", style: "padding: 0 0.5em; width: auto"}, "🗑"),
			]),
		])));
		update_activations("#claw_activations", info.id, "claw");
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

const files = { };
export const autorender = {
	image_parent: DOM("#uploads"),
	image(file, obj) { //extcall
		files[file.id] = file;
		return DIV({"data-type": file.mimetype}, [
			FIGURE([
				file.url ? DIV({className: "thumbnail", style: "background-image: url(" + file.url + ")"})
					: DIV({className: "thumbnail"}, "uploading..."),
				FIGCAPTION([
					A({href: file.url, target: "_blank"}, file.name),
					" ",
					BUTTON({type: "button", class: "renamefile", title: "Rename"}, "📝"),
				]),
				BUTTON({type: "button", class: "confirmdelete", title: "Delete"}, "🗑"),
			]),
			DIV({style: "flex-grow: 1"}),
			DIV({style: "display: flex; justify-content: space-around"}, BUTTON({type: "button", class: "chooseimage"}, "Choose")),
		]);
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
	//HACK: For pile o' pics, the preview is actually just iframed in. Lower performance but easier.
	//Note that this incurs the cost of a separate websocket with (partly) duplicate signals. Review
	//this decision once things are fully implemented and consider doing it like the others (but
	//maybe with a different update call).
	if (editables[nonce].type === "pile")
		//TODO: Get the width and height once they're configurable
		set_content(el.querySelector(".preview"), IFRAME({src: "monitors?view=" + nonce, "width": 600, "height": 400}));
	else update_display(el.querySelector(".preview"), editables[nonce]);
	el.querySelector(".preview-bg").style.backgroundColor = editables[nonce].previewbg;
	const dlg = DOM("#edit" + msg.type);
	if (dlg && dlg.dataset.nonce === nonce) {
		//dlg.querySelector("form").reset(); //Do we need this? Would add flicker.
		//When it's a pile of stuff, we also need to update the quantities, so query those first.
		if (editables[nonce].type === "pile") ws_sync.send({cmd: "getgroupvars", id: editables[nonce].varname}, "chan_variables");
		else set_values(msg, dlg);
	}
	const catdlg = DOM("#editthingcat");
	if (catdlg && catdlg.dataset.nonce === nonce) {
		const thing = editables[nonce].things.find(t => t.id === catdlg.dataset.originalid);
		if (thing) {
			const form = DOM("#editthingcat form");
			for (let attr in thing) {
				const elem = form.elements[attr]; if (!elem) continue;
				elem.value = thing[attr];
			}
			update_thing_images(thing);
		}
	}
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

function AUTO_RESET(attrs) {return SELECT({name: "autoreset", ...attrs}, [
	OPTION({value: ""}, "None"),
	OPTION({value: "stream"}, "End of stream"),
	OPTION({value: "month"}, "Calendar month"),
])}

set_content("#edittext form div", TEXTFORMATTING({use_preview: true}));
set_content("#editcountdown form div", [
	TEXTFORMATTING({
		before: TR([TH("Variable"), TD([
			//TODO: Allow multiple select boxes with name=varname and populate them all
			//Then this can reuse the autorender code that powers goal bar varnames.
			INPUT({name: "varname", size: 20, "data-nocopy": 1}),
			BUTTON({type: "button", id: "setcountdown"}, "Change..."),
		])]),
		use_preview: true,
		texts: [
			{label: "Active"},
			{name: "textcompleted", label: "Completed", desc: " If blank, same as Active"},
			{name: "textinactive", label: "Inactive", desc: " If blank, same as Active"},
		],
		after: [
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
		],
	}),
]);

set_content("#editgoalbar form div", TABLE({border: 1, "data-copystyles": 1}, [
	TR([TH("Active"), TD([
		LABEL([INPUT({name: "active", type: "checkbox", "data-nocopy": 1}), "Enable auto-advance and level up messages"]),
		BR(), LABEL(["Automatically reset? ", AUTO_RESET()]),
	])]),
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
	TR([TH("Custom CSS"), TD(TEXTAREA({name: "css"}))]),
	TR([TH("Share styles"), TD([BUTTON({type: "button", class: "copystyles"}, "Copy to clipboard"), BUTTON({type: "button", class: "pastestyles"}, "Paste from clipboard")])]),
]));

function ACTIVATIONS(action) {
	return [
		DIV({id: action + "_activations", class: "buttonbox"}),
		DIV({class: "buttonbox", "data-action": action}, [
			"Create: ",
			BUTTON({type: "button", class: "addactivation", "data-invocation": "command"}, "Command"),
			//FIXME: Disable this button if we don't have perms for reward creation
			BUTTON({type: "button", class: "addactivation", "data-invocation": "reward"}, "Points reward"),
			BUTTON({type: "button", class: "addactivation", "data-invocation": "timer"}, "Timer"),
		]),
	];
}
set_content("#editpile form div", [
	P({style: "max-width: 600px"}, [
		"A flexible system that can be used in a variety of ways, the Pile of Pics lets you drop " +
		"items into it, and potentially claw them out again. The objects bounce off each other, " +
		"and can be contained in a box or partial box. Objects can be provided images, or you " +
		"can use Twitch emotes; note that BTTV, 7TV, FFZ, etc emotes will not work.",
	]),
	TABLE({border: 1}, [
		TR([TH("Variable group"), TD(CODE({"data-content": "varname"}))]),
		TR([TH(LABEL({for: "editpile_autoreset"}, "Auto-reset")), TD(AUTO_RESET({id: "editpile_autoreset"}))]),
		TR([TH("Fade after"), TD([INPUT({name: "fadeouttime", type: "number"}), " minutes (0 to disable)"])]),
		TR([TH("Background"), TD([
			LABEL(["Color: ", INPUT({name: "bgcolor", type: "color"})]),
			LABEL([
				" Opacity: ",
				INPUT({name: "bgalpha", type: "number", min: 0, max: 100, value: 0}),
				"% (0 for invisible)",
			]),
		])]),
		TR([TH("Walls"), TD([
			LABEL(["Color: ", INPUT({name: "wallcolor", type: "color"})]),
			LABEL([
				" Opacity: ",
				INPUT({name: "wallalpha", type: "number", min: 0, max: 100, value: 0}),
				"% (0 for invisible)",
			]),
		])]),
		TR([TH("Claw"), TD([
			LABEL(["Size: ", INPUT({name: "clawsize", type: "number"}), " (0 to disable)"]), " ",
			LABEL(["Thickness: ", INPUT({name: "clawthickness", type: "number", defaultvalue: 1, min: 1, max: 10})]), BR(),
			LABEL(["Color: ", INPUT({name: "clawcolor", type: "color", defaultvalue: "#71797E"})]), BR(),
			"NOTE: The claw is not active on this edit page; open the", BR(), "direct link to test it.", BR(),
			FIELDSET([
				LEGEND("Activations:"),
				ACTIVATIONS("claw"),
			]),
		])]),
	]),
	DIV({style: "margin: 12px 0"}, TABLE({border: "1"}, [
		TR([TH("Wall"), TH("Size (%)")]),
		TR([TD(LABEL({for: "wall_left"}, "Left")), TD(INPUT({type: "number", id: "wall_left", name: "wall_left"}))]),
		TR([TD(LABEL({for: "wall_right"}, "Right")), TD(INPUT({type: "number", id: "wall_right", name: "wall_right"}))]),
		TR([TD(LABEL({for: "wall_floor"}, "Floor")), TD(INPUT({type: "number", id: "wall_floor", name: "wall_floor"}))]),
	])),
	"Thing categories:",
	DIV({id: "pilethings"}), //Will contain a tile for every category of thing that can be dropped onto the pile
]);

set_content("#editthingcat form div", TABLE({border: 1}, [
	TR([TH("ID"), TD(INPUT({name: "id"}))]),
	TR([TH("Size"), TD([
		//Note that the height is calculated in order to preserve aspect ratio of the image.
		INPUT({name: "xsize", type: "number", step: 1}),
		" Shape ",
		SELECT({name: "shape"}, [
			OPTION({value: ""}, "Rectangle"),
			OPTION({value: "circle"}, "Circle"),
		]),
	])]),
	TR([TH("Activations"), TD(ACTIVATIONS("thing"))]),
	TR([TH("Images"), TD({id: "thingcatimages"})]),
]));

on("click", "#createvar", e => {
	const varname = /^[A-Za-z]*/.exec(DOM("#newvarname").value);
	if (!varname || varname[0] === "") return;
	DOM("select[name=varname]").appendChild(OPTION(varname[0]));
	DOM("select[name=varname]").value = varname[0];
	ws_sync.send({cmd: "createvar", varname: varname[0]});
});

on("click", ".addactivation", e => ws_sync.send({
	cmd: "addactivation", nonce: e.match.closest_data("nonce"),
	invocation: e.match.closest_data("invocation"), action: e.match.closest_data("action"),
	thingid: e.match.closest_data("originalid"),
}));

on("submit", "dialog form", async e => {
	if (e.submitter.value === "cancel") return; //The "Cancel" button is actually a submit-type button to make it manage the dialog, but don't actually save anything
	const dlg = e.match.closest("dialog");
	const body = {cmd: "updatemonitor", nonce: dlg.dataset.nonce, type: dlg.id.slice(4)};
	if (dlg.id === "editthingcat") {
		//HACK: Different message for editing the subelements
		body.cmd = "managethings";
		body.update = dlg.dataset.originalid;
	}
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
	dlg.dataset.nonce = nonce;
	dlg.returnValue = "close";
	if (mon.type === "pile") {
		ws_sync.send({cmd: "getgroupvars", id: mon.varname}, "chan_variables");
		dlg.dataset.pending = "1";
	}
	else {
		set_values(mon, dlg);
		dlg.showModal();
	}
});

on("click", ".deletebtn", simpleconfirm("Delete this monitor?", e =>
	ws_sync.send({cmd: "deletemonitor", nonce: e.match.dataset.nonce})));

on("click", ".confirmdelete", simpleconfirm("Delete this file?", e =>
	ws_sync.send({cmd: "deletefile", id: e.match.closest_data("id")})));

on("click", ".deletething", simpleconfirm("Delete this thing category?", e =>
	ws_sync.send({cmd: "managethings", nonce: e.match.closest_data("nonce"), remove: e.match.closest_data("thingid")})));

on("click", ".renamefile", e => {
	const elem = DOM("#renameform").elements;
	const file = files[e.match.closest("[data-id]").dataset.id];
	if (!file) return;
	elem.id.value = file.id;
	elem.name.value = file.name;
	DOM("#renamefiledlg").showModal();
});

on("submit", "#renameform", e => {
	e.preventDefault();
	const msg = {cmd: "renamefile"};
	for (let el of e.match.elements)
		if (el.name) msg[el.name] = el.type === "checkbox" ? el.checked : el.value;
	ws_sync.send(msg);
	DOM("#renamefiledlg").close();
});

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
	ws_sync.send({cmd: "setvar", varname: DOM("select[name=varname]").value, val});
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

function update_thing_images(thing) {
	set_content("#thingcatimages", [
		"If multiple images are available, one will be chosen at random for each thing.",
		DIV({id: "imagetiles"}, thing.images.map((img, idx) => DIV([
			IMG({src: img.url, style: "width: " + thing.xsize + "px"}),
			BUTTON({class: "deleteimg", type: "button", "data-idx": idx}, "🗑"),
		]))),
		DIV([
			BUTTON({type: "button", id: "thingcatimg"}, "Choose new"),
		]),
	]);
}

on("click", "#addpilecat", e => ws_sync.send({cmd: "managethings", "nonce": e.match.closest("dialog").dataset.nonce, "add": 1}));
on("click", ".editpilecat", e => {
	const nonce = e.match.closest_data("nonce"), thingid = e.match.closest_data("thingid");
	const dlg = DOM("#editthingcat");
	const form = DOM("#editthingcat form");
	const mon = editables[nonce];
	const thing = mon.things.find(t => t.id === thingid);
	if (!thing) return;
	for (let attr in thing) {
		const elem = form.elements[attr]; if (!elem) continue;
		//TODO: if elem.type === "checkbox"
		elem.value = thing[attr];
	}
	update_thing_images(thing);
	update_activations("#thing_activations", mon.varname + ":" + thingid, "+=");
	dlg.dataset.nonce = nonce;
	dlg.dataset.originalid = thingid;
	dlg.showModal();
});

upload_to_library({});
let library_selection = { };
on("click", "#thingcatimg", e => {
	library_selection = {nonce: e.match.closest_data("nonce"), update: e.match.closest_data("originalid")};
	DOM("#library").showModal();
});

on("click", ".chooseimage", e => {
	ws_sync.send({cmd: "managethings", addimage: e.match.closest_data("id"), ...library_selection});
	DOM("#library").close();
});

on("click", ".deleteimg", e => ws_sync.send({cmd: "managethings",
		nonce: e.match.closest_data("nonce"), update: e.match.closest_data("originalid"),
		delimage: e.match.dataset.idx,
}));

on("change", ".thingqty", e => {
	const nonce = e.match.closest_data("nonce"), thingid = e.match.closest_data("thingid");
	const mon = editables[nonce];
	ws_sync.send({cmd: "setvar", varname: mon.varname + ":" + thingid, val: e.match.value});
});

function twodig(n) {return ("0" + n).slice(-2);}

on("click", "#setcountdown", e => {
	const varname = e.match.closest("dialog").querySelector("[name=varname]").value; //In case the user's edited it
	const time = +variables[varname]; //Zero if not set - will imply "00:00 and paused"
	const dlg = DOM("#setcountdowndlg");
	if (time > 1e9) { //Match the behaviour of monitor.js
		const date = new Date(time * 1000);
		//NOTE: The datetime-local input type supports minutes, but not seconds. This means that
		//timers will lose resolution when they do not end at exactly the end of a minute.
		//If your intention really is to target a specific time, this is probably fine, but if it
		//was (say) a 5 minute timer for a break, that would be a problem. When the dialog opens,
		//it will be truncated to the start of that minute; this can mean that, when there's less
		//than a minute to go, the timer could still be ticking down but the display shows a target
		//time in the past. Thus opening the dialog and immediately clicking "Set" will truncate
		//the target time to the start of that minute.
		const datestring = (
			date.getFullYear() + "-" + twodig(date.getMonth() + 1) + "-" + twodig(date.getDate())
			+ "T" + twodig(date.getHours()) + ":" + twodig(date.getMinutes())
		);
		//FIXME: What about timezones? Currently we try to show in the user's timezone,
		//but a lot of other aspects of the bot will use the channel's instead.
		dlg.querySelector("[name=target]").value = datestring;
		dlg.querySelector("[name=delay]").value = "";
	} else {
		dlg.querySelector("[name=target]").value = "";
		dlg.querySelector("[name=delay]").value = time < 60 ? ""+time
			: time < 3600 ? Math.floor(time / 60) + ":" + twodig(time % 60)
			: Math.floor(time / 3600) + ":" + twodig(Math.floor(time / 60) % 60) + ":" + twodig(time % 60);
	}
	dlg.dataset.varname = varname;
	dlg.showModal();
});
on("click", "#settarget", e => {
	const target = e.match.closest("dialog").querySelector("[name=target]").value;
	ws_sync.send({cmd: "setvar", varname: e.match.closest("dialog").dataset.varname, val: +new Date(target) / 1000});
	e.match.closest("dialog").close();
});
on("click", "#setdelay,#setdelayafter", e => {
	let val = 0;
	e.match.closest("dialog").querySelector("[name=delay]").value.split(":").forEach(part => val = val * 60 + (+part));
	//To start a five minute counter at the current time, we need to add the current time.
	//Note that the definition of "current time" is given by your computer's clock, and may
	//not correspond to the server's. But they should normally be close.
	if (e.match.id === "setdelayafter") val += Math.floor(+new Date() / 1000);
	ws_sync.send({cmd: "setvar", varname: e.match.closest("dialog").dataset.varname, val});
	e.match.closest("dialog").close();
});

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
ws_sync.connect(ws_group, {
	ws_type: "chan_commands", ws_sendid: "cmdedit",
	select: DOM("#cmdpicker"),
	make_option: cmd => OPTION({"data-id": cmd.id, value: cmd.id.split("#")[0]}, "!" + cmd.id.split("#")[0] + " -- " + shorten(textify(cmd.message), 75)),
	is_recommended: cmd => cmd.access === "none" && cmd.visibility === "hidden",
	render: function(data) {
		if (data.id) {
			//FIXME: Partial updates to the SELECT() are broken. Replace it with an activation list for
			//better functionality anyway, and get rid of the drop-down altogether.
			commands[data.id] = data.data;
			update_activation_lists();
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
		update_activation_lists();
	},
});
ws_sync.connect(ws_group, {
	ws_type: "chan_variables", ws_sendid: "chan_variables",
	render_parent: DOM("select[name=varname]"),
	render_item: (v, obj) => {variables[v.id] = v.curval; return obj || OPTION({"data-id": v.id}, v.id)},
	render: function(data) { },
	sockmsg_groupvars: function(msg) {
		vargroups[msg.prefix] = Object.fromEntries(msg.vars.map(v => [v.suffix, v.value]));
		const dlg = DOM("#editpile");
		const nonce = dlg.dataset.nonce;
		const mon = editables[nonce];
		if (mon.varname + ":" === msg.prefix) set_values(mon, dlg);
		if (dlg.dataset.pending === "1") {
			delete dlg.dataset.pending;
			dlg.showModal();
		}
	},
});
