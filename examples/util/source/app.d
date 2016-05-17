import std.stdio;
import std.getopt;
import std.process;
import std.path;

import desktopfile.file;
import findexecutable;
import isfreedesktop;

@safe string currentLocale() nothrow
{
    try {
        return environment.get("LC_CTYPE", environment.get("LC_ALL", environment.get("LANG")));
    }
    catch(Exception e) {
        return null;
    }
}

void main(string[] args)
{
    string action;
    string[] appPaths;
    getopt(args, 
           "action", "Action to run", &action,
           "appPath", "Path of applications directory", &appPaths
          );
    
    if (args.length < 3) {
        writefln("Usage: %s <read|exec|open|start|write> <desktop-file> <optional arguments>", args[0]);
        return;
    }
    
    string command = args[1];
    string inFile = args[2];
    string locale = currentLocale();
    
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
            return;
        }
    }
    
    if (command == "read") {
        auto df = new DesktopFile(inFile);
        
        writefln("Name: %s. Localized: %s", df.displayName(), df.localizedDisplayName(locale));
        writefln("GenericName: %s. Localized: %s", df.genericName(), df.localizedGenericName(locale));
        writefln("Comment: %s. Localized: %s", df.comment(), df.localizedComment(locale));
        writeln("Type: ", df.value("Type"));
        writeln("Icon: ", df.iconName());
        static if (isFreedesktop) {
            writeln("Desktop ID: ", df.id());
        }
        writefln("Actions: %(%s %)", df.actions());
        writefln("Categories: %(%s %)", df.categories());
        writefln("MimeTypes: %(%s %)", df.mimeTypes());
        
        if (df.type() == DesktopFile.Type.Application) {
            writeln("Exec: ", df.execValue());
            writeln("In terminal: ", df.terminal());
            writeln("Trusted: ", isTrusted(df.fileName));
        }
        if (df.type() == DesktopFile.Type.Link) {
            writeln("URL: ", df.url());
        }
    } else if (command == "exec") {
        auto df = new DesktopFile(inFile);
        if (action.length) {
            auto desktopAction = df.action(action);
            if (desktopAction is null) {
                stderr.writefln("No such action %s", action);
            } else {
                desktopAction.start();
            }
        } else {
            string[] urls = args[3..$];
            string[] appArgs = df.expandExecValue(urls, locale);
            writefln("Exec: %(%s %)", appArgs);
            df.startApplication(urls, locale);
        }
    } else if (command == "open") {
        auto df = new DesktopFile(inFile);
        writeln("Link: ", df.url());
        df.startLink();
    } else if (command == "start") {
        auto df = new DesktopFile(inFile);
        df.start();
    } else if (command == "write") {
        auto df = new DesktopFile(inFile, DesktopFile.ReadOptions.preserveComments);
        if (args.length > 3) {
            string outFile = args[3];
            df.saveToFile(outFile);
        } else {
            writeln(df.saveToString());
        }
    } else {
        stderr.writefln("unknown command '%s'", command);
    }
}
