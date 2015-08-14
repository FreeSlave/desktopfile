import std.stdio;
import desktopfile;

void main(string[] args)
{
    if (args.length < 3) {
        writefln("Usage: %s <read|exec|link|start|write> <desktop-file> <optional arguments>", args[0]);
        return;
    }
    
    string command = args[1];
    string inFile = args[2];
    
    
    if (command == "read") {
        auto df = new DesktopFile(inFile, DesktopFile.ReadOptions.preserveComments | DesktopFile.ReadOptions.firstGroupOnly);
        
        writeln("Name: ", df.name());
        writeln("GenericName: ", df.genericName());
        writeln("Comment: ", df.comment());
        writeln("Type: ", df.value("Type"));
        writeln("Icon: ", df.iconName());
        writeln("Desktop ID: ", df.id());
        
        if (df.type() == DesktopFile.Type.Application) {
            writeln("Exec: ", df.execString());
            writeln("In terminal: ", df.terminal());
        }
        if (df.type() == DesktopFile.Type.Link) {
            writeln("URL: ", df.url());
        }
    } else if (command == "exec") {
        auto df = new DesktopFile(inFile, DesktopFile.ReadOptions.firstGroupOnly);
        string[] urls = args[3..$];
        writeln("Exec:", df.expandExecString(urls));
        df.startApplication(urls);
    } else if (command == "link") {
        auto df = new DesktopFile(inFile, DesktopFile.ReadOptions.firstGroupOnly);
        writeln("Link:", df.url());
        df.startLink();
    } else if (command == "start") {
        auto df = new DesktopFile(inFile, DesktopFile.ReadOptions.firstGroupOnly);
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
        writefln("unknown command '%s'", command);
    }
}
