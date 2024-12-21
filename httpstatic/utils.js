//Usage:
//import {...} from "$$static||utils.js$$";

import {choc, on, fix_dialogs} from "https://rosuav.github.io/choc/factory.js";
const {BR, BUTTON, DIALOG, DIV, H3, HEADER, INPUT, LABEL, LINK, OPTGROUP, OPTION, P, SECTION, SELECT, TABLE, TD, TEXTAREA, TH, TR} = choc; //autoimport
ensure_simpleconfirm_dlg(); //Unnecessary overhead once Firefox 98+ is standard - can then be removed
fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: "formless", methods: 1});

//Deprecated. Use simpleconfirm instead - dialogs work in all current browsers (even inside other dlgs).
export function waitlate(wait_time, late_time, confirmdesc, callback) {
	//Assumes that this is attached to a button click. Other objects
	//and other events may work but are not guaranteed.
	let wait = 0, late = 0, timeout = 0, btn, orig;
	function reset() {
		clearTimeout(timeout);
		set_content(btn, orig).disabled = false;
		wait = late = timeout = 0;
	}
	return e => {
		if (btn && btn !== e.match) reset();
		const t = +new Date;
		if (t > wait && t < late) {
			reset();
			callback(e);
			return;
		}
		wait = t + wait_time; late = t + late_time;
		btn = e.match; orig = btn.innerText;
		setTimeout(() => btn.disabled = false, wait_time);
		timeout = setTimeout(reset, late_time);
		set_content(btn, confirmdesc).disabled = true;
	};
}

function ensure_simpleconfirm_dlg() {
	//Setting the z-index is necessary only on older Firefoxes that don't support true showModal()
	if (!DOM("#simpleconfirmdlg")) document.body.appendChild(DIALOG({id: "simpleconfirmdlg", style: "z-index: 999"}, SECTION([
		HEADER([H3("Are you sure?"), DIV(BUTTON({type: "button", class: "dialog_cancel"}, "x"))]),
		DIV([
			P({id: "simpleconfirmdesc"}, "Really do the thing?"),
			P([BUTTON({id: "simpleconfirmyes"}, "Confirm"), BUTTON({class: "dialog_close"}, "Cancel")]),
		]),
	])));
}

function ensure_simplemessage_dlg() {
	//Testing out NOT having the z-index on this
	if (!DOM("#simplemessagedlg")) document.body.appendChild(DIALOG({id: "simplemessagedlg"}, SECTION([
		HEADER([H3("Hello!"), DIV(BUTTON({type: "button", class: "dialog_cancel"}, "x"))]),
		DIV([
			P({id: "simplemessagetext"}, "Hello there."),
			P([BUTTON({class: "dialog_close"}, "OK")]),
		]),
	])));
}

let simpleconfirm_callback = null, simpleconfirm_arg = null, simpleconfirm_match;
//Simple confirmation dialog. If you need more than just a text string in the
//confirmdesc, provide a function; it can return any Choc Factory content.
//One argument will be carried through. For convenience with Choc Factory event
//objects, its match attribute will be carried through independently.
export function simpleconfirm(confirmdesc, callback) {
	ensure_simpleconfirm_dlg();
	return e => {
		simpleconfirm_callback = callback; simpleconfirm_arg = e;
		if (e && e.match) simpleconfirm_match = e.match;
		set_content("#simpleconfirmdesc", typeof confirmdesc === "string" ? confirmdesc : confirmdesc(e));
		DOM("#simpleconfirmdlg").showModal();
	};
}
on("click", "#simpleconfirmyes", e => {
	const cb = simpleconfirm_callback, arg = simpleconfirm_arg;
	if (simpleconfirm_match) arg.match = simpleconfirm_match;
	simpleconfirm_match = simpleconfirm_arg = simpleconfirm_callback = undefined;
	if (cb) cb(arg);
	DOM("#simpleconfirmdlg").close();
})

//Fire-and-forget. There's no callback when the user dismisses the dialog.
export function simplemessage(messagetext, messagetitle) {
	ensure_simplemessage_dlg();
	set_content("#simplemessagetext", messagetext);
	set_content("#simplemessagedlg h3", messagetitle);
	DOM("#simplemessagedlg").showModal();
}

on("click", ".twitchlogin", async e => {
	const scopes = e.match.dataset.scopes || ""; //Buttons may specify their scopes-required, otherwise assume just identity is needed
	const force = e.match.dataset.force ? "&force_verify=true" : "";
	const data = await (await fetch("/twitchlogin?urlonly=true&scope=" + scopes + force)).json();
	window.open(data.uri, "login", "width=525, height=900");
});

on("click", ".twitchlogout", async e => {
	await fetch("/logout"); //Don't care what the response is (it'll be HTML anyway)
	location.reload();
});

on("click", ".opendlg", e => {e.preventDefault(); DOM("#" + e.match.dataset.dlg).showModal();});

export function TEXTFORMATTING(cfg) {
    //Half an indent coz I can't be bothered
    if (cfg.textname === "-") cfg.texts = []; //Compat (deprecated)
    if (!cfg.texts) cfg.texts = [{ }];
    return TABLE({border: 1, "data-copystyles": 1}, [
	cfg.texts.map(t => TR({class: t.class || cfg.textclass || ""}, [TH(t.label || cfg.textlabel || "Text"), TD([INPUT({size: 40, name: t.name || cfg.textname || "text", "data-nocopy": 1}), t.desc])])),
	TR([TH("Font"), TD([
		INPUT({name: "font", size: "28"}),
		SELECT({name: "fontweight"}, [cfg.blank_opts && OPTION(), OPTION("normal"), OPTION("bold")]),
		SELECT({name: "fontstyle"}, [cfg.blank_opts && OPTION(), OPTION("normal"), OPTION("italic")]),
		INPUT({name: "fontsize", type: "number", size: "3", value: "16"}),
		" Family: ", SELECT({name: "fontfamily"}, [
			OPTION({value: ""}, cfg.blank_opts ? "" : "Unspecified"),
			"serif sans-serif monospace cursive fantasy system-ui emoji".split(" ")
			.map(f => OPTION({style: "font-family: " + f}, f))]),
		BR(), "Pick a font from Google Fonts or one that's already on your PC.",
		BR(), "Choosing both a font and the family provides a fallback during loading.",
	])]),
	TR([TH("Text color"), TD([
		INPUT({name: "color", type: "color"}),
		" Outline ",
		SELECT({name: "strokewidth"}, [cfg.blank_opts && OPTION(), "None 0.25px 0.5px 0.75px 1px 2px 3px 4px 5px 7px 9px 12px".split(" ").map(o => OPTION(o))]),
		INPUT({name: "strokecolor", type: "color"}),
		" Note: Outline works only in Chrome (including OBS)",
		//TODO at some point: Add a "stroke inside/outside" option. Works only in Chrome v123 eg OBS 31.0, very new as of 20241222.
	])]),
	cfg.use_preview && TR([TH("Preview bg"), TD(INPUT({name: "previewbg", type: "color"}))]), //Should this one be non-copiable? It's not quite a style, but not quite NOT a style either.
	TR([TH("Border"), TD([
		LABEL(["Width (px): ", INPUT({name: "borderwidth", type: "number"})]),
		LABEL([" Color: ", INPUT({name: "bordercolor", type: "color"})]),
		LABEL(["Radius (px): ", INPUT({name: "borderradius", type: "number"})]),
	])]),
	TR([TH("Padding"), TD([
		LABEL(["Vertical (em): ", INPUT({name: "padvert", type: "number", step: "0.25"})]),
		LABEL([" Horizontal (em): ", INPUT({name: "padhoriz", type: "number", step: "0.25"})]),
	])]),
	TR([TH("Background"), TD([
		LABEL([
			" Opacity (0 to disable): ",
			INPUT({name: "bgalpha", type: "number", min: 0, max: 100, value: 0}),
		]),
		LABEL([" Color: ", INPUT({name: "bgcolor", type: "color"})]),
	])]),
	TR([TH("Drop shadow"), TD([
		"Position (px): ", INPUT({name: "shadowx", type: "number"}), INPUT({name: "shadowy", type: "number"}),
		LABEL([
			" Opacity (0 to disable): ",
			INPUT({name: "shadowalpha", type: "number", min: 0, max: 100, value: 0}),
		]),
		LABEL([" Color: ", INPUT({name: "shadowcolor", type: "color"})]),
	])]),
	//TODO: Gradient?
	TR([TH("Formatting"), TD([
		SELECT({name: "whitespace"}, [
			cfg.blank_opts && OPTION(),
			OPTGROUP({label: "Single line"}, [
				OPTION({value: "normal"}, "Wrapped"),
				OPTION({value: "nowrap"}, "No wrapping"),
			]),
			OPTGROUP({label: "Multi-line"}, [
				OPTION({value: "pre-line"}, "Normal"),
				OPTION({value: "pre"}, "Keep indents"),
				OPTION({value: "pre-wrap"}, "No wrapping"),
			]),
		]),
		"Alignment",
		SELECT({name: "textalign"}, [cfg.blank_opts && OPTION(), "start end center justify".split(" ").map(o => OPTION(o))]),
	])]),
	TR([TH("Custom CSS"), TD(INPUT({name: "css", size: 60, "data-nocopy": 1}))]),
	TR([TH("Share styles"), TD([BUTTON({type: "button", class: "copystyles"}, "Copy to clipboard"), BUTTON({type: "button", class: "pastestyles"}, "Paste from clipboard")])]),
    ]);
}

//Ensure that a font is loaded if applicable. If this fails, the font may
//still be usable if installed on the person's computer (not suitable for
//external use of course, but for something inside OBS, that's fine).
//Note: It's safe to call this more than once for the same font.
export function ensure_font(font) {
	if (!font) return; //Omitted? Blank? Not a problem.
	font = font.replace('"', '').replace('"', ''); //Remove any spare quotes. TODO: Also split on commas, not counting commas in quotes.
	const id = "fontlink_" + encodeURIComponent(font);
	if (document.getElementById(id)) return; //Got it already.
	document.body.appendChild(LINK({
		id, rel: "stylesheet",
		href: "https://fonts.googleapis.com/css2?family=" + encodeURIComponent(font) + "&display=swap",
	}));
}

export function copytext(copyme) {
	try {navigator.clipboard.writeText(copyme);} //TODO: What if this fails asynchronously?
	catch (exc) {
		//If we can't copy to clipboard, it might be possible to do it via an MLE.
		const mle = TEXTAREA({value: copyme, style: "position: absolute; left: -99999999px"});
		document.body.append(mle);
		mle.select();
		try {document.execCommand("copy");}
		finally {mle.remove();}
	}
}

//Note that this uses #copied for hysterical raisins, but any quick description label will work.
export function notify(elem, x, y, label) {
	const c = DOM("#copied") || DIV({id: "copied"});
	const par = (elem && elem.closest("dialog")) || document.body;
	par.append(c); //Reparent the marker element to the dialog or document every time it's used
	set_content(c, label).classList.add("shown");
	c.style.left = x + "px";
	c.style.top = y + "px";
	setTimeout(() => c.classList.remove("shown"), 1000);
}

on("click", ".clipbtn", e => {copytext(e.match.dataset.copyme); notify(e.match, e.clientX, e.clientY, "Copied!");});
on("click", ".copystyles", e => {
	const par = e.match.closest("[data-copystyles]");
	if (!par) return;
	let styles = "";
	par.querySelectorAll("input,select").forEach(inp => {
		if (!inp.dataset.nocopy) styles += inp.name + ": " + inp.value + "\n";
	});
	copytext(styles);
	notify(e.match, e.clientX, e.clientY, "Copied!");
});

on("click", ".pastestyles", async e => {
	const elem = e.match;
	let clip;
	try {clip = await(navigator.clipboard.readText());}
	catch (exc) {
		//Do we need an MLE-based fallback? Wasn't able to get it to work.
		console.error(exc);
		console.warn("Clipboard paste failed, maybe too old Firefox? Upgrade to v125 or newer to be able to paste.");
		notify(elem, e.clientX, e.clientY, "Paste failed");
		return;
	}
	const values = { };
	clip.replace(/^([^:]+): ([^\n]*)$/gm, (m, k, v) => values[k] = v); //Yeah this is abusing replace() a bit.
	const par = elem.closest("[data-copystyles]");
	if (!par) return;
	let styles = "";
	par.querySelectorAll("input,select").forEach(inp => {
		if (!inp.dataset.nocopy && typeof values[inp.name] === "string") inp.value = values[inp.name];
	});
	notify(elem, e.clientX, e.clientY, "Pasted!");
});

const sidebar = DOM("nav#sidebar"), box = DOM("#togglesidebarbox");
const sbvis = window.matchMedia("screen and (width >= 600px)");
on("click", "#togglesidebar", e => {
	if (sidebar) sidebar.classList.toggle("vis");
	box.classList.toggle("sbvis");
	sbvis.onchange = null; //No longer automatically toggle as the window resizes.
});
//On wide windows, default to having the sidebar visible.
(sidebar || box) && (sbvis.onchange = () => {
	if (sidebar) sidebar.classList.toggle("vis", sbvis.matches);
	if (box) box.classList.toggle("sbvis", sbvis.matches);
})();

//window.onerror = (msg, source, line, col) => window.__socket__ && ws_sync.send({cmd: "error", msg, source, line, col});
