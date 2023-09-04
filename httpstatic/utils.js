//Usage:
//import {...} from "$$static||utils.js$$";

import {choc, on, fix_dialogs} from "https://rosuav.github.io/choc/factory.js";
const {BR, BUTTON, DIALOG, DIV, H3, HEADER, INPUT, LABEL, LINK, OPTGROUP, OPTION, P, SECTION, SELECT, TABLE, TD, TEXTAREA, TH, TR} = choc; //autoimport
ensure_simpleconfirm_dlg(); //Unnecessary overhead once Firefox 98+ is standard - can then be removed
fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: "formless"});

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

on("click", ".twitchlogin", async e => {
	let scopes = e.match.dataset.scopes || ""; //Buttons may specify their scopes-required, otherwise assume just identity is needed
	const data = await (await fetch("/twitchlogin?urlonly=true&scope=" + scopes)).json();
	window.open(data.uri, "login", "width=525, height=900");
});

on("click", ".twitchlogout", async e => {
	await fetch("/logout"); //Don't care what the response is (it'll be HTML anyway)
	location.reload();
});

export function TEXTFORMATTING(cfg) {return TABLE({border: 1}, [
	cfg.textname !== "-" && TR({class: cfg.textclass || ""}, [TH(cfg.textlabel || "Text"), TD([INPUT({size: 40, name: cfg.textname || "text"}), cfg.textdesc])]),
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
		SELECT({name: "strokewidth"}, [cfg.blank_opts && OPTION(), "None 0.25px 0.5px 0.75px 1px 2px 3px 4px 5px".split(" ").map(o => OPTION(o))]),
		INPUT({name: "strokecolor", type: "color"}),
		" Note: Outline works only in Chrome (including OBS)",
	])]),
	cfg.use_preview && TR([TH("Preview bg"), TD(INPUT({name: "previewbg", type: "color"}))]),
	TR([TH("Border"), TD([
		LABEL(["Width (px): ", INPUT({name: "borderwidth", type: "number"})]),
		LABEL([" Color: ", INPUT({name: "bordercolor", type: "color"})]),
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
	TR([TH("Custom CSS"), TD(INPUT({name: "css", size: 60}))]),
])}

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

on("click", ".clipbtn", e => {
	try {navigator.clipboard.writeText(e.match.dataset.copyme);}
	catch (exc) {
		//If we can't copy to clipboard, it might be possible to do it via an MLE.
		const mle = TEXTAREA({value: e.match.dataset.copyme, style: "position: absolute; left: -99999999px"});
		document.body.append(mle);
		mle.select();
		try {document.execCommand("copy");}
		finally {mle.remove();}
	}
	const c = DOM("#copied");
	c.classList.add("shown");
	c.style.left = e.pageX + "px";
	c.style.top = e.pageY + "px";
	setTimeout(() => c.classList.remove("shown"), 1000);
});

const sidebar = DOM("nav#sidebar"), box = DOM("#togglesidebarbox");
on("click", "#togglesidebar", e => {
	if (sidebar) sidebar.classList.toggle("vis");
	box.classList.toggle("sbvis");
	window.onresize = null; //No longer automatically toggle as the window resizes.
});
//On wide windows, default to having the sidebar visible.
(sidebar || box) && (window.onresize = () => {
	const sbvis = window.innerWidth > 600;
	if (sidebar) sidebar.classList.toggle("vis", sbvis);
	if (box) box.classList.toggle("sbvis", sbvis);
})();
