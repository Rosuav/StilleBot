# VLC integration

(loading...)
{:#nowplaying}

> ### Recently played
> * loading...
> {:#recent}
>
{: tag=details $$showrecents||$$}

<style>
#nowplaying {
	background: #ddffdd;
	border: 1px solid #007700;
	font-size: larger;
}
#recent li:nth-child(even) {
	background: #ddffee;
}
#recent li:nth-child(odd) {
	background: #eeffdd;
}
details {border: 1px solid transparent;} /* I love "solid transparent", ngl */
details#config {
	padding: 0 1.5em;
	border: 1px solid rebeccapurple;
}
#config summary {
	margin: 0 -1.5em;
}
</style>

$$modconfig||$$

$$save_or_login$$
