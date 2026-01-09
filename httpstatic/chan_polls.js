import {lindt, replace_content, on} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, LI, OPTION, SELECT, TABLE, TBODY, TD, TH, THEAD, TIME, TR, UL} = lindt; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

function DATE(d) {
	if (!d) return "(unknown)";
	const date = new Date(d * 1000);
	let day = date.getDate();
	switch (day) {
		case 1: case 21: day += "st"; break;
		case 2: case 22: day += "nd"; break;
		case 3: case 23: day += "rd"; break;
		default: day += "th";
	}
	return TIME({datetime: date.toISOString(), title: date.toLocaleString()}, [
		//This abbreviated format assumes English and shows just the date. The hover uses your locale.
		"Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(" ")[date.getMonth()] + " " + day,
	]);
}

function results_summary(options) {
	const votes = options.toSorted((a, b) => b.votes - a.votes);
	let totvotes = 0; options.forEach(o => totvotes += o.votes);
	if (!totvotes) return "no votes";
	let ret = [];
	//With five options, this might get quite long - only show the winner and runner-up
	options.forEach(o => o.votes && ret.length < 2 && ret.push(Math.floor(o.votes * 100 / totvotes) + "% " + o.title));
	return ret.join(", ");
}

function show_poll_results(rslt) {
	if (!rslt) replace_content("#resultdetails", "");
	console.log(rslt)
	const opts = rslt.options.toSorted((a, b) => b.votes - a.votes);
	let totvotes = 0; rslt.options.forEach(o => totvotes += o.votes);
	if (!totvotes) totvotes = 1; //If no votes were cast, everything shows as 0%.
	replace_content("#resultdetails", [
		"Poll conducted ", DATE(rslt.completed),
		TABLE([
			THEAD(TR([TH("Option"), TH("Votes"), TH("Percentage")])),
			TBODY(opts.map(o => TR([
				TD(o.title),
				TD([""+o.votes, o.channel_points_votes && " (" + (o.votes - o.channel_points_votes) + "+" + o.channel_points_votes + ")"]),
				TD(Math.floor(o.votes * 100 / totvotes) + "%"),
			]))),
		]),
	]);
}

let pollresults = { };
function update_results_view(poll) {
	replace_content("#resultsummary", [
		//Summary of all times this has been asked
		SELECT({id: "pickresults", value: poll.results[poll.results.length - 1]?.completed}, [
			poll.results.map(r => OPTION({value: r.completed}, [
				poll.results.length > 1 && [ //Differentiate results by date if there are multiple. If multiple on same day, sorry, use the sequence.
					DATE(r.completed), //NOTE: Browsers ignore the element and just include the text. Would be nice to get the hover but so be it.
					" - ",
				],
				results_summary(r.options),
			])),
		]),
	]);
	pollresults = { };
	poll.results.forEach(r => pollresults[r.completed] = r);
	show_poll_results(pollresults[DOM("#pickresults").value]);
}

let selectedpoll = null;
export function render(data) {
	//TODO: If !data.polls.length, put in a placeholder
	replace_content("#polls tbody", data.polls.map((p, idx) => TR({".polldata": p, "data-idx": idx}, [
		TD(DATE(p.created)), TD(DATE(p.lastused)),
		TD(p.title),
		TD(UL(p.options.split("\n").map(o => LI(o)))),
		TD(p.duration+""), //TODO: 60 -> "1 minute" etc
		TD(p.points || ""),
		TD("TODO"),
		TD(BUTTON({class: "delete"}, "X")),
	])));
	//If you have a poll selected, update any results. Should we update everything about it? Might mess with you
	//if you're editing the poll for subsequent usage.
	if (selectedpoll) data.polls.forEach(p => p.title + "\n" + p.options === selectedpoll && update_results_view(p));
}

on("click", "#polls tr[data-idx]", e => {
	const poll = e.match.polldata;
	if (!poll) return;
	const form = DOM("#config").elements;
	selectedpoll = poll.title + "\n" + poll.options;
	form.created.value = poll.created; //TODO: Format with both date and time
	form.lastused.value = poll.lastused; //ditto
	form.title.value = poll.title;
	form.options.value = poll.options;
	form.duration.value = poll.duration;
	form.points.value = poll.points;
	update_results_view(poll);
});

on("change", "#pickresults", e => show_poll_results(pollresults[e.match.value]));

on("submit", "#config", e => {
	e.preventDefault();
	const el = DOM("#config").elements;
	const msg = {cmd: "askpoll"};
	"title options duration points".split(" ").forEach(id => msg[id] = el[id].value);
	ws_sync.send(msg);
});

on("click", ".delete", simpleconfirm("Delete this poll?", e => {
	ws_sync.send({cmd: "delpoll", idx: +e.match.closest_data("idx")});
}));
