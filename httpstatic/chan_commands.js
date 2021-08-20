import choc, {set_content, DOM} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, BR, BUTTON, INPUT, DIV, DETAILS, LI, LABEL, SPAN, SUMMARY, TABLE, TBODY, TR, TH, TD,
	P, TEXTAREA, SELECT, OPTION, FIELDSET, LEGEND, CODE, UL} = choc;
import {waitlate} from "$$static||utils.js$$";
import {gui_load_message, gui_save_message} from "$$static||command_gui.js$$";
const commands = { };
const hooks = {
	open_advanced: [], //Called with a command mapping when Advanced View is about to be opened
};

/* Stuff not working:

* Creating !join from template utterly fails
* Triggers can't change mode
* Raw view needs to approximate the size of the others - can sizes be synchronized in CSS?
  - Maybe set a max width for classic view, and have it scroll???
* Properties dialog for graphical view

*/

on("click", "button.addline", e => {
	let parent = e.match.closest("td").previousElementSibling;
	parent.appendChild(BR());
	parent.appendChild(INPUT({className: "widetext"}));
});

const flags = {
	mode: {"": "Sequential", random: "Random", "*": "Where multiple responses are available, send them all or pick one at random?"},
	access: {"": "Anyone", mod: "Mods only", vip: "Mods/VIPs", none: "Nobody", "*": "Who should be able to use this command? Disable a command with 'Nobody'."},
	visibility: {"": "Visible", hidden: "Hidden", "*": "Should the command be listed in !help and the non-mod commands view?"},
	delay: {"": "Immediate", "2": "2 seconds", "30": "30 seconds", "60": "1 minute", "120": "2 minutes", "300": "5 minutes",
			"1800": "Half hour", "3600": "One hour", "7200": "Two hours", "*": "When should this be sent?"},
	builtin: {"": "None", "*": "Call on extra information from a built-in function or action"},
	dest: {"": "Chat", "/w": "Whisper", "/web": "Private message", "/set": "Set a variable",
		"*": "Where should the response be sent?"},
	action: {"": "Set the value", "add": "Add to the value", "*": "When setting a variable, should it increment or replace?"}, //TODO: Deprecate
};
for (let name in builtins) {
	flags.builtin[name] = builtins[name][""];
}
const toplevelflags = ["access", "visibility"];
const conditionalkeys = "expr1 expr2 casefold".split(" "); //Include every key used by every conditional type

const tablist = ["Classic", "Graphical", "Raw"], defaulttab = "Classic";

function checkpos() {
	const dlg = DOM("#advanced_view");
	const html = DOM("html");
	dlg.style.left = Math.max(html.clientWidth - dlg.clientWidth, 0) / 2 + "px";
	dlg.style.top = Math.max(html.clientHeight - dlg.clientHeight, 0) / 2 + "px";
	dlg.style.margin = "0";
}

function simple_to_advanced(e) {
	e.preventDefault();
	const elem = e.target.closest(".simpletext");
	const txt = elem.querySelector("input").value;
	elem.replaceWith(render_command(txt));
	checkpos();
}

function simple_to_conditional(e) {
	e.preventDefault();
	const parent = e.currentTarget.closest(".simpletext");
	parent.replaceWith(render_command({
		conditional: "choose",
		message: parent.querySelector("input").value,
		otherwise: "",
	}));
	checkpos();
}

function simple_text(msg) {
	return DIV({className: "simpletext"}, [
		INPUT({value: msg}),
		BUTTON({onclick: simple_to_advanced, title: "Customize flags for this line"}, "\u2699"),
		BUTTON({onclick: simple_to_conditional, title: "Make this conditional"}, "\u2753"),
	]);
}

function adv_add_elem(e) {
	e.target.parentNode.insertBefore(simple_text(""), e.target);
	e.preventDefault();
}

function make_conditional(e) {
	const parent = e.currentTarget.closest(".optedmsg");
	const cmd = get_command_details(parent);
	const msg = { };
	for (let key of ["conditional", "message", "otherwise", ...conditionalkeys]) {
		if (cmd[key] !== undefined) {
			msg[key] = cmd[key];
			delete cmd[key];
		}
	}
	cmd.conditional = "choose";
	cmd.message = msg;
	cmd.otherwise = "";
	parent.replaceWith(render_command(cmd));
	console.log(cmd);
	checkpos();
}

function swap_true_false(e) {
	const parent = e.currentTarget.closest(".optedmsg");
	const cmd = get_command_details(parent);
	const {message, otherwise} = cmd;
	cmd.message = otherwise; cmd.otherwise = message;
	parent.replaceWith(render_command(cmd));
	checkpos();
}

//Build an array of DOM elements that could include simple_texts. Calling render_command
//itself is guaranteed to offer the user flag space.
function text_array(prefix, msg) {
	const ret = (Array.isArray(msg) ? msg : [msg]).map(m =>
		(typeof m === "string") ? simple_text(m) : render_command(m)
	);
	if (!ret.length) ret.push(simple_text("")); //Ensure we always get at least one input even on empty arrays
	if (prefix) ret.unshift(prefix);
	ret.push(BUTTON({onclick: adv_add_elem, title: "Add another line of text here"}, "+"));
	return ret;
}

const conditional_types = {
	string: {
		expr1: "Expression 1",
		expr2: "Expression 2",
		casefold: "?Case insensitive",
		"": "The condition passes if (after variable substitution) the two are equal.",
	},
	contains: {
		expr1: "Needle",
		expr2: "Haystack",
		casefold: "?Case insensitive",
		"": "The condition passes if (after variable substitution) the needle is in the haystack.",
	},
	number: {
		expr1: "Expression to evaluate",
		"": "The condition passes if the expression is nonzero. Use comparisons eg '$var$ > 100'.",
	},
	regexp: {
		expr1: "Regular expression",
		expr2: "Search target (use %s for the message)",
		casefold: "?Case insensitive",
		"": () => [
			"The condition passes if the ",
			//TODO: Find a useful link for PCRE, which is what we actually use
			A({href: "https://pike.lysator.liu.se/generated/manual/modref/ex/predef_3A_3A/Regexp/SimpleRegexp.html"},
				"regular expression"
			),
			" matches.", BR(),
			"NOTE: Variable substitution and case folding are not done in the regexp, only the target.",
		],
	},
	cooldown: {
		cdname: "(optional) Synchronization name",
		cdlength: "Cooldown (seconds)", //TODO: Support hh:mm:ss and show it that way for display
		"": () => ["The condition passes if the time has passed.", BR(),
			"Use ", CODE("{cooldown}"), " for the remaining time, or ",
			CODE("{cooldown_hms}"), " in hh:mm:ss format.", BR(),
			"All commands with the same sync name share the same cooldown.",
		],
	},
	choose: {
		"": "Choose a type of condition.",
	},
};

function describe_builtin_vars(name) {
	const builtin = builtins[name]; if (!builtin) return [];
	const rows = [];
	for (let v in builtin) {
		if (v === "" || v === "*") continue;
		rows.push(TR([TD(CODE(v)), TD(builtin[v])]));
	}
	return rows;
}

//Recursively generate DOM elements to allow a command to be edited with full flexibility
function render_command(cmd, toplevel) {
	if (typeof cmd.message === "undefined") cmd = {message: cmd};
	if (cmd.conditional) {
		//NOTE: This UI currently cannot handle (nor will it create) conditionals
		//with other flags. Instead, do the flags, and then have the conditional
		//as its sole message. In fact, if we DON'T have flags, make sure there's
		//room to add them around the outside (at top level, at least).
		if (toplevel && cmd.otherwise !== undefined) return render_command({message: cmd}, toplevel);
		const cond = conditional_types[cmd.conditional] || {"": "Unrecognized condition type!"};
		const conditions = [SELECT({"data-flag": "conditional"}, [
			OPTION({value: "choose"}, "Unconditional"),
			OPTION({value: "string"}, "String comparison"),
			OPTION({value: "contains"}, "Substring search"),
			OPTION({value: "regexp"}, "Regular expression"),
			OPTION({value: "number"}, "Numeric calculation"),
			OPTION({value: "cooldown"}, "Cooldown/rate limit"),
		])];
		const rows = [];
		let desc = "";
		if (cmd.cdname && cmd.cdname[0] === '.') cmd.cdname = ""; //It's not worth showing the anonymous ones' internal names
		for (let key in cond) {
			if (key === "") desc = cond[key];
			else if (cond[key][0] === '?')
				rows.push(TR([TD(), TD(LABEL([
					INPUT({"data-flag": key, type: "checkbox", checked: cmd[key] === "on"}),
					" " + cond[key].slice(1)
				]))]));
			else rows.push(TR([TD(cond[key]), TD(INPUT({"data-flag": key, value: cmd[key] || "", className: "widetext"}))]));
		}
		for (let key of conditionalkeys) {
			if (cmd[key] && !cond[key]) conditions.push(INPUT({type: "hidden", "data-flag": key, value: cmd[key]}));
		}
		rows.unshift(TR([TD("Type:"), TD(conditions)]));
		rows[0].querySelector("[data-flag=conditional]").value = cmd.conditional;
		if (typeof desc === "function") desc = desc();
		const td = TD(desc); td.setAttribute("colspan", 2);
		rows.push(TR(td));

		return FIELDSET({className: "optedmsg"}, [
			DIV([
				BUTTON({onclick: make_conditional, title: "Add condition around this"}, "\u2753"),
				BUTTON({onclick: swap_true_false, title: "Swap true and false"}, "\u21c5"),
			]),
			TABLE({border: 1, className: "flagstable"}, rows),
			FIELDSET({className: "optedmsg iftrue"}, text_array(LEGEND("If true:"), cmd.message || "")),
			//The "Otherwise" clause is omitted entirely for a trigger's top-level.
			//(If ever this gets tripped by something else, ensure that otherwise:"" is added somewhere.)
			cmd.otherwise !== undefined && FIELDSET({className: "optedmsg iffalse"}, text_array(LEGEND("If false:"), cmd.otherwise)),
		]);
	}
	//Handle flags
	const opts = [TR([TH("Option"), TH("Effect")])];
	//Note that specials could technically alias to commands (but not vice versa),
	//but this UI will never let you do it.
	if (toplevel) opts.push(TR([TD(INPUT({"data-flag": "aliases", value: cmd.aliases || ""})), TD("List other command names that should do the same as this one")]));
	let m = !cmd.target && /^(\/[a-z]+) ([a-zA-Z$%]+)$/.exec(cmd.dest);
	if (m) {cmd.dest = m[1]; cmd.target = m[2];}
	//Replace deprecated "/builtin" with the new way of doing builtins.
	//It's still supported on the back end but is now hidden in the front end.
	if (cmd.dest === "/builtin" && cmd.target) {
		const words = cmd.target.split(" ");
		cmd.dest = cmd.target = "";
		cmd.builtin = words.shift().replace("!", "");
		cmd.builtin_param = words.join(" "); //b/c JS doesn't sanely handle split(" ", 1)
	}
	for (let flg in flags) {
		if (!toplevel && toplevelflags.includes(flg)) continue;
		const opt = [];
		for (let o in flags[flg]) if (o !== "*")
		{
			const el = OPTION({value: o, selected: cmd[flg]+"" === o ? "1" : undefined}, flags[flg][o]);
			//Guarantee that the one marked with an empty string will be the first
			//It usually would be anyway, but make certain.
			if (o === "") opt.unshift(el); else opt.push(el);
		}
		opts.push(TR({"data-flag": flg}, [
			TD(SELECT({"data-flag": flg}, opt)),
			TD(flags[flg]["*"]),
		]));
		//Can these (builtin ==> builtin_param, dest ==> target) be made more generic?
		if (flg === "builtin") opts.push(TR({className: "paramrow"}, [
			TD(INPUT({"data-flag": "builtin_param", value: cmd.builtin_param || ""})),
			TD(["Parameter (extra info) for the built-in", BR(), DETAILS({className: "builtininfo"}, [
				SUMMARY("Information provided"),
				TABLE([TR([TH("Var"), TH("Value")]), TBODY(describe_builtin_vars(cmd.builtin))]),
			])]),
		]));
	}
	opts.push(TR({className: "targetrow"}, [TD(INPUT({"data-flag": "target", value: cmd.target || ""})), TD("Who/what should it send to? User or variable name.")]));
	const voiceids = Object.keys(voices);
	if (voiceids.length > 0 || cmd.voice) {
		const v = voiceids.map(id => OPTION({value: id, selected: cmd.voice+"" === id ? "1" : undefined}, voices[id].desc));
		v.unshift(OPTION({value: "", selected: cmd.voice ? "1" : undefined}, "Default voice"));
		if (cmd.voice && !voices[cmd.voice]) {
			//TODO: Show the name somehow?
			v.push(OPTION({value: "", selected: "1", style: "color: red"}, "Deauthenticated"));
		}
		opts.push(TR({"data-flag": "voice"}, [
			TD(SELECT({"data-flag": "voice"}, v)),
			TD("In what voice should the bot speak?"),
		]));
	}
	return FIELDSET({className: "optedmsg"}, text_array(DETAILS({className: "flagstable"}, [
		SUMMARY("Flags"),
		TABLE({border: 1, "data-dest": cmd.dest || "", "data-builtin": cmd.builtin || ""}, opts),
	]), cmd.message));
}

on("change", 'select[data-flag="dest"]', e => e.match.closest("table").dataset.dest = e.match.value);
on("change", 'select[data-flag="builtin"]', e => {
	const builtin = e.match.closest("table").dataset.builtin = e.match.value;
	set_content(e.match.closest("table").querySelector(".paramrow tbody"), describe_builtin_vars(builtin));
});

let cmd_editing = null, mode = "", cmd_id = "";
function change_tab(tab) {
	console.log("Previous:", mode);
	let response = null;
	switch (mode) {
		case "classic": response = get_command_details(DOM("#command_details").firstChild); break; //TODO: Do we need to retain anything?
		case "graphical": response = gui_save_message(); break;
		case "raw": {
			try {response = JSON.parse(DOM("#raw_text").value);}
			catch (e) {set_content("#raw_error", "JSON format error: " + e.message); return null;}
			set_content("#raw_error", ""); //TODO: Show errors somewhere else (maybe in the header??)
		}
		case "": break;
	}
	if (response) ws_sync.send({cmd: "validate", cmdname: "changetab_" + tab, response});
	else select_tab(tab, cmd_editing);
}
function select_tab(tab, response) {
	mode = tab; cmd_editing = response;
	console.log("Selected:", tab, response);
	DOM("#command_gui").style.display = tab == "graphical" ? "inline" : "none"; //Hack - hide and show the GUI rather than destroying and creating it.
	switch (tab) {
		case "classic": set_content("#command_details", render_command(cmd_editing, cmd_id[0] !== '!')); break;
		case "graphical": set_content("#command_details", ""); gui_load_message(cmd_editing); break;
		case "raw": set_content("#command_details", [
			P("Copy and paste entire commands in JSON format. Make changes as desired!"),
			DIV({className: "error", id: "raw_error"}),
			DIV([BUTTON({className: "raw_view compact", type: "button"}, "Compact"),
				BUTTON({className: "raw_view pretty", type: "button"}, "Pretty-print")]),
			TEXTAREA({id: "raw_text", rows: 10, cols: 80}, JSON.stringify(cmd_editing)),
		]); break;
		default: set_content("#command_details", "Unknown tab " + tab);
	}
}
on("change", "#cmdviewtabset input", e => change_tab(e.match.value));

export function open_advanced_view(cmd) {
	cmd_editing = cmd; mode = ""; cmd_id = cmd.id;
	set_content("#cmdname", "!" + cmd.id.split("#")[0]);
	if (!DOM("#cmdviewtabset")) DOM("#advanced_view header").appendChild(UL({id: "cmdviewtabset"}));
	set_content("#cmdviewtabset", tablist.map(tab => LI(LABEL([
		INPUT({type: "radio", name: "editor", value: tab.toLowerCase(), checked: tab === defaulttab}),
		SPAN(tab),
	]))));
	change_tab(defaulttab.toLowerCase());
	hooks.open_advanced.forEach(f => f(cmd));
	DOM("#advanced_view").style.cssText = "";
	DOM("#advanced_view").showModal();
}
on("click", "button.advview", e => {
	const tr = e.match.closest("tr");
	open_advanced_view(commands[tr.dataset.editid || tr.dataset.id]);
});

on("change", "select[data-flag=conditional]", e => {
	//NOTE: Assumes that this does not have additional flags. They will be lost.
	const parent = e.match.closest(".optedmsg");
	parent.replaceWith(render_command(get_command_details(parent)));
	checkpos();
});

//Recursively reconstruct the command info from the DOM - the inverse of render_command()
function get_command_details(elem) {
	if (elem.classList.contains("simpletext")) {
		//It's a simple input and can only have one value
		elem = elem.querySelector("input");
		if (elem && elem.value && elem.value !== "") return elem.value;
		return undefined; //Will suppress this from the resulting array
	}
	if (!elem.classList.contains("optedmsg")) return undefined;
	//Otherwise it's a full options-and-messages setup.
	const ret = {message: []};
	for (elem = elem.firstElementChild; elem; elem = elem.nextElementSibling) {
		if (elem.classList.contains("flagstable")) {
			elem.querySelectorAll("[data-flag]").forEach(flg => {
				if (flg.type === "checkbox") {
					if (flg.checked) ret[flg.dataset.flag] = "on";
				}
				else if (flg.value !== "") ret[flg.dataset.flag] = flg.value;
			});
		}
		else if (elem.classList.contains("iftrue"))
			ret.message = get_command_details(elem).message;
		else if (elem.classList.contains("iffalse"))
			ret.otherwise = get_command_details(elem).message;
		else {
			const msg = get_command_details(elem);
			if (msg) ret.message.push(msg);
		}
	}
	if (ret.message.length === 1) ret.message = ret.message[0];
	//We could return ret.message if there are no other attributes, but
	//at the moment I can't be bothered. (Also, do it only if not toplevel.)
	//Worst case, we have some junk locally that won't matter; the server
	//will clean it up before next load anyhow.
	return ret;
}

on("click", "#save_advanced", async e => {
	let info = get_command_details(DOM("#command_details").firstChild);
	/*
	const cmd = commands[document.getElementById("cmdname").innerText.slice(1)];
	console.log("WAS:", cmd);
	console.log("NOW:", info);
	return;
	// */
	document.getElementById("advanced_view").close();
	const el = document.getElementById("cmdname").firstChild;
	const cmdname = !el ? "" : el.nodeType === 3 ? el.data : el.value; //Not sure if text nodes' .data attribute is the best way to do this
	ws_sync.send({cmd: "update", cmdname, response: info});
});

on("click", "#delete_advanced", waitlate(750, 5000, "Really delete?", e => {
	const el = document.getElementById("cmdname").firstChild;
	const cmdname = el.nodeType === 3 ? el.data : el.value; //Duplicated from above
	ws_sync.send({cmd: "delete", cmdname});
	DOM("#advanced_view").close();
}));

on("click", ".raw_view", e => {
	let response;
	try {response = JSON.parse(DOM("#raw_text").value);}
	catch (e) {set_content("#raw_error", "JSON format error: " + e.message); return;}
	set_content("#raw_error", "");
	DOM("#raw_text").value = JSON.stringify(response, null, e.match.classList.contains("pretty") ? 4 : 0);
});
export function sockmsg_validated(data) {
	if (data.cmdname.startsWith("changetab_")) select_tab(data.cmdname.replace("changetab_", ""), data.response);
}

on("click", 'a[href="/emotes"]', e => {
	e.preventDefault();
	window.open("/emotes", "emotes", "width=900, height=700");
});

on("click", "#examples", e => {
	e.preventDefault();
	document.getElementById("templates").showModal();
});
on("click", "#templates tbody tr", e => {
	e.preventDefault();
	document.getElementById("templates").close();
	const [cmd, text] = e.match.children;
	const cmdname = cmd.innerText.trim();
	const template = complex_templates[cmdname];
	if (template) {
		open_advanced_view({...template, id: cmdname.slice(1)});
		if (cmdname[0] === '!') set_content("#cmdname", INPUT({value: cmdname}));
		else set_content("#cmdname", "");
		return;
	}
	DOM("#newcmd_name").value = cmdname;
	DOM("#newcmd_resp").value = text.innerText.trim();
});

export const render_parent = DOM("#commandview tbody");
function collect_messages(msg, cb, pfx) {
	if (typeof msg === "string") cb(pfx + msg);
	else if (Array.isArray(msg)) msg.forEach(line => collect_messages(line, cb, pfx));
	else if (typeof msg !== "object") return; //Not sure what this could mean, but we can't handle it. Probably a null entry or something.
	else if (msg.conditional && msg.otherwise) { //Hide the Otherwise if there isn't any (either a normal command with "" or a trigger with undefined)
		collect_messages(msg.message, cb, pfx + "?) ");
		collect_messages(msg.otherwise, cb, pfx + "!) ");
	}
	else collect_messages(msg.message, cb, pfx);
}
export function render_item(msg) {
	//All commands are objects with (at a minimum) an id and a message.
	//A simple command is one which is non-conditional, and whose message  is either
	//a string or an array of strings. Anything else is a non-simple command and will
	//be non-editable in the table - it can only be edited using the Advanced View popup.
	const response = [], cmd = msg.id.split("#")[0];
	let addbtn = "";
	let editid = msg.id;
	if (msg.alias_of) {
		response.push(CODE("Alias of !" + msg.alias_of), BR());
		editid = msg.alias_of + "#" + msg.id.split("#")[1];
	}
	else if (!msg.conditional && (
		typeof msg.message === "string" ||
		(Array.isArray(msg.message) && !msg.message.find(r => typeof r !== "string"))
	)) {
		//Simple message. Return an editable row.
		collect_messages(msg.message, m => response.push(INPUT({value: m, className: "widetext"}), BR()), "");
		addbtn = BUTTON({type: "button", className: "addline", title: "Add another line"}, "+");
	}
	else {
		//Complex message. Return a non-editable row.
		collect_messages(msg, m => response.push(CODE(m), BR()), "");
	}
	response.pop(); //There should be a BR at the end.
	commands[msg.id] = msg;
	return TR({"data-id": msg.id, "data-editid": editid}, [
		TD(CODE("!" + cmd)),
		TD(response),
		TD([
			BUTTON({type: "button", className: "advview", title: "Advanced"}, "\u2699"),
			addbtn,
		]),
	]);
}
export function render(data) {
	if (DOM("#addcmd")) render_parent.appendChild(DOM("#addcmd").closest("TR")); //Move to end w/o disrupting anything
	else render_parent.appendChild(TR([
		TD(["Add: ", INPUT({id: "newcmd_name", size: 10, placeholder: "!hype"})]),
		TD(INPUT({id: "newcmd_resp", className: "widetext"})),
		TD(BUTTON({type: "button", id: "addcmd"}, "Add")),
	]));
}
on("input", "tr[data-id] input", e => e.match.closest("tr").classList.add("dirty"));

on("submit", "main > form", e => {
	e.preventDefault();
	document.querySelectorAll("tr.dirty[data-id]").forEach(tr => {
		const msg = [];
		tr.querySelectorAll("input").forEach(inp => inp.value && msg.push(inp.value));
		if (!msg.length) {
			ws_sync.send({cmd: "delete", cmdname: tr.dataset.id});
			return;
		}
		const response = {message: msg};
		//In order to get here, we had to render a simple command. That means its
		//message is pretty much all there is to it, but there might be some flags.
		const prev = commands[tr.dataset.id];
		for (let flg in flags) if (prev[flg]) response[flg] = prev[flg];
		ws_sync.send({cmd: "update", cmdname: tr.dataset.id, response});
		//Note that the dirty flag is not reset. A successful update will trigger
		//a broadcast message which, when it reaches us, will rerender the command
		//completely, thus effectively resetting dirty.
	});
	addcmd();
});
function addcmd() {
	const newcmd = DOM("#newcmd_name");
	if (newcmd) { //Applicable only to the main command editor
		const cmdname = newcmd.value, response = DOM("#newcmd_resp").value;
		if (cmdname !== "" && response !== "") {
			ws_sync.send({cmd: "update", cmdname, response});
			newcmd.value = DOM("#newcmd_resp").value = "";
			newcmd.closest("tr").classList.remove("dirty");
		}
	}
}
on("click", "#addcmd", addcmd); //Note that there'll never be more than one add button at the moment, but might be zero.

export function add_hook(name, func) {
	if (!hooks[name]) return false;
	return hooks[name].push(func);
}
