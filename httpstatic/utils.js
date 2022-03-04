//Usage:
//import {...} from "$$static||utils.js$$";

import {on, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {BR, INPUT, LINK, OPTGROUP, OPTION, SELECT, TABLE, TD, TH, TR} = choc; //autoimport
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
	TR([TH(cfg.textlabel || "Text"), TD([INPUT({size: 40, name: cfg.textname || "text"}), cfg.textdesc])]),
	TR([TH("Font"), TD([
		INPUT({name: "font", size: "28"}),
		SELECT({name: "fontweight"}, [OPTION("normal"), OPTION("bold")]),
		SELECT({name: "fontstyle"}, [OPTION("normal"), OPTION("italic")]),
		INPUT({name: "fontsize", type: "number", size: "3", value: "16"}),
		BR(), "Pick a font from Google Fonts or one that's already on your PC.",
	])]),
	TR([TH("Text color"), TD([
		INPUT({name: "color", type: "color"}),
		" Outline ",
		SELECT({name: "strokewidth"}, ["None 0.25px 0.5px 0.75px 1px 2px 3px 4px 5px".split(" ").map(o => OPTION(o))]),
		INPUT({name: "strokecolor", type: "color"}),
		" Note: Outline works only in Chrome (including OBS)",
	])]),
	cfg.use_preview && TR([TH("Preview bg"), TD(INPUT({name: "previewbg", type: "color"}))]),
	TR([TH("Border"), TD([
		"Width (px): ", INPUT({name: "borderwidth", type: "number"}),
		" Color: ", INPUT({name: "bordercolor", type: "color"}),
	])]),
	TR([TH("Drop shadow"), TD([
		"Position (px): ", INPUT({name: "shadowx", type: "number"}), INPUT({name: "shadowy", type: "number"}),
		" Color: ", INPUT({name: "shadowcolor", type: "color"}),
		" Opacity: ", INPUT({name: "shadowalpha", type: "number", min: 0, max: 100, value: 0}),
		" 0 to disable",
	])]),
	//TODO: Gradient?
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
	TR([TH("Custom CSS"), TD(INPUT({name: "css", size: 60}))]),
])}

//Ensure that a font is loaded if applicable. If this fails, the font may
//still be usable if installed on the person's computer (not suitable for
//external use of course, but for something inside OBS, that's fine).
//Note: It's safe to call this more than once for the same font.
export function ensure_font(font) {
	if (!font) return; //Omitted? Blank? Not a problem.
	const id = "fontlink_" + encodeURIComponent(font);
	if (document.getElementById(id)) return; //Got it already.
	document.body.appendChild(LINK({
		id, rel: "stylesheet",
		href: "https://fonts.googleapis.com/css2?family=" + encodeURIComponent(font) + "&display=swap",
	}));
}
