import std.stdio;
import desktopfile;

void main(string[] args)
{
    if (args.length < 3) {
        writefln("Usage: %s <read|exec|link|write> <desktop-file> <optional arguments>", args[0]);
        return;
    }
    
    string inFile = args[2];
    auto df = new DesktopFile(inFile, DesktopFile.ReadOptions.preserveComments);
    string command = args[1];
    
    if (command == "read") {
        foreach(group; df.byGroup()) {
            writefln("[%s]", group.name);
            foreach(t; group.byKeyValue()) {
                writefln("%s=%s", t.key, t.value);
            }
        }
    } else if (command == "exec") {
        string[] urls = args[3..$];
        writeln("Exec:", df.expandExecString(urls));
        df.startApplication(urls);
    } else if (command == "link") {
        df.startLink();
    } else if (command == "write") {
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