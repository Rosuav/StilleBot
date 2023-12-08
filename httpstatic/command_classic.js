//Command editor: Classic mode
import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BR, BUTTON, CODE, DETAILS, SUMMARY, DIV, FIELDSET, INPUT, LABEL, LEGEND, SELECT, OPTION, TABLE, TBODY, TR, TH, TD, UL, LI} = choc;

const flags = {
	mode: {"": "Sequential", random: "Random", rotate: "Rotate", foreach: "Per chatter", "*": "Where multiple responses are available, send them all or pick one?"},
	access: {"": "Anyone", mod: "Mods only", vip: "Mods/VIPs", none: "Nobody", "*": "Who should be able to use this command? Disable a command with 'Nobody'."},
	visibility: {"": "Visible", hidden: "Hidden", "*": "Should the command be listed in !help and the non-mod commands view?"},
	delay: {"": "Immediate", "2": "2 seconds", "30": "30 seconds", "60": "1 minute", "120": "2 minutes", "300": "5 minutes",
			"1800": "Half hour", "3600": "One hour", "7200": "Two hours", "*": "When should this be sent?"},
	builtin: {"": "None", "*": "Call on extra information from a built-in function or action"},
	dest: {"": "Chat", "/w": "Whisper", "/web": "Private message", "/set": "Set a variable",
		"/chain": "Chain to another command", "/reply": "Reply or join a thread, eg to {msgid}",
		"//": "Comment (won't be sent anywhere)", "*": "Where should the response be sent?"},
};
for (let name in builtins) flags.builtin[name] = builtins[name].name;
const toplevelflags = ["access", "visibility"];
const conditionalkeys = "expr1 expr2 casefold".split(" "); //Include every key used by every conditional type
//NOTE: Must correspond to the list of params in command_gui types.anchor_command.params
const anchor_props = ["aliases", "access", "visibility", "automate", "redemption"];

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
		INPUT({value: msg.replace("##CHANNEL##", ws_group.slice(1))}),
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
	spend: {
		expr1: "Variable to spend some of",
		expr2: "Amount to spend",
		"": "The condition passes if the variable has at least that much in it. It will be reduced by that amount.",
	},
	regexp: {
		expr1: "Regular expression",
		expr2: "Search target (use %s for the message)",
		casefold: "?Case insensitive",
		"": () => [
			"The condition passes if the ",
			A({href: "/regexp", target: "_blank"}, "regular expression"),
			" matches.", BR(),
			"NOTE: Variable substitution and case folding are not done in the regexp, only the target.",
		],
	},
	cooldown: {
		cdname: "(optional) Synchronization name",
		cdlength: "Cooldown (seconds)", //TODO: Support hh:mm:ss and show it that way for display
		cdqueue: "?Queue",
		"": () => ["The condition passes if the time has passed.", BR(),
			"Use ", CODE("{cooldown}"), " for the remaining time, or ",
			CODE("{cooldown_hms}"), " in hh:mm:ss format.", BR(),
			"All commands with the same sync name share the same cooldown.",
		],
	},
	"catch": {
		"": () => ["If an error happens in the first block, move into the second."],
	},
	choose: {
		"": "Choose a type of condition.",
	},
};

function describe_builtin_vars(name) {
	const builtin = builtins[name]; if (!builtin) return [];
	const rows = [];
	for (let v in builtin)
		if (v[0] === '{') rows.push(TR([TD(CODE(v)), TD(builtin[v])]));
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
			OPTION({value: "spend"}, "Spend channel points"),
			OPTION({value: "cooldown"}, "Cooldown/rate limit"),
			OPTION({value: "catch"}, "Catch errors"),
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
		rows.push(TR(TD({colSpan: 2}, desc)));

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
	if (toplevel) opts.push(TR([TD(BUTTON({class: "anchorprops", type: "button"}, "Advanced")), TD("Advanced command options")]));
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
		let custom = true;
		for (let o in flags[flg]) if (o !== "*")
		{
			const el = OPTION({value: o, ".selected": cmd[flg]+"" === o ? "1" : undefined}, flags[flg][o]);
			//Guarantee that the one marked with an empty string will be the first
			//It usually would be anyway, but make certain.
			if (o === "") opt.unshift(el); else opt.push(el);
			if (cmd[flg]+"" === o) custom = false;
		}
		//The current value for the flag doesn't match any of our standard options.
		//Add a custom option to allow the value to be retained (but if you save
		//with a default, you won't be able to reset to this one).
		if (cmd[flg] && custom) opt.push(OPTION({value: cmd[flg]+"", ".selected": "1"}, "Custom: " + cmd[flg]));
		opts.push(TR({"data-flag": flg}, [
			TD(SELECT({"data-flag": flg}, opt)),
			TD(flags[flg]["*"]),
		]));
		//Can these (builtin ==> builtin_param, dest ==> target) be made more generic?
		if (flg === "builtin") opts.push(TR({className: "paramrow"}, [
			//Note that multi-param is not supported here, and it'll always and only return a single string.
			TD([
				//NOTE: This cheats horrifically by attaching a value attribute to an element
				//that normally doesn't have one. It should work fine, though.
				CODE({"data-flag": "builtin_param", ".value": cmd.builtin_param}, JSON.stringify(cmd.builtin_param)),
				BR(),
				BUTTON({class: "bltedit", type: "button"}, "Edit"),
			]),
			TD(["Parameter (extra info) for the built-in", BR(), DETAILS({className: "builtininfo"}, [
				SUMMARY("Information provided"),
				TABLE([TR([TH("Var"), TH("Value")]), TBODY(describe_builtin_vars(cmd.builtin))]),
			])]),
		]));
	}
	opts.push(TR({className: "destcfgrow"}, [TD(INPUT({"data-flag": "destcfg", value: cmd.action || cmd.destcfg || ""})), TD("Extra config. Use 'add' to add to a variable. See docs?")]));
	opts.push(TR({className: "targetrow"}, [TD(INPUT({"data-flag": "target", value: cmd.target || ""})), TD("Who/what should it send to? User or variable name.")]));
	const voiceids = Object.keys(voices);
	if (voiceids.length > 0 || cmd.voice) {
		const v = voiceids.map(id => OPTION({value: id, ".selected": cmd.voice+"" === id ? "1" : undefined}, voices[id].desc));
		v.unshift(OPTION({value: "", ".selected": cmd.voice ? "1" : undefined}, "Default voice"));
		if (cmd.voice && !voices[cmd.voice]) {
			v.push(OPTION({value: "", ".selected": "1", style: "color: red"}, "Deauthenticated"));
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

on("click", ".bltedit", e => {
	const tb = e.match.closest("table"), builtin = tb.dataset.builtin;
	const code = tb.querySelector("[data-flag=builtin_param]")
	//Encapsulation breach: Call on a function from the GUI editor to open a
	//properties dialog for the builtin params.
	window.open_element_properties({type: "builtin_" + builtin, builtin_param: code.value,
		_onsave: function() {set_content(code, JSON.stringify(code.value = this.builtin_param));}});
});

let toplevel_params = { };
on("click", ".anchorprops", e => {
	//Encapsulation breach as above
	toplevelflags.forEach(f => toplevel_params[f] = DOM("#command_details select[data-flag=" + f + "]").value);
	toplevel_params._onsave = () => toplevelflags.forEach(f => DOM("#command_details select[data-flag=" + f + "]").value = toplevel_params[f]);
	window.open_element_properties(toplevel_params);
});

on("change", 'select[data-flag="dest"]', e => e.match.closest("table").dataset.dest = e.match.value);
on("change", 'select[data-flag="builtin"]', e => {
	const builtin = e.match.closest("table").dataset.builtin = e.match.value;
	set_content(e.match.closest("table").querySelector(".paramrow tbody"), describe_builtin_vars(builtin));
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
export function cls_save_message() {
	return {...toplevel_params, ...get_command_details(DOM("#command_details > .optedmsg"))};
}
export function cls_load_message(cmd_basis, cmd_editing) {
	//HACK: The server's validation for tab changing doesn't know that this is a trigger,
	//so if the basis doesn't tell us what type to be (ie it's a trigger), remove a blank
	//"otherwise" branch, so it doesn't show to the user.
	if (!cmd_basis.type && cmd_editing.otherwise === "") delete cmd_editing.otherwise;
	toplevel_params = {...cmd_basis, message: cmd_editing};
	anchor_props.forEach(f => cmd_editing[f] && (toplevel_params[f] = cmd_editing[f]));
	set_content("#command_details", [
		//Maybe make the Provides entries clickable to insert that token in the current EF??
		UL(Object.keys(cmd_basis.provides || { }).map(p => LI([CODE(p), " - " + cmd_basis.provides[p]]))),
		render_command(toplevel_params, cmd_basis.type === "anchor_command"),
	]);
}
