/**
 * Reading, writing and executing .desktop file
 * Authors: 
 *  $(LINK2 https://github.com/MyLittleRobo, Roman Chistokhodov).
 * License: 
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * See_Also: 
 *  $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/index.html, Desktop Entry Specification).
 */

module desktopfile;

public import inilike;

private {
    import std.algorithm;
    import std.array;
    import std.conv;
    import std.exception;
    import std.file;
    import std.path;
    import std.process;
    import std.range;
    import std.stdio;
    import std.string;
    import std.traits;
    import std.typecons;
    
    static if( __VERSION__ < 2066 ) enum nogc = 1;
}

version(Posix)
{
    private bool isExecutable(string filePath) nothrow @trusted {
        import core.sys.posix.unistd;
        return access(toStringz(filePath), X_OK) == 0;
    }
    /**
    * Checks if the program exists and is executable. 
    * If the programPath is not an absolute path, the file is looked up in the $PATH environment variable.
    * This function is defined only on Posix.
    */
    bool checkTryExec(string programPath) @trusted {
        if (programPath.isAbsolute()) {
            return isExecutable(programPath);
        }
        
        foreach(path; environment.get("PATH").splitter(':')) {
            if (isExecutable(buildPath(path, programPath))) {
                return true;
            }
        }
        return false;
    }
}


@trusted string unescapeExec(string str) nothrow pure
{
    static immutable Tuple!(char, char)[] pairs = [
       tuple('"', '"'),
       tuple('\'', '\''),
       tuple('\\', '\\'),
       tuple('>', '>'),
       tuple('<', '<'),
       tuple('~', '~'),
       tuple('|', '|'),
       tuple('&', '&'),
       tuple(';', ';'),
       tuple('$', '$'),
       tuple('*', '*'),
       tuple('?', '?'),
       tuple('#', '#'),
       tuple('(', '('),
       tuple(')', ')'),
    ];
    return doUnescape(str, pairs);
}

/**
 * Get terminal emulator.
 * First, it probes $(B TERM) environment variable. If not found, checks if /usr/bin/x-terminal-emulator exists on Linux and use it on success.
 * $(I xterm) is used by default, if could not determine other terminal emulator.
 * Returns: Terminal emulator command name.
 */
string determineTerminalEmulator() nothrow @trusted 
{
    string term;
    collectException(environment.get("TERM"), term);
    version(linux) {
        if (term.empty) {
            string debianTerm = "/usr/bin/x-terminal-emulator";
            if (debianTerm.isExecutable()) {
                term = debianTerm;
            }
        }
    }
    
    if (term.empty) {
        term = "xterm";
    }
    
    return term;
}

/**
 * Represents .desktop file.
 * 
 */
final class DesktopFile : IniLikeFile
{
public:
    ///Desktop entry type
    enum Type
    {
        Unknown, ///Desktop entry is unknown type
        Application, ///Desktop describes application
        Link, ///Desktop describes URL
        Directory ///Desktop entry describes directory settings
    }
    
    alias IniLikeFile.ReadOptions ReadOptions;
    
    /**
     * Reads desktop file from file.
     * Throws:
     *  $(B ErrnoException) if file could not be opened.
     *  $(B IniLikeException) if error occured while reading the file.
     */
    @safe this(string fileName, ReadOptions options = ReadOptions.noOptions) {
        this(iniLikeFileReader(fileName), options, fileName);
    }
    
    /**
     * Reads desktop file from range of $(B IniLikeLine)s.
     * Throws:
     *  $(B IniLikeException) if error occured while parsing.
     */
    @trusted this(Range)(Range byLine, ReadOptions options = ReadOptions.noOptions, string fileName = null) if(is(ElementType!Range : IniLikeLine))
    {   
        super(byLine, options, fileName);
        _desktopEntry = group("Desktop Entry");
        enforce(_desktopEntry, new IniLikeException("no groups", 0));
    }
    
    /**
     * Constructs DesktopFile with "Desktop Entry" group and Version set to 1.0
     */
    @safe this() {
        super();
        _desktopEntry = super.addGroup("Desktop Entry");
        this["Version"] = "1.0";
    }
    
    @safe override IniLikeGroup addGroup(string groupName) {
        if (!_desktopEntry) {
            enforce(groupName == "Desktop Entry", "The first group must be Desktop Entry");
            _desktopEntry = super.addGroup(groupName);
            return _desktopEntry;
        } else {
            return super.addGroup(groupName);
        }
    }
    
    /**
     * Removes group by name. You can't remove "Desktop Entry" group with this function.
     */
    @safe override void removeGroup(string groupName) nothrow {
        if (groupName != "Desktop Entry") {
            super.removeGroup(groupName);
        }
    }
    
    /**
    * Tells whether the string is valid dekstop entry key.
    * Note: This does not include characters presented in locale names. Use $(B separateFromLocale) to get non-localized key to pass it to this function
    */
    @nogc @safe override bool isValidKey(string key) pure nothrow const 
    {
        /**
        * Tells whether the character is valid for entry key.
        * Note: This does not include characters presented in locale names.
        */
        @nogc @safe static bool isValidKeyChar(char c) pure nothrow {
            return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-';
        }
        
        if (key.empty) {
            return false;
        }
        for (size_t i = 0; i<key.length; ++i) {
            if (!isValidKeyChar(key[i])) {
                return false;
            }
        }
        return true;
    }
    
    /**
     * Type of desktop entry.
     * Returns: Type of desktop entry.
     */
    @nogc @safe Type type() const nothrow {
        string t = value("Type");
        if (t.length) {
            if (t == "Application") {
                return Type.Application;
            } else if (t == "Link") {
                return Type.Link;
            } else if (t == "Directory") {
                return Type.Directory;
            }
        }
        if (fileName().endsWith(".directory")) {
            return Type.Directory;
        }
        
        return Type.Unknown;
    }
    /// Sets "Type" field to type
    @safe Type type(Type t) {
        final switch(t) {
            case Type.Application:
                this["Type"] = "Application";
                break;
            case Type.Link:
                this["Type"] = "Link";
                break;
            case Type.Directory:
                this["Type"] = "Directory";
                break;
            case Type.Unknown:
                break;
        }
        return t;
    }
    
    /**
     * Specific name of the application, for example "Mozilla".
     * Returns: The value associated with "Name" key.
     */
    @nogc @safe string name() const nothrow {
        return value("Name");
    }
    ///ditto, but returns localized value.
    @safe string localizedName(string locale = null) const nothrow {
        return localizedValue("Name", locale);
    }
    
    /** 
     * Desktop file ID
     * Returns: desktop file id as described in $(LINK 2 http://standards.freedesktop.org/desktop-entry-spec/latest/ape.html, Desktop File ID) or empty string if file does not have an ID.
     */
    @trusted string id() const nothrow {
        try {
            string absolute = fileName.absolutePath;
            enum applications = "/applications/";
            auto index = absolute.indexOf(applications);
            if (index != -1) {
                return absolute[index + applications.length..$].replace("/", "-");
            }
        } catch(Exception e) {
            
        }
        return null;
    }
    
    /**
     * Generic name of the application, for example "Web Browser".
     * Returns: The value associated with "GenericName" key.
     */
    @nogc @safe string genericName() const nothrow {
        return value("GenericName");
    }
    ///ditto, but returns localized value.
    @safe string localizedGenericName(string locale = null) const nothrow {
        return localizedValue("GenericName", locale);
    }
    
    /**
     * Tooltip for the entry, for example "View sites on the Internet".
     * Returns: The value associated with "Comment" key.
     */
    @nogc @safe string comment() const nothrow {
        return value("Comment");
    }
    ///ditto, but returns localized value.
    @safe string localizedComment(string locale = null) const nothrow {
        return localizedValue("Comment", locale);
    }
    
    /** 
     * Returns: the value associated with "Exec" key.
     * Note: Don't use this to start the program. Consider using expandExecString or startApplication instead.
     * See_Also: expandExecString, startApplication
     */
    @nogc @safe string execString() const nothrow {
        return value("Exec");
    }
    
    /**
     * URL to access.
     * Returns: The value associated with "URL" key.
     */
    @nogc @safe string url() const nothrow {
        return value("URL");
    }
    
    /**
     * Value used to determine if the program is actually installed. If the path is not an absolute path, the file should be looked up in the $(B PATH) environment variable. If the file is not present or if it is not executable, the entry may be ignored (not be used in menus, for example).
     * Returns: The value associated with "TryExec" key.
     */
    @nogc @safe string tryExecString() const nothrow {
        return value("TryExec");
    }
    
    /**
     * Icon to display in file manager, menus, etc.
     * Returns: The value associated with "Icon" key. If not found it also tries "X-Window-Icon".
     * Note: This function returns Icon as it's defined in .desktop file. 
     *  It does not provide any lookup of actual icon file on the system if the name if not an absolute path.
     *  To find the path to icon file refer to $(LINK2 http://standards.freedesktop.org/icon-theme-spec/icon-theme-spec-latest.html, Icon Theme Specification) or consider using $(LINK2 https://github.com/MyLittleRobo/icontheme, icontheme library).
     */
    @nogc @safe string iconName() const nothrow {
        string iconPath = value("Icon");
        if (iconPath is null) {
            iconPath = value("X-Window-Icon");
        }
        return iconPath;
    }
    
    /**
     * NoDisplay means "this application exists, but don't display it in the menus".
     * Returns: The value associated with "NoDisplay" key converted to bool using isTrue.
     */
    @nogc @safe bool noDisplay() const nothrow {
        return isTrue(value("NoDisplay"));
    }
    
    /**
     * Hidden means the user deleted (at his level) something that was present (at an upper level, e.g. in the system dirs). 
     * It's strictly equivalent to the .desktop file not existing at all, as far as that user is concerned. 
     * Returns: The value associated with "Hidden" key converted to bool using isTrue.
     */
    @nogc @safe bool hidden() const nothrow {
        return isTrue(value("Hidden"));
    }
    
    /**
     * A boolean value specifying if D-Bus activation is supported for this application.
     * Returns: The value associated with "dbusActivable" key converted to bool using isTrue.
     */
    @nogc @safe bool dbusActivable() const nothrow {
        return isTrue(value("DBusActivatable"));
    }
    
    /**
     * Returns: The value associated with "startupNotify" key converted to bool using isTrue.
     */
    @nogc @safe bool startupNotify() const nothrow {
        return isTrue(value("StartupNotify"));
    }
    
    /**
     * The working directory to run the program in.
     * Returns: The value associated with "Path" key.
     */
    @nogc @safe string workingDirectory() const nothrow {
        return value("Path");
    }
    
    /**
     * Whether the program runs in a terminal window.
     * Returns: The value associated with "Terminal" key converted to bool using isTrue.
     */
    @nogc @safe bool terminal() const nothrow {
        return isTrue(value("Terminal"));
    }
    /// Sets "Terminal" field to true or false.
    @safe bool terminal(bool t) {
        this["Terminal"] = t ? "true" : "false";
        return t;
    }
    
    /**
     * Some keys can have multiple values, separated by semicolon. This function helps to parse such kind of strings into the range.
     * Returns: The range of multiple nonempty values.
     */
    @trusted static auto splitValues(string values) {
        return values.splitter(';').filter!(s => s.length != 0);
    }
    
    /**
     * Join range of multiple values into a string using semicolon as separator. Adds trailing semicolon.
     * If range is empty, then the empty string is returned.
     */
    @trusted static string joinValues(Range)(Range values) if (isInputRange!Range && isSomeString!(ElementType!Range)) {
        auto result = values.filter!( s => s.length != 0 ).joiner(";");
        if (result.empty) {
            return null;
        } else {
            return text(result) ~ ";";
        }
    }
    
    /**
     * Categories this program belongs to.
     * Returns: The range of multiple values associated with "Categories" key.
     */
    @safe auto categories() const {
        return splitValues(value("Categories"));
    }
    
    /**
     * Sets the list of values for the "Categories" list.
     */
    @safe void categories(Range)(Range values) if (isInputRange!Range && isSomeString!(ElementType!Range)) {
        this["Categories"] = joinValues(values);
    }
    
    /**
     * A list of strings which may be used in addition to other metadata to describe this entry.
     * Returns: The range of multiple values associated with "Keywords" key.
     */
    @safe auto keywords() const {
        return splitValues(value("Keywords"));
    }
    
    /**
     * Sets the list of values for the "Keywords" list.
     */
    @safe void keywords(Range)(Range values) if (isInputRange!Range && isSomeString!(ElementType!Range)) {
        this["Keywords"] = joinValues(values);
    }
    
    /**
     * The MIME type(s) supported by this application.
     * Returns: The range of multiple values associated with "MimeType" key.
     */
    @safe auto mimeTypes() const {
        return splitValues(value("MimeType"));
    }
    
    /**
     * Sets the list of values for the "MimeType" list.
     */
    @safe void mimeTypes(Range)(Range values) if (isInputRange!Range && isSomeString!(ElementType!Range)) {
        this["MimeType"] = joinValues(values);
    }
    
    /**
     * A list of strings identifying the desktop environments that should display a given desktop entry.
     * Returns: The range of multiple values associated with "OnlyShowIn" key.
     */
    @safe auto onlyShowIn() const {
        return splitValues(value("OnlyShowIn"));
    }
    
    /**
     * A list of strings identifying the desktop environments that should not display a given desktop entry.
     * Returns: The range of multiple values associated with "NotShowIn" key.
     */
    @safe auto notShowIn() const {
        return splitValues(value("NotShowIn"));
    }
    
    /**
     * Returns: instance of "Desktop Entry" group.
     * Note: Usually you don't need to call this function since you can rely on alias this.
     */
    @nogc @safe inout(IniLikeGroup) desktopEntry() nothrow inout {
        return _desktopEntry;
    }
    
    
    /**
     * This alias allows to call functions related to "Desktop Entry" group without need to call desktopEntry explicitly.
     */
    alias desktopEntry this;
    
    /**
     * Expands Exec string into the array of command line arguments to use to start the program.
     */
    @safe string[] expandExecString(in string[] urls = null) const
    {   
        string[] toReturn;
        auto execStr = execString().unescapeExec(); //add unquoting
        
        foreach(token; execStr.split) {
            if (token == "%f") {
                if (urls.length) {
                    toReturn ~= urls.front;
                }
            } else if (token == "%F") {
                toReturn ~= urls;
            } else if (token == "%u") {
                if (urls.length) {
                    toReturn ~= urls.front;
                }
            } else if (token == "%U") {
                toReturn ~= urls;
            } else if (token == "%i") {
                string iconStr = iconName();
                if (iconStr.length) {
                    toReturn ~= "--icon";
                    toReturn ~= iconStr;
                }
            } else if (token == "%c") {
                toReturn ~= localizedValue("Name");
            } else if (token == "%k") {
                toReturn ~= fileName();
            } else if (token == "%d" || token == "%D" || token == "%n" || token == "%N" || token == "%m" || token == "%v") {
                continue;
            } else {
                toReturn ~= token;
            }
        }
        
        return toReturn;
    }
    
    /**
     * Starts the application associated with this .desktop file using urls as command line params.
     * If the program should be run in terminal it tries to find system defined terminal emulator to run in.
     * Params:
     *  urls = urls application will start with.
     *  preferableTerminal = preferable terminal emulator. If this string is empty terminal is determined via determineTerminalEmulator.
     * Note:
     *  This function does not check if the type of desktop file is Application. It relies only on "Exec" value.
     * Returns:
     *  Pid of started process.
     * Throws:
     *  ProcessException on failure to start the process.
     *  Exception if expanded exec string is empty.
     * See_Also: determineTerminalEmulator, start
     */
    @trusted Pid startApplication(in string[] urls = null, string preferableTerminal = null) const
    {
        auto args = expandExecString(urls);
        enforce(args.length, "No command line params to run the program. Is Exec missing?");
        
        if (terminal()) {
            string term = preferableTerminal.length ? preferableTerminal : determineTerminalEmulator();            
            args = [term, "-e"] ~ args;
        }
        
        File newStdin;
        version(Posix) {
            newStdin = File("/dev/null", "rb");
        } else {
            newStdin = std.stdio.stdin;
        }
        
        static if( __VERSION__ < 2066 ) {
            return spawnProcess(args, newStdin, std.stdio.stdout, std.stdio.stderr, null, Config.none);
        } else {
            return spawnProcess(args, newStdin, std.stdio.stdout, std.stdio.stderr, null, Config.none, workingDirectory());
        }
    }
    
    ///ditto, but uses the only url.
    @trusted Pid startApplication(string url, string preferableTerminal = null) const
    {
        return startApplication([url], preferableTerminal);
    }
    
    /**
     * Opens url defined in .desktop file using $(LINK2 http://portland.freedesktop.org/xdg-utils-1.0/xdg-open.html, xdg-open).
     * Note:
     *  This function does not check if the type of desktop file is Link. It relies only on "URL" value.
     * Returns:
     *  Pid of started process.
     * Throws:
     *  ProcessException on failure to start the process.
     *  Exception if desktop file does not define URL.
     * See_Also: start
     */
    @trusted Pid startLink() const {
        string myurl = url();
        enforce(myurl.length, "No URL to open");
        return spawnProcess(["xdg-open", myurl], null, Config.none);
    }
    
    /**
     * Starts application or open link depending on desktop entry type.
     * Returns: 
     *  Pid of started process.
     * Throws:
     *  ProcessException on failure to start the process.
     *  Exception if type is unknown or directory.
     * See_Also: startApplication, startLink
     */
    @trusted Pid start() const
    {
        final switch(type()) {
            case DesktopFile.Type.Application:
                return startApplication();
            case DesktopFile.Type.Link:
                return startLink();
            case DesktopFile.Type.Directory:
                throw new Exception("Don't know how to start directory");
            case DesktopFile.Type.Unknown:
                throw new Exception("Unknown desktop entry type");
        }
    }
    
private:
    IniLikeGroup _desktopEntry;
}

unittest 
{
    //Test split/join values
    
    assert(equal(DesktopFile.splitValues("Application;Utility;FileManager;"), ["Application", "Utility", "FileManager"]));
    assert(DesktopFile.splitValues(";").empty);
    assert(equal(DesktopFile.joinValues(["Application", "Utility", "FileManager"]), "Application;Utility;FileManager;"));
    assert(DesktopFile.joinValues([""]).empty);
    
    //Test DesktopFile
    string desktopFileContents = 
`[Desktop Entry]
# Comment
Name=Double Commander
GenericName=File manager
GenericName[ru]=Файловый менеджер
Comment=Double Commander is a cross platform open source file manager with two panels side by side.
Terminal=false
Icon=doublecmd
Exec=doublecmd
Type=Application
Categories=Application;Utility;FileManager;
Keywords=folder;manager;explore;disk;filesystem;orthodox;copy;queue;queuing;operations;`;
    
    auto df = new DesktopFile(iniLikeStringReader(desktopFileContents), DesktopFile.ReadOptions.preserveComments);
    assert(df.name() == "Double Commander");
    assert(df.genericName() == "File manager");
    assert(df.localizedGenericName("ru_RU") == "Файловый менеджер");
    assert(!df.terminal());
    assert(df.type() == DesktopFile.Type.Application);
    assert(equal(df.categories(), ["Application", "Utility", "FileManager"]));
    
    assert(df.saveToString() == desktopFileContents);
    
    assert(df.contains("Icon"));
    df.removeEntry("Icon");
    assert(!df.contains("Icon"));
    df["Icon"] = "files";
    assert(df.contains("Icon"));
    
    df = new DesktopFile();
    assert(df.desktopEntry());
    assert(df.value("Version") == "1.0");
    assert(df.categories().empty);
    assert(df.type() == DesktopFile.Type.Unknown);
    
    df.terminal = true;
    df.type = DesktopFile.Type.Application;
    df.categories = ["Development", "Compilers"];
    
    assert(df.terminal() == true);
    assert(df.type() == DesktopFile.Type.Application);
    assert(equal(df.categories(), ["Development", "Compilers"]));
    
    string contents = 
`[Not desktop entry]
Key=Value`;
    assertThrown(new DesktopFile(iniLikeStringReader(contents)));
}
