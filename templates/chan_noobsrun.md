# How far will $$channel$$ run?

> <button type=button class=dialog_cancel>x</button>
>
> Edit mileage response <code id=cmdname></code>
>
> <div id=command_details></div>
>
> <p><button type=button id=save_advanced>Save</button> <button type=button class=dialog_close>Cancel</button></p>
>
{: tag=dialog #advanced_view}

<style>
input[type=number] {width: 4em;}
.preview-frame {
	border: 1px solid black;
	padding: 4px;
}
.preview-bg {padding: 6px;}
#preview div {width: 33%;}
#preview div:nth-of-type(2) {text-align: center;}
#preview div:nth-of-type(3) {text-align: right;}

.optionset {display: flex; padding: 0.125em 0;}
.optionset fieldset {padding: 0.25em; margin-left: 1em;}
</style>

<table border=1>
<tr><th>Variable</th><td><input size=20 name=varname></td></tr>
<tr><th>Current</th><td><input size=10 name=currentval><select name=milepicker></select><button type=button id=setval>Set</button><br>
	NOTE: This will override any donations! Be careful!
	<br>Changes made here are NOT applied with the Save button.
</td></tr>
<tr><th>Text</th><td><input size=60 name=text><br>Put a '#' where the mile count should go - it'll be replaced<br>with the actual number.</td></tr>
<tr><th>Cost per mile</th><td><input size=60 name=thresholds><br>eg "10 10 10 10 20 30 40 50" for slowly ramping up costs</td></tr>
<tr><th>Font</th><td>
	<input size=40 name=font>
	<select name=fontweight><option>normal</option><option>bold</option></select>
	<input name=fontsize type=number value=16><br>
	Pick a font from Google Fonts or one that's<br>
	already on your PC. (Name is case sensitive.)
</td></tr>
<tr><th>Colors</th><td><div class=optionset>
	<fieldset><legend>Text</legend><input type=color name=color></fieldset>
	<fieldset><legend>Bar</legend><input type=color name=barcolor></fieldset>
	<fieldset><legend>Fill</legend><input type=color name=fillcolor></fieldset>
	<fieldset><legend>Border</legend><input type=color name=bordercolor> <input type=number name=borderwidth>px</fieldset>
</div></td></tr>
<tr><th>Padding</th><td><div class=optionset>
	<fieldset><legend>Vertical</legend><input type=number name=padvert min=0 max=2 step=0.005> em</fieldset>
	<fieldset><legend>Horizontal</legend><input type=number name=padhoriz min=0 max=2 step=0.005> em</fieldset>
</div></td></tr>
<tr><th>Needle size</th><td><input type=number name=needlesize min=0 max=1 step=0.005 value=0.375> Thickness of the red indicator needle</td></tr>
<tr><th>Next mile response</th><td><code>testing testing</code> <button class=advview data-cmd=nextmile>Edit</button></td></tr>
<tr><th>Custom CSS</th><td><textarea name=css></textarea></td></tr>
<tr><th>Preview</th><td><div id=preview></div></td></tr>
<tr><th>Link</th><td><a href="monitors?view=$$nonce$$" class=monitorlink>Drag me to OBS</a></td></tr>
</table>
<input type=submit value=Save>

<script type=module src="$$static||noobsrun.js$$"></script>
<script type=module src="$$static||commands.js$$"></script>
