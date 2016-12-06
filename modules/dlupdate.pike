#if constant(G)
inherit menu_item;
#endif

//Most of this code is lifted from Gypsum. TODO: Synchronize them somehow. Or make this all
//part of some kind of generic framework, like Hogan has - it'd be a self-updating GUI app.

//Unzip the specified data (should be exactly what could be read from/written to a .zip file)
//and call the callback for each file, with the file name, contents, and the provided arg.
//Note that content errors will be thrown, but previously-parsed content has already been
//passed to the callback. This may be considered a feature.
//Note that this can't cope with prefixed zip data (eg a self-extracting executable).
//It is also poorly suited to large files, as it keeps all parts of the process in memory;
//in the pathological case of a gigantic one-file zip, this will have the original data, the
//compressed chunk, the uncompressed result, and several intermediate sscanf temporaries,
//all in memory simultaneously. See my shed/unzip.pike for a Stdio.Buffer implementation -
//it requires Pike 8.0 (this one runs happily on 7.8), but should keep less in memory.
//This is not a general unzip tool, but it could be turned into one if needed.
void unzip(string data,function callback,mixed|void callback_arg)
{
	if (has_prefix(data,"PK\5\6")) return; //File begins with EOCD marker, must be empty.
	while (sscanf(data,"PK\3\4%-2c%-2c%-2c%-2c%-2c%-4c%-4c%-4c%-2c%-2c%s",
		int minver,int flags,int method,int modtime,int moddate,int crc32,
		int compsize,int uncompsize,int fnlen,int extralen,data))
	{
		string fn=data[..fnlen-1]; data=data[fnlen..]; //I can't use %-2H for these, because the two lengths come first and then the two strings. :(
		string extra=data[..extralen-1]; data=data[extralen..]; //Not actually used, and I have no idea whether it'll ever be important to GitHub update.
		string zip=data[..compsize-1]; data=data[compsize..];
		if (flags&8) {zip=data; data=0;} //compsize will be 0 in this case.
		string result,eos;
		switch (method)
		{
			case 0: result=zip; eos=""; break; //Stored (incompatible with flags&8 mode)
			case 8:
				#if constant(Gz)
				object infl=Gz.inflate(-15);
				result=infl->inflate(zip);
				eos=infl->end_of_stream();
				#else
				error("Gz module unavailable, cannot decompress");
				#endif
				break;
			default: error("Unknown compression method %d (%s)",method,fn); 
		}
		if (flags&8)
		{
			//The next block should be the CRC and size marker, optionally prefixed with "PK\7\b". Not sure
			//what happens if the crc32 happens to be exactly those four bytes and the header's omitted...
			if (eos[..3]=="PK\7\b") eos=eos[4..]; //Trim off the marker
			sscanf(eos,"%-4c%-4c%-4c%s",crc32,compsize,uncompsize,data);
		}
		#if __REAL__VERSION__<8.0
		//There seems to be a weird bug with Pike 7.8.866 on Windows which means that a correctly-formed ZIP
		//file will have end_of_stream() return 0 instead of "". No idea why. This is resulting in spurious
		//errors, For the moment, I'm just suppressing this error in that case.
		else if (!eos) ;
		#endif
		else if (eos!="") error("Malformed ZIP file (bad end-of-stream on %s)",fn);
		if (sizeof(result)!=uncompsize) error("Malformed ZIP file (bad file size on %s)",fn);
		#if constant(Gz)
		//NOTE: In older Pikes, Gz.crc32() returns a *signed* integer.
		int actual=Gz.crc32(result); if (actual<0) actual+=1<<32;
		if (actual!=crc32) error("Malformed ZIP file (bad CRC on %s)",fn);
		#endif
		callback(fn,result,callback_arg);
	}
	if (data[..3]!="PK\1\2") error("Malformed ZIP file (bad signature)");
	//At this point, 'data' contains the central directory and the end-of-central-directory marker.
	//The EOCD contains the file comment, which may be of interest, but beyond that, we don't much care.
}

//Callbacks for 'update zip'
void data_available(object q)
{
	//Note that it's impossible for zip update to include a "delete this file" signal.
	//Consequently, file deletions (including renames) would leave old files behind,
	//possibly causing build failures, unless we wipe them out.
	array(string) oldfiles="modules/"+get_dir("modules")[*];
	if (mixed err=catch {unzip(q->data(),lambda(string fn,string data)
	{
		fn -= "StilleBot-master/";
		if (fn=="") return; //Ignore the first-level directory entry
		if (fn[-1]=='/') mkdir(fn); else Stdio.write_file(fn,data);
		if (has_prefix(fn,"modules/")) oldfiles-=({fn});
	});}) {write("%% "+describe_error(err)+"\n"); return;}
	rm(oldfiles[*]);
	G->bootstrap_all();
	if (sizeof(oldfiles)) write("%% Wiped out old files: "+oldfiles*", "+"\n");
}
void request_ok(object q) {q->async_fetch(data_available);}
void request_fail(object q) {write("%% Failed to download latest code\n");}

#if constant(G)
constant menu_label = "Download and update";
void menu_clicked()
{
	#if constant(Protocols.HTTP.do_async_method)
	//Note that the canonical URL is the one in the message, but Pike 7.8 doesn't follow redirects.
	Protocols.HTTP.do_async_method("GET","https://codeload.github.com/Rosuav/StilleBot/zip/master",0,0,
		Protocols.HTTP.Query()->set_callbacks(request_ok,request_fail));
	write("%% Downloading https://github.com/Rosuav/StilleBot/archive/master.zip ...\n");
	#else
	write("%% Pike lacks HTTP engine, unable to download updates\n");
	#endif
}
#else
//Stand-alone usage: Update, with minimal dependencies
//Ideally, this will work even if startup is failing.
object G = this;
void bootstrap_all() {exit(0,"Update complete.\n");}
int main(int argc,array(string) argv)
{
	cd(combine_path(@explode_path(argv[0])[..<2]));
	Protocols.HTTP.do_async_method("GET","https://codeload.github.com/Rosuav/StilleBot/zip/master",0,0,
		Protocols.HTTP.Query()->set_callbacks(request_ok,request_fail,([])));
	write("Downloading latest code...\n");
	return -1;
}
#endif
