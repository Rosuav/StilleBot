import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {FIGCAPTION, FIGURE, IMG, P} = choc; //autoimport

const alert_formats = {
	text_under: data => FIGURE({className: "text_under"}, [
		IMG({src: data.image}),
		FIGCAPTION({"data-textformat": data.textformat}),
	]),
};

//Timings:
//1) Alert length is the time that the alert is visible, measured from the
//   start of its fade-in to the start of its fade-out.
//2) Fade-in and fade-out are visual effects only; opacity grows/shrinks
//   over time to smooth things out. Keep these short.
//3) Alert gap is the time after the start of fade-out before another alert
//   will be shown. It should be greater than the fade-out, to avoid ugly
//   "snap back to full" visuals.
//4) An animated alert with a period exactly equal to alert_length + fade-out
//   will run once, then disappear. A period half of that will cycle twice etc.
//5) An audio clip shorter than alert_length + alert_gap will leave silence.
//   Longer than that will skip the audio on stacked alerts. Recommend aiming
//   to keep it roughly as long as the alert, no more, no less.
//6) A long alert_gap will result in weird waiting periods between alerts. A
//   short alert_gap will have alerts coming hard on each other's heels.
let alert_length = 6, alert_gap = 2;

export function render(data) {
	if (data.alert_format) {
		if (alert_formats[data.alert_format]) set_content("main", alert_formats[data.alert_format](data));
		else set_content("main", P("Unrecognized alert format, check editor or refresh page"));
	}
	if (data.alert_length) alert_length = data.alert_length;
	if (data.sound) DOM("#alertsound").src = data.sound;
	if (typeof data.volume !== "undefined") DOM("#alertsound").volume = data.volume; //0 is not the same as absent
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
	DOM("#alertsound").play();
	setTimeout(remove_alert, alert_length * 1000);
}
window.ping = () => do_alert("Test", 42);
