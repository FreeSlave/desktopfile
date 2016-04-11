/**
 * Class representation of desktop file.
 * Authors: 
 *  $(LINK2 https://github.com/MyLittleRobo, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2015-2016
 * License: 
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * See_Also: 
 *  $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/index.html, Desktop Entry Specification)
 */

module desktopfile.file;

public import inilike.file;
public import desktopfile.utils;

/**
 * Subclass of IniLikeGroup for easy access to desktop action.
 */
final class DesktopAction : IniLikeGroup
{
protected:
    @trusted override void validateKeyValue(string key, string value) const {
        enforce(isValidKey(key), "key is invalid");
    }
public:
    package @nogc @safe this(string groupName) nothrow {
        super(groupName);
    }
    
    /**
     * Label that will be shown to the user.
     * Returns: The value associated with "Name" key.
     */
    @nogc @safe string displayName() const nothrow {
        return value("Name");
    }
    
    /**
     * Label that will be shown to the user in given locale.
     * Returns: The value associated with "Name" key and given locale.
     */
    @safe string localizedDisplayName(string locale) const nothrow {
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
     *  DesktopExecException if exec string is invalid.
     * See_Also: execString
     */
    @safe Pid start(string locale = null) const {
        return execProcess(expandExecString(execString, null, localizedIconName(locale), localizedDisplayName(locale)));
    }
}

/**
 * Subclass of IniLikeGroup for easy accessing of Desktop Entry properties.
 */
final class DesktopEntry : IniLikeGroup
{
    ///Desktop entry type
    enum Type
    {
        Unknown, ///Desktop entry is unknown type
        Application, ///Desktop describes application
        Link, ///Desktop describes URL
        Directory ///Desktop entry describes directory settings
    }
    
    protected @nogc @safe this() nothrow {
        super("Desktop Entry");
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
        return Type.Unknown;
    }
    
    ///
    unittest
    {
        string contents = "[Desktop Entry]\nType=Application";
        auto desktopFile = new DesktopFile(iniLikeStringReader(contents));
        assert(desktopFile.type == Type.Application);
        
        desktopFile.desktopEntry["Type"] = "Link";
        assert(desktopFile.type == Type.Link);
        
        desktopFile.desktopEntry["Type"] = "Directory";
        assert(desktopFile.type == Type.Directory);
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
        desktopFile.type = Type.Application;
        assert(desktopFile.desktopEntry.value("Type") == "Application");
        desktopFile.type = Type.Link;
        assert(desktopFile.desktopEntry.value("Type") == "Link");
        desktopFile.type = Type.Directory;
        assert(desktopFile.desktopEntry.value("Type") == "Directory");
        
        desktopFile.type = Type.Unknown;
        assert(desktopFile.desktopEntry.value("Type").empty);
    }
    
    /**
     * Specific name of the application, for example "Mozilla".
     * Returns: The value associated with "Name" key.
     * See_Also: localizedName
     */
    @nogc @safe string displayName() const nothrow {
        return value("Name");
    }
    
    ///setter
    @safe string displayName(string name) {
        this["Name"] = name;
        return name;
    }
    
    /**
     * Returns: Localized name.
     * See_Also: name
     */
    @safe string localizedDisplayName(string locale) const nothrow {
        return localizedValue("Name", locale);
    }
    
    /**
     * Generic name of the application, for example "Web Browser".
     * Returns: The value associated with "GenericName" key.
     * See_Also: localizedGenericName
     */
    @nogc @safe string genericName() const nothrow {
        return value("GenericName");
    }
    
    ///setter
    @safe string genericName(string name) {
        this["GenericName"] = name;
        return name;
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
    
    ///setter
    @safe string comment(string commentary) {
        this["Comment"] = commentary;
        return commentary;
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
     * See_Also: expandExecString, startApplication, tryExecString
     */
    @nogc @safe string execString() const nothrow {
        return value("Exec");
    }
    
    /**
     * Setter for Exec value.
     * Params:
     *  exec = String to set as "Exec" value. Should be properly escaped and quoted.
     * See_Also: desktopfile.utils.ExecBuilder.
     */
    @safe string execString(string exec) {
        this["Exec"] = exec;
        return exec;
    }
    
    /**
     * URL to access.
     * Returns: The value associated with "URL" key.
     */
    @nogc @safe string url() const nothrow {
        return value("URL");
    }
    
    ///setter
    @safe string url(string link) {
        this["URL"] = link;
        return link;
    }
    
    ///
    unittest
    {
        auto df = new DesktopFile(iniLikeStringReader("[Desktop Entry]\nType=Link\nURL=https://github.com/"));
        assert(df.url() == "https://github.com/");
    }
    
    /**
     * Value used to determine if the program is actually installed. If the path is not an absolute path, the file should be looked up in the $(B PATH) environment variable. If the file is not present or if it is not executable, the entry may be ignored (not be used in menus, for example).
     * Returns: The value associated with "TryExec" key, possibly with quotes removed if path is quoted.
     * See_Also: execString
     */
    @nogc @safe string tryExecString() const nothrow {
        return value("TryExec");
    }
    
    /**
     * Set TryExec value.
     * Throws:
     *  Exception if tryExec is not abolute path nor base name.
     */
    @safe string tryExecString(string tryExec) {
        enforce(tryExec.isAbsolute || tryExec.baseName == tryExec, "TryExec must be absolute path or base name");
        this["TryExec"] = tryExec;
        return tryExec;
    }
    
    ///
    unittest
    {
        auto df = new DesktopFile();
        assertNotThrown(df.tryExecString = "base");
        version(Posix) {
            assertNotThrown(df.tryExecString = "/absolute/path");
        }
        assertThrown(df.tryExecString = "not/absolute");
        assertThrown(df.tryExecString = "./relative");
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
     * Set Icon value.
     * Throws:
     *  Exception if icon is not abolute path nor base name.
     */
    @safe string iconName(string icon) {
        enforce(icon.isAbsolute || icon.baseName == icon, "Icon must be absolute path or base name");
        this["Icon"] = icon;
        return icon;
    }
    
    ///
    unittest
    {
        auto df = new DesktopFile();
        assertNotThrown(df.iconName = "base");
        version(Posix) {
            assertNotThrown(df.iconName = "/absolute/path");
        }
        assertThrown(df.iconName = "not/absolute");
        assertThrown(df.iconName = "./relative");
    }
    
    /**
     * Returns: Localized icon name
     * See_Also: iconName
     */
    @safe string localizedIconName(string locale) const nothrow {
        return localizedValue("Icon", locale);
    }
    
    private @nogc @safe static string boolToString(bool b) nothrow pure {
        return b ? "true" : "false";
    }
    
    unittest
    {
        assert(boolToString(false) == "false");
        assert(boolToString(true) == "true");
    }
    
    /**
     * NoDisplay means "this application exists, but don't display it in the menus".
     * Returns: The value associated with "NoDisplay" key converted to bool using isTrue.
     */
    @nogc @safe bool noDisplay() const nothrow {
        return isTrue(value("NoDisplay"));
    }
    
    ///setter
    @safe bool noDisplay(bool notDisplay) {
        this["NoDisplay"] = boolToString(notDisplay);
        return notDisplay;
    }
    
    /**
     * Hidden means the user deleted (at his level) something that was present (at an upper level, e.g. in the system dirs). 
     * It's strictly equivalent to the .desktop file not existing at all, as far as that user is concerned. 
     * Returns: The value associated with "Hidden" key converted to bool using isTrue.
     */
    @nogc @safe bool hidden() const nothrow {
        return isTrue(value("Hidden"));
    }
    
    ///setter
    @safe bool hidden(bool hide) {
        this["Hidden"] = boolToString(hide);
        return hide;
    }
    
    /**
     * A boolean value specifying if D-Bus activation is supported for this application.
     * Returns: The value associated with "dbusActivable" key converted to bool using isTrue.
     */
    @nogc @safe bool dbusActivable() const nothrow {
        return isTrue(value("DBusActivatable"));
    }
    
    ///setter
    @safe bool dbusActivable(bool activable) {
        this["DBusActivatable"] = boolToString(activable);
        return activable;
    }
    
    /**
     * Returns: The value associated with "startupNotify" key converted to bool using isTrue.
     */
    @nogc @safe bool startupNotify() const nothrow {
        return isTrue(value("StartupNotify"));
    }
    
    ///setter
    @safe bool startupNotify(bool notify) {
        this["StartupNotify"] = boolToString(notify);
        return notify;
    }
    
    /**
     * The working directory to run the program in.
     * Returns: The value associated with "Path" key.
     */
    @nogc @safe string workingDirectory() const nothrow {
        return value("Path");
    }
    
    /**
     * Set Path value.
     * Throws:
     *  Exception if wd is not valid path or wd is not abolute path nor base name.
     */
    @safe string workingDirectory(string wd) {
        enforce(wd.isValidPath, "Working directory must be valid path");
        enforce(wd.isAbsolute || wd.baseName == wd, "Path (working directory) must be absolute path or base name");
        this["Path"] = wd;
        return wd;
    }
    
    ///
    unittest
    {
        auto df = new DesktopFile();
        assertNotThrown(df.workingDirectory = "valid path");
        assertThrown(df.workingDirectory = "/foo\0/bar");
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
     * Categories this program belongs to.
     * Returns: The range of multiple values associated with "Categories" key.
     */
    @safe auto categories() const nothrow {
        return DesktopFile.splitValues(value("Categories"));
    }
    
    /**
     * Sets the list of values for the "Categories" list.
     */
    @safe void categories(Range)(Range values) if (isInputRange!Range && isSomeString!(ElementType!Range)) {
        this["Categories"] = DesktopFile.joinValues(values);
    }
    
    /**
     * A list of strings which may be used in addition to other metadata to describe this entry.
     * Returns: The range of multiple values associated with "Keywords" key.
     */
    @safe auto keywords() const nothrow {
        return DesktopFile.splitValues(value("Keywords"));
    }
    
    /**
     * A list of localied strings which may be used in addition to other metadata to describe this entry.
     * Returns: The range of multiple values associated with "Keywords" key in given locale.
     */
    @safe auto localizedKeywords(string locale) const nothrow {
        return DesktopFile.splitValues(localizedValue("Keywords", locale));
    }
    
    /**
     * Sets the list of values for the "Keywords" list.
     */
    @safe void keywords(Range)(Range values) if (isInputRange!Range && isSomeString!(ElementType!Range)) {
        this["Keywords"] = DesktopFile.joinValues(values);
    }
    
    /**
     * The MIME type(s) supported by this application.
     * Returns: The range of multiple values associated with "MimeType" key.
     */
    @safe auto mimeTypes() nothrow const {
        return DesktopFile.splitValues(value("MimeType"));
    }
    
    /**
     * Sets the list of values for the "MimeType" list.
     */
    @safe void mimeTypes(Range)(Range values) if (isInputRange!Range && isSomeString!(ElementType!Range)) {
        this["MimeType"] = DesktopFile.joinValues(values);
    }
    
    /**
     * Actions supported by application.
     * Returns: Range of multiple values associated with "Actions" key.
     * Note: This only depends on "Actions" value, not on actually presented sections in desktop file.
     * See_Also: byAction, action
     */
    @safe auto actions() nothrow const {
        return DesktopFile.splitValues(value("Actions"));
    }
    
    /**
     * Sets the list of values for "Actions" list.
     */
    @safe void actions(Range)(Range values) if (isInputRange!Range && isSomeString!(ElementType!Range)) {
        this["Actions"] = DesktopFile.joinValues(values);
    }
    
    /**
     * A list of strings identifying the desktop environments that should display a given desktop entry.
     * Returns: The range of multiple values associated with "OnlyShowIn" key.
     */
    @safe auto onlyShowIn() const {
        return DesktopFile.splitValues(value("OnlyShowIn"));
    }
    
    ///setter
    @safe void onlyShowIn(Range)(Range values) if (isInputRange!Range && isSomeString!(ElementType!Range)) {
        this["OnlyShowIn"] = DesktopFile.joinValues(values);
    }
    
    /**
     * A list of strings identifying the desktop environments that should not display a given desktop entry.
     * Returns: The range of multiple values associated with "NotShowIn" key.
     */
    @safe auto notShowIn() const {
        return DesktopFile.splitValues(value("NotShowIn"));
    }
    
    ///setter
    @safe void notShowIn(Range)(Range values) if (isInputRange!Range && isSomeString!(ElementType!Range)) {
        this["NotShowIn"] = DesktopFile.joinValues(values);
    }
    
protected:
    @trusted override void validateKeyValue(string key, string value) const {
        enforce(isValidKey(key), "key is invalid");
    }
}

/**
 * Represents .desktop file.
 * 
 */
final class DesktopFile : IniLikeFile
{
public:
    /**
     * Alias for backward compatibility.
     */
    alias DesktopEntry.Type Type;
    
    ///Flags to manage desktop file reading
    enum ReadOptions
    {
        noOptions = 0,              /// Read all groups, skip comments and empty lines, stop on any error.
        preserveComments = 2,       /// Preserve comments and empty lines. Use this when you want to keep them across writing.
        ignoreGroupDuplicates = 4,  /// Ignore group duplicates. The first found will be used.
        ignoreInvalidKeys = 8,      /// Skip invalid keys during parsing.
        ignoreKeyDuplicates = 16,   /// Ignore key duplicates. The first found will be used.
        ignoreUnknownGroups = 32,   /// Don't throw on unknown groups. Still save them.
        skipUnknownGroups = 64,     /// Don't save unknown groups. Use it with ignoreUnknownGroups.
        skipExtensionGroups = 128,  /// Don't save groups which names are started with X-.
        skipActionGroups = 256      /// Don't save Desktop Action groups during parsing.
    }
    
    /**
     * Default options for desktop file reading.
     */
    enum defaultReadOptions = ReadOptions.ignoreUnknownGroups | ReadOptions.skipUnknownGroups | ReadOptions.preserveComments;
    
protected:
    @trusted bool isActionName(string groupName)
    {
        return groupName.startsWith("Desktop Action ");
    }
    
    @trusted override void addCommentForGroup(string comment, IniLikeGroup currentGroup, string groupName)
    {
        if (currentGroup && (_options & ReadOptions.preserveComments)) {
            currentGroup.addComment(comment);
        }
    }
    
    @trusted override void addKeyValueForGroup(string key, string value, IniLikeGroup currentGroup, string groupName)
    {
        if (currentGroup) {
            if ((groupName == "Desktop Entry" || isActionName(groupName)) && !isValidKey(key) && (_options & ReadOptions.ignoreInvalidKeys)) {
                return;
            }
            if (currentGroup.contains(key)) {
                if (_options & ReadOptions.ignoreKeyDuplicates) {
                    return;
                } else {
                    throw new Exception("key '" ~ key ~ "' already exists");
                }
            }
            currentGroup[key] = value;
        }
    }
    
    @trusted override IniLikeGroup createGroup(string groupName)
    {
        if (group(groupName) !is null) {
            if (_options & ReadOptions.ignoreGroupDuplicates) {
                return null;
            } else {
                throw new Exception("group '" ~ groupName ~ "' already exists");
            }
        }
        
        if (groupName == "Desktop Entry") {
            _desktopEntry = new DesktopEntry();
            return _desktopEntry;
        } else if (groupName.startsWith("X-")) {
            if (_options & ReadOptions.skipExtensionGroups) {
                return null;
            }
            return createEmptyGroup(groupName);
        } else if (isActionName(groupName)) {
            if (_options & ReadOptions.skipActionGroups) {
                return null;
            } else {
                return new DesktopAction(groupName);
            }
        } else {
            if (_options & ReadOptions.ignoreUnknownGroups) {
                if (_options & ReadOptions.skipUnknownGroups) {
                    return null;
                } else {
                    return createEmptyGroup(groupName);
                }
            } else {
                throw new Exception("Invalid group name: '" ~ groupName ~ "'. Must start with 'Desktop Action ' or 'X-'");
            }
        }
    }
    
public:
    /**
     * Reads desktop file from file.
     * Throws:
     *  $(B ErrnoException) if file could not be opened.
     *  $(B IniLikeException) if error occured while reading the file.
     */
    @safe this(string fileName, ReadOptions options = defaultReadOptions) {
        this(iniLikeFileReader(fileName), options, fileName);
    }
    
    /**
     * Reads desktop file from IniLikeReader, e.g. acquired from iniLikeFileReader or iniLikeStringReader.
     * Throws:
     *  $(B IniLikeException) if error occured while parsing.
     */
    @trusted this(IniLikeReader)(IniLikeReader reader, ReadOptions options = defaultReadOptions, string fileName = null)
    {   
        _options = options;
        super(reader, fileName);
        enforce(_desktopEntry !is null, new IniLikeException("No \"Desktop Entry\" group", 0));
        _options = ReadOptions.ignoreUnknownGroups | ReadOptions.preserveComments;
    }
    
    /**
     * Reads desktop file from IniLikeReader, e.g. acquired from iniLikeFileReader or iniLikeStringReader.
     * Throws:
     *  $(B IniLikeException) if error occured while parsing.
     */
    @trusted this(IniLikeReader)(IniLikeReader reader, string fileName, ReadOptions options = defaultReadOptions)
    {
        this(reader, options, fileName);
    }
    
    /**
     * Constructs DesktopFile with "Desktop Entry" group and Version set to 1.0
     */
    @safe this() {
        super();
        addGroup("Desktop Entry");
        _desktopEntry["Version"] = "1.0";
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
        df.addGroup("X-Action");
        assert(df.group("X-Action") !is null);
        df.removeGroup("X-Action");
        assert(df.group("X-Action") is null);
        df.removeGroup("Desktop Entry");
        assert(df.desktopEntry() !is null);
    }
    
    @trusted override void addLeadingComment(string line) nothrow {
        if (_options & ReadOptions.preserveComments) {
            super.addLeadingComment(line);
        }
    }
    
    /**
     * Type of desktop entry.
     * Returns: Type of desktop entry.
     * See_Also: DesktopEntry.type
     */
    @nogc @safe Type type() const nothrow {
        auto t = desktopEntry().type();
        if (t == Type.Unknown && fileName().endsWith(".directory")) {
            return Type.Directory;
        }
        return t;
    }
    
    @safe Type type(Type t) {
        return desktopEntry().type(t);
    }
    
    ///
    unittest
    {   
        auto desktopFile = new DesktopFile(iniLikeStringReader("[Desktop Entry]"), ReadOptions.noOptions, ".directory");
        assert(desktopFile.type == DesktopFile.Type.Directory);
    }
    
    static if (isFreedesktop) {
        /** 
        * See $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/ape.html, Desktop File ID)
        * Returns: Desktop file ID or empty string if file does not have an ID.
        * Note: This function retrieves applications paths each time it's called and therefore can impact performance. To avoid this issue use overload with argument.
        * See_Also: desktopfile.paths.applicationsPaths, desktopfile.utils.desktopId
        */
        @safe string id() const nothrow {
            return desktopId(fileName);
        }
        
        ///
        unittest
        {
            import xdgpaths;
            
            string contents = "[Desktop Entry]\nType=Directory";
            auto df = new DesktopFile(iniLikeStringReader(contents), "/home/user/data/applications/test/example.desktop");
            auto dataHomeGuard = EnvGuard("XDG_DATA_HOME");
            environment["XDG_DATA_HOME"] = "/home/user/data";
            assert(df.id() == "test-example.desktop");
        }
    }
    
    /**
     * See $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/ape.html, Desktop File ID)
     * Params: 
     *  appPaths = range of base application paths to check if this file belongs to one of them.
     * Returns: Desktop file ID or empty string if file does not have an ID.
     * See_Also: desktopfile.paths.applicationsPaths, desktopfile.utils.desktopId
     */
    @trusted string id(Range)(Range appPaths) const nothrow if (isInputRange!Range && is(ElementType!Range : string)) 
    {
        return desktopId(fileName, appPaths);
    }
    
    ///
    unittest 
    {
        string contents = 
`[Desktop Entry]
Name=Program
Type=Directory`;
        
        string[] appPaths;
        string filePath, nestedFilePath, wrongFilePath;
        
        version(Windows) {
            appPaths = [`C:\ProgramData\KDE\share\applications`, `C:\Users\username\.kde\share\applications`];
            filePath = `C:\ProgramData\KDE\share\applications\example.desktop`;
            nestedFilePath = `C:\ProgramData\KDE\share\applications\kde\example.desktop`;
            wrongFilePath = `C:\ProgramData\desktop\example.desktop`;
        } else {
            appPaths = ["/usr/share/applications", "/usr/local/share/applications"];
            filePath = "/usr/share/applications/example.desktop";
            nestedFilePath = "/usr/share/applications/kde/example.desktop";
            wrongFilePath = "/etc/desktop/example.desktop";
        }
         
        auto df = new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.noOptions, nestedFilePath);
        assert(df.id(appPaths) == "kde-example.desktop");
        
        df = new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.noOptions, filePath);
        assert(df.id(appPaths) == "example.desktop");
        
        df = new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.noOptions, wrongFilePath);
        assert(df.id(appPaths).empty);
        
        df = new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.noOptions);
        assert(df.id(appPaths).empty);
    }
    
    private static struct SplitValues
    {
        @trusted this(string value) nothrow {
            _value = value;
            next();
        }
        @nogc @trusted string front() const nothrow pure {
            return _current;
        }
        @trusted void popFront() nothrow {
            next();
        }
        @trusted bool empty() const nothrow pure {
            return _value.empty && _current.empty;
        }
        @trusted @property auto save() const nothrow pure {
            SplitValues values;
            values._value = _value;
            values._current = _current;
            return values;
        }
    private:
        void next() nothrow {
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
    @trusted static auto splitValues(string values) nothrow {
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
        
        auto values = DesktopFile.splitValues("Application;Utility;FileManager;");
        assert(values.front == "Application");
        values.popFront();
        assert(equal(values, ["Utility", "FileManager"]));
        auto saved = values.save;
        values.popFront();
        assert(equal(values, ["FileManager"]));
        assert(equal(saved, ["Utility", "FileManager"]));
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
     * Get $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s10.html, additional application action) by name.
     * Returns: DesktopAction with given action name or null if not found or found section does not have a name.
     * See_Also: actions, byAction
     */
    @trusted inout(DesktopAction) action(string actionName) inout {
        if (actions().canFind(actionName)) {
            auto desktopAction = cast(typeof(return))group("Desktop Action "~actionName);
            if (desktopAction !is null && desktopAction.displayName().length != 0) {
                return desktopAction;
            }
        }
        return null;
    }
    
    /**
     * Iterating over existing actions.
     * Returns: Range of DesktopAction.
     * See_Also: actions, action
     */
    @safe auto byAction() const {
        return actions().map!(actionName => action(actionName)).filter!(desktopAction => desktopAction !is null);
    }
    
    /**
     * Returns: instance of "Desktop Entry" group.
     * Note: Usually you don't need to call this function since you can rely on alias this.
     */
    @nogc @safe inout(DesktopEntry) desktopEntry() nothrow inout {
        return _desktopEntry;
    }
    
    /**
     * This alias allows to call functions related to "Desktop Entry" group without need to call desktopEntry explicitly.
     */
    alias desktopEntry this;
    
    /**
     * Expand "Exec" value into the array of command line arguments to use to start the program.
     * It applies unquoting and unescaping.
     * See_Also: execString, desktopfile.utils.expandExecArgs, startApplication
     */
    @safe string[] expandExecString(in string[] urls = null, string locale = null) const
    {   
        return .expandExecString(execString(), urls, localizedIconName(locale), localizedDisplayName(locale), fileName());
    }
    
    ///
    unittest 
    {
        string contents = 
`[Desktop Entry]
Name=Program
Name[ru]=Программа
Exec="quoted program" %i -w %c -f %k %U %D %u %f %F
Icon=folder
Icon[ru]=folder_ru`;
        auto df = new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.noOptions, "/example.desktop");
        assert(df.expandExecString(["one", "two"], "ru") == 
        ["quoted program", "--icon", "folder_ru", "-w", "Программа", "-f", "/example.desktop", "one", "two", "one", "one", "one", "two"]);
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
     *  DesktopExecException if exec string is invalid.
     * See_Also: desktopfile.utils.getTerminalCommand, start, expandExecString
     */
    @trusted Pid startApplication(in string[] urls = null, string locale = null, lazy const(string)[] terminalCommand = getTerminalCommand) const
    {
        auto args = expandExecString(urls, locale);
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
        
        version(Posix) {
            static string[] emptyTerminalCommand() nothrow {
                return null;
            }
            
            df = new DesktopFile(iniLikeStringReader("[Desktop Entry]\nTerminal=true\nType=Application\nExec=whoami"));
            try {
                df.startApplication((string[]).init, null, emptyTerminalCommand);
            } catch(Exception e) {
                
            }
        }
    }
    
    ///ditto, but uses the only url.
    @trusted Pid startApplication(string url, string locale = null, lazy const(string)[] terminalCommand = getTerminalCommand) const {
        return startApplication([url], locale, terminalCommand);
    }
    
    /**
     * Opens url defined in .desktop file using $(LINK2 http://portland.freedesktop.org/xdg-utils-1.0/xdg-open.html, xdg-open).
     * Note:
     *  This function does not check if the type of desktop file is Link. It relies only on "URL" value.
     * Throws:
     *  ProcessException on failure to start the process.
     *  Exception if desktop file does not define URL or it's empty.
     * See_Also: start
     */
    @trusted void startLink() const {
        string myurl = url();
        enforce(myurl.length, "No URL to open");
        xdgOpen(myurl);
    }
    
    ///
    unittest
    {
        auto df = new DesktopFile();
        assertThrown(df.startLink());
    }
    
    /**
     * Starts application or open link depending on desktop entry type.
     * Throws:
     *  ProcessException on failure to start the process.
     *  Exception if type is Unknown or Directory.
     * See_Also: startApplication, startLink
     */
    @trusted void start() const
    {
        final switch(type()) {
            case DesktopFile.Type.Application:
                startApplication();
                return;
            case DesktopFile.Type.Link:
                startLink();
                return;
            case DesktopFile.Type.Directory:
                throw new Exception("Don't know how to start Directory");
            case DesktopFile.Type.Unknown:
                throw new Exception("Unknown desktop entry type");
        }
    }
    
    ///
    unittest
    {
        string contents = "[Desktop Entry]\nType=Directory";
        auto df = new DesktopFile(iniLikeStringReader(contents));
        assertThrown(df.start());
        
        df = new DesktopFile();
        assertThrown(df.start());
    }
    
private:
    DesktopEntry _desktopEntry;
    ReadOptions _options;
}

///
unittest 
{
    import std.file;
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
Icon[ru]=doublecmd_ru
Exec=doublecmd %f
TryExec=doublecmd
Type=Application
Categories=Application;Utility;FileManager;
Keywords=folder;manager;disk;filesystem;operations;
Keywords[ru]=папка;директория;диск;файловый;менеджер;
Actions=OpenDirectory;NotPresented;Settings;X-NoName;
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

[X-NoName]
Icon=folder

[Desktop Action Settings]
Name=Settings
Name[ru]=Настройки
Icon=edit
Exec=doublecmd settings

[Desktop Action Notspecified]
Name=Notspecified Action`;
    
    auto df = new DesktopFile(iniLikeStringReader(desktopFileContents), DesktopFile.ReadOptions.preserveComments, "doublecmd.desktop");
    assert(df.fileName() == "doublecmd.desktop");
    assert(df.displayName() == "Double Commander");
    assert(df.localizedDisplayName("ru_RU") == "Двухпанельный коммандер");
    assert(df.genericName() == "File manager");
    assert(df.localizedGenericName("ru_RU") == "Файловый менеджер");
    assert(df.comment() == "Double Commander is a cross platform open source file manager with two panels side by side.");
    assert(df.localizedComment("ru_RU") == "Double Commander - кроссплатформенный файловый менеджер.");
    assert(df.iconName() == "doublecmd");
    assert(df.localizedIconName("ru_RU") == "doublecmd_ru");
    assert(df.tryExecString() == "doublecmd");
    assert(!df.terminal());
    assert(!df.noDisplay());
    assert(!df.hidden());
    assert(df.startupNotify());
    assert(df.dbusActivable());
    assert(df.workingDirectory() == "/opt/doublecmd");
    assert(df.type() == DesktopFile.Type.Application);
    assert(equal(df.keywords(), ["folder", "manager", "disk", "filesystem", "operations"]));
    assert(equal(df.localizedKeywords("ru_RU"), ["папка", "директория", "диск", "файловый", "менеджер"]));
    assert(equal(df.categories(), ["Application", "Utility", "FileManager"]));
    assert(equal(df.actions(), ["OpenDirectory", "NotPresented", "Settings", "X-NoName"]));
    assert(equal(df.mimeTypes(), ["inode/directory", "application/x-directory"]));
    assert(equal(df.onlyShowIn(), ["GNOME", "XFCE", "LXDE"]));
    assert(equal(df.notShowIn(), ["KDE"]));
    
    assert(equal(df.byAction().map!(desktopAction => 
    tuple(desktopAction.displayName(), desktopAction.localizedDisplayName("ru"), desktopAction.iconName(), desktopAction.execString())), 
                 [tuple("Open directory", "Открыть папку", "open", "doublecmd %u"), tuple("Settings", "Настройки", "edit", "doublecmd settings")]));
    
    assert(df.action("NotPresented") is null);
    assert(df.action("Notspecified") is null);
    assert(df.action("X-NoName") is null);
    assert(df.action("Settings") !is null);
    
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
`# First comment
[Desktop Entry]
Key=Value
# Comment in group`;

    df = new DesktopFile(iniLikeStringReader(contents), "test.desktop", DesktopFile.ReadOptions.noOptions);
    assert(df.fileName() == "test.desktop");
    df.removeGroup("Desktop Entry");
    assert(df.group("Desktop Entry") !is null);
    assert(df.desktopEntry() !is null);
    assert(df.leadingComments().empty);
    assert(equal(df.desktopEntry().byIniLine(), [IniLikeLine.fromKeyValue("Key", "Value")]));
    
    //after constructing can add comments
    df.addLeadingComment("# Another comment");
    assert(equal(df.leadingComments(), ["# Another comment"]));
    // and add unknown groups
    assert(df.addGroup("Some unknown name") !is null);
    
    df = new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.preserveComments);
    assert(equal(df.leadingComments(), ["# First comment"]));
    assert(equal(df.desktopEntry().byIniLine(), [IniLikeLine.fromKeyValue("Key", "Value"), IniLikeLine.fromComment("# Comment in group")]));
    
    contents = 
`[X-SomeGroup]
Key=Value`;

    auto thrown = collectException!IniLikeException(new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.noOptions));
    assert(thrown !is null);
    assert(thrown.lineNumber == 0);
    
    contents = 
`[Desktop Entry]
Key=Value
Actions=Action1;
[Desktop Action Action1]
Key=Value`;

    df = new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.skipActionGroups);
    assert(df.action("Action1") is null);
    
    contents = 
`[Desktop Entry]
Valid=Key
$=Invalid`;

    assertThrown(new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.noOptions));
    assertNotThrown(new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.ignoreInvalidKeys));
    
    contents = 
`[Desktop Entry]
Key=Value1
Key=Value2`;

    assertThrown(new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.noOptions));
    assertNotThrown(df = new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.ignoreKeyDuplicates));
    assert(df.desktopEntry().value("Key") == "Value1");
    
    contents = 
`[Desktop Entry]
Name=Name
[Unknown]
Key=Value`;

    assertThrown(new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.noOptions));
    assertNotThrown(df = new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.ignoreUnknownGroups));
    assert(df.group("Unknown") !is null);
    
    df = new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.ignoreUnknownGroups|DesktopFile.ReadOptions.skipUnknownGroups);
    assert(df.group("Unknown") is null);
    
    contents = 
`[Desktop Entry]
Name=Name1
[Desktop Entry]
Name=Name2`;
    
    assertThrown(new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.noOptions));
    assertNotThrown(df = new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.ignoreGroupDuplicates));
    
    assert(df.desktopEntry().value("Name") == "Name1");
}
