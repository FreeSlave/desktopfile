/+dub.sdl:
name "shoot"
dependency "desktopfile" path="../"
+/

import std.stdio;
import std.getopt;

import desktopfile.utils;

int main(string[] args)
{
    bool onlyExec;
    bool notFollow;
    string[] appPaths;

    getopt(
        args,
        "onlyExec", "Only start applications, don't open links", &onlyExec,
        "notFollow", "Don't follow desktop files", &notFollow,
        "appPath", "Path of applications directory", &appPaths);


    string inFile;
    if (args.length > 1) {
        inFile = args[1];
    } else {
        stderr.writeln("Must provide path to desktop file");
        return 1;
    }

    if (appPaths.length == 0) {
        static if (isFreedesktop) {
            import desktopfile.paths;
            appPaths = applicationsPaths();
        }
        version(Windows) {
            try {
                auto root = environment.get("SYSTEMDRIVE", "C:");
                auto kdeAppDir = root ~ `\ProgramData\KDE\share\applications`;
                if (kdeAppDir.isDir) {
                    appPaths = [kdeAppDir];
                }
            } catch(Exception e) {

            }
        }
    }

    if (inFile == inFile.baseName && inFile.extension == ".desktop") {
        string desktopId = inFile;
        inFile = findDesktopFile(desktopId, appPaths);
        if (inFile is null) {
            stderr.writeln("Could not find desktop file with such id: ", desktopId);
            return 1;
        }
    }

    ShootOptions options;

    options.urls = args[2..$];

    if (onlyExec) {
        options.flags = options.flags & ~ShootOptions.Link;
    }

    if (notFollow) {
        options.flags = options.flags & ~ ShootOptions.FollowLink;
    }

    try {
        shootDesktopFile(inFile, options);
    }
    catch(Exception e) {
        stderr.writeln(e.msg);
        return 1;
    }

    return 0;
}
