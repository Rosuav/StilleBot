import choc, {set_content, DOM} from "https://rosuav.github.io/shed/chocfactory.js";
const {DIV} = choc;

let socket;
const protocol = window.location.protocol == "https:" ? "wss://" : "ws://";
//Map the CSS attributes on the server to the names used in element.style
const css_attribute_names = {color: "color", font: "fontFamily", fontweight: "fontWeight", fontstyle: "fontStyle", bordercolor: "borderColor", whitespace: "white-space"};

const currency_formatter = new Intl.NumberFormat("en-US", {style: "currency", currency: "USD"});
function currency(cents) {
	if (cents >= 0 && !(cents % 100)) return "$" + (cents / 100); //Abbreviate the display to "$5" for 500
	return currency_formatter.format(cents / 100);
}

//NOTE: These values persist. If ever a particular ID is used in thresholds mode,
//it must remain so forever (or at least until you refresh the page).
const thresholdinfo = { };
export function render(data) {update_display(DOM("#display"), data.data);}
export default function update_display(elem, data) { //Used for the preview as well as the live display
	//Update styles. If the arbitrary CSS setting isn't needed, make sure it is "" not null.
	let t = thresholdinfo[data.id];
	if (data.css || data.css === "") {
		elem.style.cssText = data.css;
		for (let attr in css_attribute_names) {
			if (data[attr]) elem.style[css_attribute_names[attr]] = data[attr];
		}
		if (data.thresholds && data.barcolor) {
			t = thresholdinfo[data.id] = {t: data.thresholds.split(" ").map(x => x * 100).filter(x => x && x === x)}; //Suppress any that fail to parse as numbers
			t.barcolor = data.barcolor; t.fillcolor = data.fillcolor || data.barcolor;
			//The rest of the style handling is below, since it depends on the text
		}
		if (data.needlesize) t.needlesize = +data.needlesize;
		if (data.fontsize) elem.style.fontSize = data.fontsize + "px"; //Special-cased to add the unit
		//It's more-or-less like saying "padding: {padvert}em {padhoriz}em"
		if (data.padvert)  elem.style.paddingTop = elem.style.paddingBottom = data.padvert + "em";
		if (data.padhoriz) elem.style.paddingLeft = elem.style.paddingRight = data.padhoriz + "em";
		//If you set a border width, assume we want a solid border. (For others, set the
		//entire border definition in custom CSS.)
		if (data.borderwidth) {elem.style.borderWidth = data.borderwidth + "px"; elem.style.borderStyle = "solid";}
		if (data.font) {
			//Attempt to fetch fonts from Google Fonts if they're not installed already
			//This will be ignored by the browser if you have the font, so it's no big
			//deal to have it where it's unnecessary. If you misspell a font name, it'll
			//do a fetch, fail, and then just use a fallback font.
			const id = "fontlink_" + encodeURIComponent(data.font);
			if (!document.getElementById(id)) {
				const elem = document.createElement("link");
				elem.href = "https://fonts.googleapis.com/css2?family=" + encodeURIComponent(data.font) + "&display=swap";
				elem.rel = "stylesheet";
				elem.id = id;
				document.body.appendChild(elem);
			}
		}
	}
	if (t) {
		const thresholds = t.t;
		const m = /^([0-9]+):(.*)$/.exec(data.display);
		if (!m) {console.error("Something's misconfigured (see monitor.js regex)"); return;}
		let pos = m[1], text, mark, goal;
		for (let which = 0; which < thresholds.length; ++which) {
			if (pos < thresholds[which]) {
				//Found the point to work at.
				text = m[2].replace("#", which + 1);
				mark = pos / thresholds[which] * 100;
				goal = thresholds[which];
				break;
			}
			else pos -= thresholds[which];
		}
		if (!text) {
			//We're beyond the last threshold!
			text = m[2].replace("#", thresholds.length);
			mark = 100;
			goal = thresholds[thresholds.length - 1];
		}
		elem.style.background = `linear-gradient(.25turn, ${t.fillcolor} ${mark-t.needlesize}%, red, ${t.barcolor} ${mark+t.needlesize}%, ${t.barcolor})`;
		elem.style.display = "flex";
		set_content(elem, [DIV(text), DIV(currency(pos)), DIV(currency(goal))]);
	}
	else set_content(elem, data.display);
}
