import std.stdio;
import std.getopt;

import desktopfile.utils;

int main(string[] args)
{
	bool onlyExec;
	bool notFollow;
	
	getopt(
		args, 
		"onlyExec", "Only start applications, don't open links", &onlyExec,
		"notFollow", "Don't follow desktop files", &notFollow);
		
	
	string fileName;
	if (args.length > 1) {
		fileName = args[1];
	} else {
		stderr.writeln("Must provide path to desktop file");
		return 1;
	}
	
	ShootOptions options;
	
	if (onlyExec) {
		options.flags = options.flags & ~ShootOptions.Link;
	}
	
	if (notFollow) {
		options.flags = options.flags & ~ ShootOptions.FollowLink;
	}
	
	try {
		shootDesktopFile(fileName, options);
	}
	catch(Exception e) {
		stderr.writeln(e.msg);
		return 1;
	}
	
	return 0;
}
