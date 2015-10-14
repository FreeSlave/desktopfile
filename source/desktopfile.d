/**
 * Reading, writing and executing .desktop file
 * Authors: 
 *  $(LINK2 https://github.com/MyLittleRobo, Roman Chistokhodov).
 * Copyright:
 *  Roman Chistokhodov, 2015
 * License: 
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * See_Also: 
 *  $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/index.html, Desktop Entry Specification).
 */

module desktopfile;

import standardpaths;

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
    import std.uni;
    
    static if( __VERSION__ < 2066 ) enum nogc = 1;
}

/**
 * Applications paths based on data paths. 
 * This function is available on all platforms, but requires dataPaths argument (e.g. C:\ProgramData\KDE\share on Windows)
 * Returns: Array of paths, based on dataPaths with "applications" directory appended.
 */
@trusted string[] applicationsPaths(in string[] dataPaths) nothrow {
    return dataPaths.map!(p => buildPath(p, "applications")).array;
}

///
unittest
{
    assert(equal(applicationsPaths(["share", buildPath("local", "share")]), [buildPath("share", "applications"), buildPath("local", "share", "applications")]));
}

version(OSX) {}
else version(Posix)
{
    /**
     * ditto, but returns paths based on known data paths. It's practically the same as standardPaths(StandardPath.applications).
     * This function is defined only on freedesktop systems to avoid confusion with other systems that have data paths not compatible with Desktop Entry Spec.
     */
    @trusted string[] applicationsPaths() nothrow {
        return standardPaths(StandardPath.applications);
    }
    
    /**
     * Path where .desktop files can be stored without requiring of root privileges.
     * It's practically the same as writablePath(StandardPath.applications).
     * This function is defined only on freedesktop systems to avoid confusion with other systems that have data paths not compatible with Desktop Entry Spec.
     * Note: it does not check if returned path exists and appears to be directory.
     */
    @trusted string writableApplicationsPath() nothrow {
        return writablePath(StandardPath.applications);
    }
}


@trusted string unescapeExecArgument(string arg) nothrow pure
{
    static immutable Tuple!(char, char)[] pairs = [
       tuple('s', ' '),
       tuple('n', '\n'),
       tuple('r', '\r'),
       tuple('t', '\t'),
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
       tuple('`', '`'),
    ];
    return doUnescape(arg, pairs);
}

private @trusted string unescapeQuotedArgument(string value) nothrow pure
{
    static immutable Tuple!(char, char)[] pairs = [
       tuple('`', '`'),
       tuple('$', '$'),
       tuple('"', '"'),
       tuple('\\', '\\')
    ];
    return doUnescape(value, pairs);
}

@trusted string[] unquoteExecString(string value) pure
{
    string[] result;
    size_t i;
    
    while(i < value.length) {
        if (isWhite(value[i])) {
            i++;
        } else if (value[i] == '"') {
            i++;
            size_t start = i;
            bool inQuotes = true;
            bool wasSlash;
            
            while(i < value.length) {
                if (value[i] == '\\' && value.length > i+1 && value[i+1] == '\\') {
                    i+=2;
                    wasSlash = true;
                    continue;
                }
                
                if (value[i] == '"' && (value[i-1] != '\\' || (value[i-1] == '\\' && wasSlash) )) {
                    inQuotes = false;
                    break;
                }
                wasSlash = false;
                i++;
            }
            if (inQuotes) {
                throw new Exception("Missing end delimeter");
            }
            result ~= value[start..i];
            i++;
            
        } else {
            size_t start = i;
            i++;
            while(i < value.length) {
                if (isWhite(value[i])) {
                    break;
                }
                i++;
            }
            result ~= value[start..i];
        }
    }
    
    return result.map!(s => s.unescapeQuotedArgument).array;
}

///
unittest 
{
    assert(unquoteExecString(``) == []);
    assert(unquoteExecString(`   `) == []);
    assert(unquoteExecString(`"" "  "`) == [``, `  `]);
    
    assert(unquoteExecString(`cmd arg1  arg2   arg3   `) == [`cmd`, `arg1`, `arg2`, `arg3`]);
    assert(unquoteExecString(`"cmd" arg1 arg2  `) == [`cmd`, `arg1`, `arg2`]);
    
    assert(unquoteExecString(`"quoted cmd"   arg1  "quoted arg"  `) == [`quoted cmd`, `arg1`, `quoted arg`]);
    assert(unquoteExecString(`"quoted \"cmd\"" arg1 "quoted \"arg\""`) == [`quoted "cmd"`, `arg1`, `quoted "arg"`]);
    
    assert(unquoteExecString(`"\\\$" `) == [`\$`]);
    assert(unquoteExecString(`"\\$" `) == [`\$`]);
    assert(unquoteExecString(`"\$" `) == [`$`]);
    assert(unquoteExecString(`"$"`) == [`$`]);
    
    assert(unquoteExecString(`"\\" `) == [`\`]);
    assert(unquoteExecString(`"\\\\" `) == [`\\`]);
}

/**
 * Detect command which will run program in terminal emulator.
 * On Freedesktop it looks for x-terminal-emulator first. If found ["/path/to/x-terminal-emulator", "-e"] is returned.
 * Otherwise it looks for xdg-terminal. If found ["/path/to/xdg-terminal"] is returned.
 * If all guesses failed, it uses ["xterm", "-e"] as fallback.
 * Note: This function always returns empty array on non-freedesktop systems.
 */
string[] getTerminalCommand() nothrow @trusted 
{
    version(OSX) {
        return null;
    } else version(Posix) {
        string term = findExecutable("x-terminal-emulator");
        if (!term.empty) {
            return [term, "-e"];
        }
        term = findExecutable("xdg-terminal");
        if (!term.empty) {
            return [term];
        }
        return ["xterm", "-e"];
    } else {
        return null;
    }
}

private @trusted File getNullStdin()
{
    version(Posix) {
        return File("/dev/null", "rb");
    } else {
        return std.stdio.stdin;
    }
}

private @trusted File getNullStdout()
{
    version(Posix) {
        return File("/dev/null", "wb");
    } else {
        return std.stdio.stdout;
    }
}

private @trusted File getNullStderr()
{
    version(Posix) {
        return File("/dev/null", "wb");
    } else {
        return std.stdio.stderr;
    }
}

private @trusted Pid execProcess(string[] args, string workingDirectory = null)
{
    static if( __VERSION__ < 2066 ) {
        return spawnProcess(args, getNullStdin(), getNullStdout(), getNullStderr(), null, Config.none);
    } else {
        return spawnProcess(args, getNullStdin(), getNullStdout(), getNullStderr(), null, Config.none, workingDirectory);
    }
}

/**
 * Adapter of IniLikeGroup for easy access to desktop action.
 */
struct DesktopAction
{
    @nogc @safe this(const(IniLikeGroup) group) nothrow {
        _group = group;
    }
    
    /**
     * Label that will be shown to the user.
     * Returns: The value associated with "Name" key.
     * Note: Don't confuse this with name of section. To access name of section use group().name.
     */
    @nogc @safe string name() const nothrow {
        return value("Name");
    }
    
    /**
     * Label that will be shown to the user in given locale.
     * Returns: The value associated with "Name" key and given locale.
     */
    @safe string localizedName(string locale) const nothrow {
        return localizedValue("Name", locale);
    }
    
    /**
     * Icon name of action.
     * Returns: The value associated with "Icon" key.
     */
    @nogc @safe string iconName() const nothrow {
        return value("Icon");
    }
    
    /**
     * Returns: Localized icon name
     * See_Also: iconName
     */
    @safe string localizedIconName(string locale) const nothrow {
        return localizedValue("Icon", locale);
    }
    
    /**
     * Returns: The value associated with "Exec" key and given locale.
     */
    @nogc @safe string execString() const nothrow {
        return value("Exec");
    }
    
    /**
     * Start this action.
     * Returns:
     *  Pid of started process.
     * Throws:
     *  ProcessException on failure to start the process.
     *  Exception if expanded exec string is empty.
     * See_Also: execString
     */
    @safe Pid start() const {
        auto args = execString().unquoteExecString().map!(unescapeExecArgument).array;
        enforce(args.length, "No command line params to run the program. Is Exec missing?");
        return execProcess(args);
    }
    
    /**
     * Underlying IniLikeGroup instance. 
     * Returns: IniLikeGroup this object was constrcucted from.
     */
    @nogc @safe const(IniLikeGroup) group() const nothrow {
        return _group;
    }
    
    /**
     * This alias allows to call functions of underlying IniLikeGroup instance.
     */
    alias group this;
private:
    const(IniLikeGroup) _group;
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
    
    ///
    unittest
    {
        auto df = new DesktopFile();
        assert(df.desktopEntry());
        assert(df.value("Version") == "1.0");
        assert(df.categories().empty);
        assert(df.type() == DesktopFile.Type.Unknown);
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
    
    ///
    unittest
    {
        auto df = new DesktopFile();
        df.addGroup("Action");
        assert(df.group("Action") !is null);
        df.removeGroup("Action");
        assert(df.group("Action") is null);
        df.removeGroup("Desktop Entry");
        assert(df.desktopEntry() !is null);
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
    
    ///
    unittest
    {
        auto desktopFile = new DesktopFile;
        assert(desktopFile.isValidKey("Generic-Name"));
        assert(!desktopFile.isValidKey("Name$"));
        assert(!desktopFile.isValidKey(""));
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
    
    ///
    unittest
    {
        string contents = "[Desktop Entry]\nType=Application";
        auto desktopFile = new DesktopFile(iniLikeStringReader(contents));
        assert(desktopFile.type == DesktopFile.Type.Application);
        
        desktopFile.desktopEntry["Type"] = "Link";
        assert(desktopFile.type == DesktopFile.Type.Link);
        
        desktopFile.desktopEntry["Type"] = "Directory";
        assert(desktopFile.type == DesktopFile.Type.Directory);
        
        desktopFile = new DesktopFile(iniLikeStringReader("[Desktop Entry]"), ReadOptions.noOptions, ".directory");
        assert(desktopFile.type == DesktopFile.Type.Directory);
    }
    
    /**
     * Sets "Type" field to type
     * Note: Setting the Unknown type removes type field.
     */
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
                this.removeEntry("Type");
                break;
        }
        return t;
    }
    
    ///
    unittest
    {
        auto desktopFile = new DesktopFile();
        desktopFile.type = DesktopFile.Type.Application;
        assert(desktopFile.desktopEntry["Type"] == "Application");
        desktopFile.type = DesktopFile.Type.Link;
        assert(desktopFile.desktopEntry["Type"] == "Link");
        desktopFile.type = DesktopFile.Type.Directory;
        assert(desktopFile.desktopEntry["Type"] == "Directory");
        
        desktopFile.type = DesktopFile.Type.Unknown;
        assert(desktopFile.desktopEntry.value("Type").empty);
    }
    
    /**
     * Specific name of the application, for example "Mozilla".
     * Returns: The value associated with "Name" key.
     * See_Also: localizedName
     */
    @nogc @safe string name() const nothrow {
        return value("Name");
    }
    /**
     * Returns: Localized name.
     * See_Also: name
     */
    @safe string localizedName(string locale) const nothrow {
        return localizedValue("Name", locale);
    }
    
    version(OSX) {} version(Posix) {
        /** 
        * See $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/ape.html, Desktop File ID)
        * Returns: desktop file ID or empty string if file does not have an ID.
        * Note: This function retrieves applications paths each time it's called. To avoid this issue use overload with argument.
        */
        @trusted string id() const nothrow {
            return id(applicationsPaths());
        }
    }
    
    /**
     * See $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/ape.html, Desktop File ID)
     * Returns: desktop file ID or empty string if file does not have an ID.
     */
    @trusted string id(Range)(Range appPaths) const nothrow if (isInputRange!Range && is(ElementType!Range : string)) 
    {
        try {
            string absolute = fileName.absolutePath;
            foreach (path; appPaths) {
                auto pathSplit = pathSplitter(path);
                auto fileSplit = pathSplitter(absolute);
                
                while (!pathSplit.empty && !fileSplit.empty && pathSplit.front == fileSplit.front) {
                    pathSplit.popFront();
                    fileSplit.popFront();
                }
                
                if (pathSplit.empty) {
                    return to!string(fileSplit.join("-"));
                }
            }
        } catch(Exception e) {
            
        }
        return null;
    }
    
    ///
    unittest 
    {
        string contents = 
`[Desktop Entry]
Name=Program
Type=Application`;
        
        auto appPaths = ["/usr/share/applications", "/usr/local/share/applications"];
        auto df = new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.noOptions, "/usr/share/applications/de/example.desktop");
        assert(df.id(appPaths) == "de-example.desktop");
        
        df = new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.noOptions, "/usr/local/share/applications/example.desktop");
        assert(df.id(appPaths) == "example.desktop");
        
        df = new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.noOptions, "/etc/desktop/example.desktop");
        assert(df.id(appPaths).empty);
    }
    
    /**
     * Generic name of the application, for example "Web Browser".
     * Returns: The value associated with "GenericName" key.
     * See_Also: localizedGenericName
     */
    @nogc @safe string genericName() const nothrow {
        return value("GenericName");
    }
    /**
     * Returns: Localized generic name
     * See_Also: genericName
     */
    @safe string localizedGenericName(string locale) const nothrow {
        return localizedValue("GenericName", locale);
    }
    
    /**
     * Tooltip for the entry, for example "View sites on the Internet".
     * Returns: The value associated with "Comment" key.
     * See_Also: localizedComment
     */
    @nogc @safe string comment() const nothrow {
        return value("Comment");
    }
    /**
     * Returns: Localized comment
     * See_Also: comment
     */
    @safe string localizedComment(string locale) const nothrow {
        return localizedValue("Comment", locale);
    }
    
    /** 
     * Returns: the value associated with "Exec" key.
     * Note: To get arguments from exec string use expandExecString.
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
    
    ///
    unittest
    {
        auto df = new DesktopFile(iniLikeStringReader("[Desktop Entry]\nType=Link\nURL=https://github.com/"));
        assert(df.url() == "https://github.com/");
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
     * Returns: The value associated with "Icon" key.
     * Note: This function returns Icon as it's defined in .desktop file. 
     *  It does not provide any lookup of actual icon file on the system if the name if not an absolute path.
     *  To find the path to icon file refer to $(LINK2 http://standards.freedesktop.org/icon-theme-spec/icon-theme-spec-latest.html, Icon Theme Specification) or consider using $(LINK2 https://github.com/MyLittleRobo/icontheme, icontheme library).
     */
    @nogc @safe string iconName() const nothrow {
        return value("Icon");
    }
    
    /**
     * Returns: Localized icon name
     * See_Also: iconName
     */
    @safe string localizedIconName(string locale) const nothrow {
        return localizedValue("Icon", locale);
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
    
    private static struct SplitValues
    {
        @trusted this(string value) {
            _value = value;
            next();
        }
        @trusted string front() {
            return _current;
        }
        @trusted void popFront() {
            next();
        }
        @trusted bool empty() {
            return _value.empty && _current.empty;
        }
        @trusted @property auto save() {
            return this;
        }
    private:
        void next() {
            size_t i=0;
            for (; i<_value.length && ( (_value[i] != ';') || (i && _value[i-1] == '\\' && _value[i] == ';')); ++i) {
                //pass
            }
            _current = _value[0..i].replace("\\;", ";");
            _value = i == _value.length ? _value[_value.length..$] : _value[i+1..$];
        }
        string _value;
        string _current;
    }

    static assert(isForwardRange!SplitValues);
    
    /**
     * Some keys can have multiple values, separated by semicolon. This function helps to parse such kind of strings into the range.
     * Returns: The range of multiple nonempty values.
     * Note: Returned range unescapes ';' character automatically.
     */
    @trusted static auto splitValues(string values) {
        return SplitValues(values).filter!(s => !s.empty);
    }
    
    ///
    unittest 
    {
        assert(DesktopFile.splitValues("").empty);
        assert(DesktopFile.splitValues(";").empty);
        assert(DesktopFile.splitValues(";;;").empty);
        assert(equal(DesktopFile.splitValues("Application;Utility;FileManager;"), ["Application", "Utility", "FileManager"]));
        assert(equal(DesktopFile.splitValues("I\\;Me;\\;You\\;We\\;"), ["I;Me", ";You;We;"]));
    }
    
    /**
     * Join range of multiple values into a string using semicolon as separator. Adds trailing semicolon.
     * Returns: Values of range joined into one string with ';' after each value or empty string if range is empty.
     * Note: If some value of range contains ';' character it's automatically escaped.
     */
    @trusted static string joinValues(Range)(Range values) if (isInputRange!Range && isSomeString!(ElementType!Range)) {
        auto result = values.filter!( s => !s.empty ).map!( s => s.replace(";", "\\;")).joiner(";");
        if (result.empty) {
            return null;
        } else {
            return text(result) ~ ";";
        }
    }
    
    ///
    unittest
    {
        assert(DesktopFile.joinValues([""]).empty);
        assert(equal(DesktopFile.joinValues(["Application", "Utility", "FileManager"]), "Application;Utility;FileManager;"));
        assert(equal(DesktopFile.joinValues(["I;Me", ";You;We;"]), "I\\;Me;\\;You\\;We\\;;"));
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
     * Actions supported by application.
     * Returns: Range of multiple values associated with "Actions" key.
     * Note: This only depends on "Actions" value, not on actually presented sections in desktop file.
     * See_Also: byAction, action
     */
    @safe auto actions() const {
        return splitValues(value("Actions"));
    }
    
    /**
     * Sets the list of values for "Actions" list.
     */
    @safe void actions(Range)(Range values) if (isInputRange!Range && isSomeString!(ElementType!Range)) {
        this["Actions"] = joinValues(values);
    }
    
    /**
     * Get $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s10.html, additional application action) by name.
     * Returns: DesktopAction with given action name or DesktopAction with null group if not found or found section does not have a name.
     * See_Also: actions, byAction
     */
    @safe const(DesktopAction) action(string actionName) const {
        if (actions().canFind(actionName)) {
            auto desktopAction = DesktopAction(group("Desktop Action "~actionName));
            if (desktopAction.group() !is null && desktopAction.name().length != 0) {
                return desktopAction;
            }
        }
        
        return DesktopAction(null);
    }
    
    /**
     * Iterating over existing actions.
     * Returns: Range of DesktopAction.
     * See_Also: actions, action
     */
    @safe auto byAction() const {
        return actions().map!(actionName => DesktopAction(group("Desktop Action "~actionName))).filter!(delegate(desktopAction) {
            return desktopAction.group !is null && desktopAction.name.length != 0;
        });
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
     * Expand "Exec" value into the array of command line arguments to use to start the program.
     * See_Also: execString, unquoteExecString, unescapeExecArgument, startApplication
     */
    @safe string[] expandExecString(in string[] urls = null, string locale = null) const
    {   
        string[] toReturn;
        auto execArgs = execString().unquoteExecString().map!(unescapeExecArgument).array;
        
        foreach(token; execArgs) {
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
                auto iconStr = localizedIconName(locale);
                if (iconStr.length) {
                    toReturn ~= "--icon";
                    toReturn ~= iconStr;
                }
            } else if (token == "%c") {
                toReturn ~= localizedName(locale);
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
    
    ///
    unittest 
    {
        string contents = 
`[Desktop Entry]
Name=Program
Name[ru]=Программа
Exec="quoted program" %i -w %c -f %k %U %D %u %f %F
Icon=folder`;
        auto df = new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.noOptions, "/example.desktop");
        assert(df.expandExecString(["one", "two"], "ru") == 
        ["quoted program", "--icon", "folder", "-w", "Программа", "-f", "/example.desktop", "one", "two", "one", "one", "one", "two"]);
    }
    
    /**
     * Starts the application associated with this .desktop file using urls as command line params.
     * If the program should be run in terminal it tries to find system defined terminal emulator to run in.
     * Params:
     *  urls = urls application will start with.
     *  locale = locale that may be needed to be placed in urls if Exec value has %c code.
     *  terminalCommand = preferable terminal emulator command. If not set then terminal is determined via getTerminalCommand.
     * Note:
     *  This function does not check if the type of desktop file is Application. It relies only on "Exec" value.
     * Returns:
     *  Pid of started process.
     * Throws:
     *  ProcessException on failure to start the process.
     *  Exception if expanded exec string is empty.
     * See_Also: determineTerminalEmulator, start, expandExecString
     */
    @trusted Pid startApplication(in string[] urls = null, string locale = null, lazy string[] terminalCommand = getTerminalCommand) const
    {
        auto args = expandExecString(urls, locale);
        enforce(args.length, "No command line params to run the program. Is Exec missing?");
        
        if (terminal()) {
            auto termCmd = terminalCommand();
            args = termCmd ~ args;
        }
        
        return execProcess(args, workingDirectory());
    }
    
    ///
    unittest
    {
        auto df = new DesktopFile();
        assertThrown(df.startApplication(string[].init));
    }
    
    ///ditto, but uses the only url.
    @trusted Pid startApplication(string url, string locale = null, lazy string[] preferableTerminal = getTerminalCommand) const {
        return startApplication([url], locale, preferableTerminal);
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
    
    ///
    unittest
    {
        auto df = new DesktopFile();
        assertThrown(df.startLink());
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

///
unittest 
{
    //Test DesktopFile
    string desktopFileContents = 
`[Desktop Entry]
# Comment
Name=Double Commander
Name[ru]=Двухпанельный коммандер
GenericName=File manager
GenericName[ru]=Файловый менеджер
Comment=Double Commander is a cross platform open source file manager with two panels side by side.
Comment[ru]=Double Commander - кроссплатформенный файловый менеджер.
Terminal=false
Icon=doublecmd
Exec=doublecmd %f
TryExec=doublecmd
Type=Application
Categories=Application;Utility;FileManager;
Keywords=folder;manager;disk;filesystem;operations;
Actions=OpenDirectory;NotPresented;Settings;NoName;
MimeType=inode/directory;application/x-directory;
NoDisplay=false
Hidden=false
StartupNotify=true
DBusActivatable=true
Path=/opt/doublecmd
OnlyShowIn=GNOME;XFCE;LXDE;
NotShowIn=KDE;

[Desktop Action OpenDirectory]
Name=Open directory
Name[ru]=Открыть папку
Icon=open
Exec=doublecmd %u

[NoName]
Icon=folder

[Desktop Action Settings]
Name=Settings
Name[ru]=Настройки
Icon=edit
Exec=doublecmd settings

[Desktop Action Notspecified]
Name=Notspecified Action`;
    
    auto df = new DesktopFile(iniLikeStringReader(desktopFileContents), DesktopFile.ReadOptions.preserveComments);
    assert(df.name() == "Double Commander");
    assert(df.localizedName("ru_RU") == "Двухпанельный коммандер");
    assert(df.genericName() == "File manager");
    assert(df.localizedGenericName("ru_RU") == "Файловый менеджер");
    assert(df.comment() == "Double Commander is a cross platform open source file manager with two panels side by side.");
    assert(df.localizedComment("ru_RU") == "Double Commander - кроссплатформенный файловый менеджер.");
    assert(df.tryExecString() == "doublecmd");
    assert(!df.terminal());
    assert(!df.noDisplay());
    assert(!df.hidden());
    assert(df.startupNotify());
    assert(df.dbusActivable());
    assert(df.workingDirectory() == "/opt/doublecmd");
    assert(df.type() == DesktopFile.Type.Application);
    assert(equal(df.keywords(), ["folder", "manager", "disk", "filesystem", "operations"]));
    assert(equal(df.categories(), ["Application", "Utility", "FileManager"]));
    assert(equal(df.actions(), ["OpenDirectory", "NotPresented", "Settings", "NoName"]));
    assert(equal(df.mimeTypes(), ["inode/directory", "application/x-directory"]));
    assert(equal(df.onlyShowIn(), ["GNOME", "XFCE", "LXDE"]));
    assert(equal(df.notShowIn(), ["KDE"]));
    
    assert(equal(df.byAction().map!(desktopAction => 
    tuple(desktopAction.name(), desktopAction.localizedName("ru"), desktopAction.iconName(), desktopAction.execString())), 
                 [tuple("Open directory", "Открыть папку", "open", "doublecmd %u"), tuple("Settings", "Настройки", "edit", "doublecmd settings")]));
    
    assert(df.action("NotPresented").group() is null);
    assert(df.action("Notspecified").group() is null);
    assert(df.action("NoName").group() is null);
    assert(df.action("Settings").group() !is null);
    
    assert(df.saveToString() == desktopFileContents);
    
    assert(df.contains("Icon"));
    df.removeEntry("Icon");
    assert(!df.contains("Icon"));
    df["Icon"] = "files";
    assert(df.contains("Icon"));
    
    df = new DesktopFile();
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
