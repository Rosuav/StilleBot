import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {AUDIO, DIV, FIGCAPTION, FIGURE, IMG, LINK, P} = choc; //autoimport
import "https://cdn.jsdelivr.net/npm/comfy.js/dist/comfy.min.js"; const ComfyJS = window.ComfyJS;

const alert_formats = {
	text_image_stacked: data => FIGURE({
		className: "text_image_stacked " + (data.layout||""),
		style: `width: ${data.alertwidth||250}px; max-height: ${data.alertheight||250}px;`,
	}, [
		IMG({src: data.image}),
		FIGCAPTION({"data-textformat": data.textformat, style: data.text_css || ""}, data.textformat),
		AUDIO({preload: "auto", src: data.sound, volume: data.volume ** 2}),
	]),
	text_image_overlaid: data => DIV(
		{
			//The layout might be "top_middle", but in CSS, we can handle each dimension
			//separately, so apply classes of "top middle" instead :)
			className: "text_image_overlaid " + (data.layout||"").replace("_", " "),
			style: `background-image: url(${data.image}); width: ${data.alertwidth||250}px; height: ${data.alertheight||250}px;`,
		}, [
			DIV({"data-textformat": data.textformat, style: data.text_css || ""}, data.textformat),
			AUDIO({preload: "auto", src: data.sound, volume: data.volume ** 2}),
		]
	),
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

let inited = false, token = null;
export function render(data) {
	//If, in the future, I need more than one alert type (with distinct formats),
	//replace <main></main> with a set of position-absolute tiles, all on top of
	//each other, each with an ID that says what it is. Alert queueing would be
	//shared across all of them, but each alert type would activate a different
	//element. We guard against playing one audio while another is unpaused.
	//This would then iterate over all of alertconfigs, creating all that are
	//needed; it would need to destroy any that are NOT needed, without flickering
	//those that are still present.
	if (data.alertconfigs && data.alertconfigs.hostalert) {
		const cfg = data.alertconfigs.hostalert;
		if (alert_formats[cfg.format]) set_content("#hostalert", alert_formats[cfg.format](cfg));
		else set_content("#hostalert", P("Unrecognized alert format, check editor or refresh page"));
		DOM("#hostalert").dataset.alertlength = cfg.alertlength || 6;
		DOM("#hostalert").dataset.alertgap = cfg.alertgap || 1;
		if (cfg.font) {
			//TODO: Deduplicate this with monitor.js
			const id = "fontlink_" + encodeURIComponent(cfg.font);
			if (!document.getElementById(id)) document.body.appendChild(LINK({
				id, rel: "stylesheet",
				href: "https://fonts.googleapis.com/css2?family=" + encodeURIComponent(cfg.font) + "&display=swap",
			}));
		}
	}
	if (data.send_alert) do_alert("#hostalert", data.send_alert, Math.floor(Math.random() * 100) + 1);
	if (data.token && data.token !== token) {
		if (inited) ComfyJS.Disconnect();
		inited = true;
		ComfyJS.Init(ws_group.split("#")[1], data.token);
	}
}

setTimeout(() => {
	if (inited) return; //All good!
	set_content("#hostalert", P("No login token provided - check configuration or refresh page"));
}, 5000);

const alert_queue = [];
let alert_playing = false;

function next_alert() {
	alert_playing = false;
	const next = alert_queue.shift();
	if (next) do_alert(...next);
}

function remove_alert(alert, gap) {
	DOM(alert).classList.remove("active");
	setTimeout(next_alert, gap * 1000);
}

function do_alert(alert, channel, viewers) {
	if (alert_playing) {alert_queue.push([alert, channel, viewers]); return;}
	alert_playing = true;
	const elem = DOM(alert);
	elem.querySelectorAll("[data-textformat]").forEach(el =>
		set_content(el, el.dataset.textformat.replace("{NAME}", channel).replace("{VIEWERS}", viewers))
	);
	//Force animations to restart
	elem.querySelectorAll("img").forEach(el => el.src = el.src);
	elem.classList.add("active");
	let playing = false;
	document.querySelectorAll("audio").forEach(a => {if (!a.paused) playing = true;});
	if (!playing) elem.querySelector("audio").play();
	setTimeout(remove_alert, elem.dataset.alertlength * 1000, alert, elem.dataset.alertgap);
}
window.ping = () => do_alert("#hostalert", "Test", 42);

const current_hosts = { };
ComfyJS.onHosted = (username, viewers, autohost, extra) => {
	//Note that ComfyJS itself never seems to announce autohosts. It also
	//doesn't provide the displayname, so we fall back on the username.
	if (current_hosts[username]) return;
	current_hosts[username] = 1;
	console.log("HOST:", username, viewers, autohost, extra);
	do_alert("#hostalert", username, viewers);
};
