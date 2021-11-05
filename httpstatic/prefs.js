import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {P, SECTION, TEXTAREA, DIV, BR} = choc;

const render_pref = {
	//Provide a function to render each thing, based on the prefs key
	demo: val => P("Demo"),

	//Any unknowns will be rendered with this
	"": (key, val) => {
		if (typeof val === "string") {
			//Should this be editable?
			return [DIV([key, BR(), "Text string"]), TEXTAREA({rows: 4, cols: 40}, val)];
		}
		return [
			DIV([key, BR(), Array.isArray(val) ? "Array" : "Mapping"]),
			TEXTAREA({rows: 10, cols: 40, readOnly: true}, JSON.stringify(val, null, 4)),
		];
	},
};

export function render(data) { } //Won't ever get anything interesting
ws_sync.prefs_notify(prefs => {
	const sections = [];
	for (let key in prefs) {
		sections.push(
			render_pref[key] ? SECTION({className: "pref_" + key}, render_pref[key](prefs[key]))
			: SECTION({className: "pref_unknown"}, render_pref[""](key, prefs[key]))
		);
	}
	set_content("#prefs", sections);
});
