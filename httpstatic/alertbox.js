import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {AUDIO, FIGCAPTION, FIGURE, IMG, P} = choc; //autoimport

const alert_formats = {
	text_under: data => FIGURE({className: "text_under"}, [
		IMG({src: data.image}),
		FIGCAPTION({"data-textformat": data.textformat}),
		AUDIO({preload: "auto", src: data.sound, volume: data.volume}),
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
	//If, in the future, I need more than one alert type (with distinct formats),
	//replace <main></main> with a set of position-absolute tiles, all on top of
	//each other, each with an ID that says what it is. Alert queueing would be
	//shared across all of them, but each alert type would activate a different
	//element. TODO: If one audio is playing, don't fire another.
	if (data.alert_format) {
		if (alert_formats[data.alert_format]) set_content("#hostalert", alert_formats[data.alert_format](data));
		else set_content("#hostalert", P("Unrecognized alert format, check editor or refresh page"));
	}
	if (data.alert_length) alert_length = data.alert_length;
}

function remove_alert(alert) {
	DOM(alert).classList.remove("active");
	//If there's a queued alert, schedule it for another alert_gap seconds from now
}

function do_alert(alert, channel, viewers) {
	const elem = DOM(alert);
	elem.querySelectorAll("[data-textformat]").forEach(el =>
		set_content(el, el.dataset.textformat.replace("{NAME}", channel).replace("{VIEWERS}", viewers))
	);
	//Force animations to restart
	elem.querySelectorAll("img").forEach(el => el.src = el.src);
	elem.classList.add("active");
	elem.querySelector("audio").play();
	setTimeout(remove_alert, alert_length * 1000, alert);
}
window.ping = () => do_alert("#hostalert", "Test", 42);
setTimeout(do_alert, 500, "#hostalert", "Demo", 123);
