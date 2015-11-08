import std.stdio;
import desktopfile;
import std.getopt;
import std.process;

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
    if (args.length < 3) {
        writefln("Usage: %s <read|exec|link|start|write> <desktop-file> <optional arguments>", args[0]);
        return;
    }
    
    string command = args[1];
    string inFile = args[2];
    string locale = currentLocale();
    
    if (command == "read") {
        auto df = new DesktopFile(inFile);
        
        writefln("Name: %s. Localized: %s", df.name(), df.localizedName(locale));
        writefln("GenericName: %s. Localized: %s", df.genericName(), df.localizedGenericName(locale));
        writefln("Comment: %s. Localized: %s", df.comment(), df.localizedComment(locale));
        writeln("Type: ", df.value("Type"));
        writeln("Icon: ", df.iconName());
        version(OSX) {} else version(Posix) {
            writeln("Desktop ID: ", df.id());
        }
        writefln("Actions: %(%s %)", df.actions());
        writefln("Categories: %(%s %)", df.categories());
        writefln("MimeTypes: %(%s %)", df.mimeTypes());
        
        if (df.type() == DesktopFile.Type.Application) {
            writeln("Exec: ", df.execString());
            writeln("In terminal: ", df.terminal());
        }
        if (df.type() == DesktopFile.Type.Link) {
            writeln("URL: ", df.url());
        }
    } else if (command == "exec") {
        auto df = new DesktopFile(inFile);
        string action;
        getopt(args, "action", "Action to run", &action);
        if (action.length) {
            auto desktopAction = df.action(action);
            if (desktopAction.group() is null) {
                stderr.writefln("No such action %s", action);
            } else {
                desktopAction.start();
            }
        } else {
            string[] urls = args[3..$];
            writeln("Exec:", df.expandExecString(urls, locale));
            df.startApplication(urls, locale);
        }
        
        
    } else if (command == "link") {
        auto df = new DesktopFile(inFile);
        writeln("Link:", df.url());
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
