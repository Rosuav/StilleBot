import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {DIV, IMG, P} = choc; //autoimport

const alert_formats = {
	text_under: data => DIV({className: "text_under"}, [
		IMG({src: data.image}),
		P({"data-textformat": data.textformat}),
	]),
};

let alert_length = 6;

export function render(data) {
	if (data.alert_format) {
		if (alert_formats[data.alert_format]) set_content("main", alert_formats[data.alert_format](data));
		else set_content("main", P("Unrecognized alert format, check editor or refresh page"));
	}
	if (data.alert_length) alert_length = data.alert_length;
}

function remove_alert() {
	DOM("main").classList.remove("active");
	//If there's a queued alert, schedule it for another 1-2 seconds from now
}

function do_alert(channel, viewers) {
	document.querySelectorAll("main [data-textformat]").forEach(el =>
		set_content(el, el.dataset.textformat.replace("{NAME}", channel).replace("{VIEWERS}", viewers))
	);
	DOM("main").classList.add("active");
	setTimeout(remove_alert, alert_length * 1000);
}
window.ping = () => do_alert("Test", 42);
