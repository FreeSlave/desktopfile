/**
 * Class representation of desktop file.
 * Authors: 
 *  $(LINK2 https://github.com/MyLittleRobo, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2015-2016
 * License: 
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * See_Also: 
 *  $(LINK2 https://www.freedesktop.org/wiki/Specifications/desktop-entry-spec/, Desktop Entry Specification)
 */

module desktopfile.file;

public import inilike.file;
public import desktopfile.utils;

private @trusted void validateDesktopKeyImpl(string groupName, string key, string value) {
    if (!isValidDesktopFileKey(key)) {
        throw new IniLikeEntryException("key is invalid", groupName, key, value);
    }
}

/**
 * Subclass of IniLikeGroup for easy access to desktop action.
 */
final class DesktopAction : IniLikeGroup
{
protected:
    @trusted override void validateKey(string key, string value) const {
        validateDesktopKeyImpl(groupName(), key, value);
    }
public:
    package @nogc @safe this(string groupName) nothrow {
        super(groupName);
    }
    
    /**
     * Label that will be shown to the user.
     * Returns: The value associated with "Name" key.
     */
    @safe string displayName() const nothrow pure {
        return readEntry("Name");
    }
    
    /**
     * Label that will be shown to the user in given locale.
     * Returns: The value associated with "Name" key and given locale.
     */
    @safe string localizedDisplayName(string locale) const nothrow pure {
        return readEntry("Name", locale);
    }
    
    /**
     * Icon name of action.
     * Returns: The value associated with "Icon" key.
     */
    @safe string iconName() const nothrow pure {
        return readEntry("Icon");
    }
    
    /**
     * Returns: Localized icon name
     * See_Also: $(D iconName)
     */
    @safe string localizedIconName(string locale) const nothrow pure {
        return readEntry("Icon", locale);
    }
    
    /**
     * Returns: The value associated with "Exec" key.
     */
    @safe string execValue() const nothrow pure {
        return readEntry("Exec");
    }
    
    /**
     * Start this action.
     * Returns:
     *  Pid of started process.
     * Throws:
     *  ProcessException on failure to start the process.
     *  DesktopExecException if exec string is invalid.
     * See_Also: $(D execValue)
     */
    @safe Pid start(string locale = null) const {
        auto unquotedArgs = unquoteExec(execValue());
        
        SpawnParams params;
        params.iconName = localizedIconName(locale);
        params.displayName = localizedDisplayName(locale);
        
        return spawnApplication(unquotedArgs, params);
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
    @nogc @safe Type type() const nothrow pure {
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
     * Specific name of the application, for example "Qupzilla".
     * Returns: The value associated with "Name" key.
     * See_Also: $(D localizedDisplayName)
     */
    @safe string displayName() const nothrow pure {
        return readEntry("Name");
    }
    
    /**
     * Set "Name" to name escaping the value if needed.
     */
    @safe string displayName(string name) {
        return writeEntry("Name", name);
    }
    
    /**
     * Returns: Localized name.
     * See_Also: $(D displayName)
     */
    @safe string localizedDisplayName(string locale) const nothrow pure {
        return readEntry("Name", locale);
    }
    
    /**
     * Generic name of the application, for example "Web Browser".
     * Returns: The value associated with "GenericName" key.
     * See_Also: $(D localizedGenericName)
     */
    @safe string genericName() const nothrow pure {
        return readEntry("GenericName");
    }
    
    /**
     * Set "GenericName" to name escaping the value if needed.
     */
    @safe string genericName(string name) {
        return writeEntry("GenericName", name);
    }
    /**
     * Returns: Localized generic name
     * See_Also: $(D genericName)
     */
    @safe string localizedGenericName(string locale) const nothrow pure {
        return readEntry("GenericName", locale);
    }
    
    /**
     * Tooltip for the entry, for example "View sites on the Internet".
     * Returns: The value associated with "Comment" key.
     * See_Also: $(D localizedComment)
     */
    @safe string comment() const nothrow pure {
        return readEntry("Comment");
    }
    
    /**
     * Set "Comment" to commentary escaping the value if needed.
     */
    @safe string comment(string commentary) {
        return writeEntry("Comment", commentary);
    }
    
    /**
     * Returns: Localized comment
     * See_Also: $(D comment)
     */
    @safe string localizedComment(string locale) const nothrow pure {
        return readEntry("Comment", locale);
    }
    
    /** 
     * Exec value of desktop file.
     * Returns: the value associated with "Exec" key.
     * See_Also: $(D expandExecValue), $(D startApplication), $(D tryExecValue)
     */
    @safe string execValue() const nothrow pure {
        return readEntry("Exec");
    }
    
    /**
     * Set "Exec" to exec escaping the value if needed.
     * See_Also: $(D desktopfile.utils.ExecBuilder).
     */
    @safe string execValue(string exec) {
        return writeEntry("Exec", exec);
    }
    
    /**
     * URL to access.
     * Returns: The value associated with "URL" key.
     */
    @safe string url() const nothrow pure {
        return readEntry("URL");
    }
    
    /**
     * Set "URL" to link escaping the value if needed.
     */
    @safe string url(string link) {
        return writeEntry("URL", link);
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
     * See_Also: $(D execValue)
     */
    @safe string tryExecValue() const nothrow pure {
        return readEntry("TryExec");
    }
    
    /**
     * Set TryExec value escaping it if needed..
     * Throws:
     *  $(B IniLikeEntryException) if tryExec is not abolute path nor base name.
     */
    @safe string tryExecValue(string tryExec) {
        if (!tryExec.isAbsolute && tryExec.baseName != tryExec) {
            throw new IniLikeEntryException("TryExec must be absolute path or base name", groupName(), "TryExec", tryExec);
        }
        return writeEntry("TryExec", tryExec);
    }
    
    ///
    unittest
    {
        auto df = new DesktopFile();
        assertNotThrown(df.tryExecValue = "base");
        version(Posix) {
            assertNotThrown(df.tryExecValue = "/absolute/path");
        }
        assertThrown(df.tryExecValue = "not/absolute");
        assertThrown(df.tryExecValue = "./relative");
    }
    
    /**
     * Icon to display in file manager, menus, etc.
     * Returns: The value associated with "Icon" key.
     * Note: This function returns Icon as it's defined in .desktop file. 
     *  It does not provide any lookup of actual icon file on the system if the name if not an absolute path.
     *  To find the path to icon file refer to $(LINK2 http://standards.freedesktop.org/icon-theme-spec/icon-theme-spec-latest.html, Icon Theme Specification) or consider using $(LINK2 https://github.com/MyLittleRobo/icontheme, icontheme library).
     */
    @safe string iconName() const nothrow pure {
        return readEntry("Icon");
    }
    
    /**
     * Set Icon value.
     * Throws:
     *  $(B IniLikeEntryException) if icon is not abolute path nor base name.
     */
    @safe string iconName(string icon) {
        if (!icon.isAbsolute && icon.baseName != icon) {
            throw new IniLikeEntryException("Icon must be absolute path or base name", groupName(), "Icon", icon);
        }
        return writeEntry("Icon", icon);
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
     * See_Also: $(D iconName)
     */
    @safe string localizedIconName(string locale) const nothrow pure {
        return readEntry("Icon", locale);
    }
    
    /**
     * NoDisplay means "this application exists, but don't display it in the menus".
     * Returns: The value associated with "NoDisplay" key converted to bool using isTrue.
     */
    @nogc @safe bool noDisplay() const nothrow pure {
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
    @nogc @safe bool hidden() const nothrow pure {
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
    @nogc @safe bool dbusActivable() const nothrow pure {
        return isTrue(value("DBusActivatable"));
    }
    
    ///setter
    @safe bool dbusActivable(bool activable) {
        this["DBusActivatable"] = boolToString(activable);
        return activable;
    }
    
    /**
     * A boolean value specifying if an application uses Startup Notification Protocol.
     * Returns: The value associated with "startupNotify" key converted to bool using isTrue.
     */
    @nogc @safe bool startupNotify() const nothrow pure {
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
    @safe string workingDirectory() const nothrow pure {
        return readEntry("Path");
    }
    
    /**
     * Set Path value.
     * Throws:
     *  $(D IniLikeEntryException) if wd is not valid path or wd is not abolute path.
     */
    @safe string workingDirectory(string wd) {
        if (!wd.isValidPath) {
            throw new IniLikeEntryException("Working directory must be valid path", groupName(), "Path", wd);
        }
        version(Posix) {
            if (!wd.isAbsolute) {
                throw new IniLikeEntryException("Working directory must be absolute path", groupName(), "Path", wd);
            }
        }
        return writeEntry("Path", wd);
    }
    
    ///
    unittest
    {
        auto df = new DesktopFile();
        version(Posix) {
            assertNotThrown(df.workingDirectory = "/valid");
            assertThrown(df.workingDirectory = "not absolute");
        }
        assertThrown(df.workingDirectory = "/foo\0/bar");
    }
    
    /**
     * Whether the program runs in a terminal window.
     * Returns: The value associated with "Terminal" key converted to bool using isTrue.
     */
    @nogc @safe bool terminal() const nothrow pure {
        return isTrue(value("Terminal"));
    }
    ///setter
    @safe bool terminal(bool t) {
        this["Terminal"] = boolToString(t);
        return t;
    }
    
    /**
     * Categories this program belongs to.
     * Returns: The range of multiple values associated with "Categories" key.
     */
    @safe auto categories() const nothrow pure {
        return DesktopFile.splitValues(readEntry("Categories"));
    }
    
    /**
     * Sets the list of values for the "Categories" list.
     */
    string categories(Range)(Range values) if (isInputRange!Range && isSomeString!(ElementType!Range)) {
        return writeEntry("Categories", DesktopFile.joinValues(values));
    }
    
    /**
     * A list of strings which may be used in addition to other metadata to describe this entry.
     * Returns: The range of multiple values associated with "Keywords" key.
     */
    @safe auto keywords() const nothrow pure {
        return DesktopFile.splitValues(readEntry("Keywords"));
    }
    
    /**
     * A list of localied strings which may be used in addition to other metadata to describe this entry.
     * Returns: The range of multiple values associated with "Keywords" key in given locale.
     */
    @safe auto localizedKeywords(string locale) const nothrow pure {
        return DesktopFile.splitValues(readEntry("Keywords", locale));
    }
    
    /**
     * Sets the list of values for the "Keywords" list.
     */
    string keywords(Range)(Range values) if (isInputRange!Range && isSomeString!(ElementType!Range)) {
        return writeEntry("Keywords", DesktopFile.joinValues(values));
    }
    
    /**
     * The MIME type(s) supported by this application.
     * Returns: The range of multiple values associated with "MimeType" key.
     */
    @safe auto mimeTypes() nothrow const pure {
        return DesktopFile.splitValues(readEntry("MimeType"));
    }
    
    /**
     * Sets the list of values for the "MimeType" list.
     */
    string mimeTypes(Range)(Range values) if (isInputRange!Range && isSomeString!(ElementType!Range)) {
        return writeEntry("MimeType", DesktopFile.joinValues(values));
    }
    
    /**
     * Actions supported by application.
     * Returns: Range of multiple values associated with "Actions" key.
     * Note: This only depends on "Actions" value, not on actually presented sections in desktop file.
     * See_Also: $(D byAction), $(D action)
     */
    @safe auto actions() nothrow const pure {
        return DesktopFile.splitValues(readEntry("Actions"));
    }
    
    /**
     * Sets the list of values for "Actions" list.
     */
    string actions(Range)(Range values) if (isInputRange!Range && isSomeString!(ElementType!Range)) {
        return writeEntry("Actions", DesktopFile.joinValues(values));
    }
    
    /**
     * A list of strings identifying the desktop environments that should display a given desktop entry.
     * Returns: The range of multiple values associated with "OnlyShowIn" key.
     */
    @safe auto onlyShowIn() nothrow const pure {
        return DesktopFile.splitValues(readEntry("OnlyShowIn"));
    }
    
    ///setter
    string onlyShowIn(Range)(Range values) if (isInputRange!Range && isSomeString!(ElementType!Range)) {
        return writeEntry("OnlyShowIn", DesktopFile.joinValues(values));
    }
    
    /**
     * A list of strings identifying the desktop environments that should not display a given desktop entry.
     * Returns: The range of multiple values associated with "NotShowIn" key.
     */
    @safe auto notShowIn() nothrow const pure {
        return DesktopFile.splitValues(readEntry("NotShowIn"));
    }
    
    ///setter
    string notShowIn(Range)(Range values) if (isInputRange!Range && isSomeString!(ElementType!Range)) {
        return writeEntry("NotShowIn", DesktopFile.joinValues(values));
    }
    
    /**
     * Check if desktop file should be shown in menu of specific desktop environment.
     * Params:
     *  desktopEnvironment = Name of desktop environment, usually detected by XDG_CURRENT_DESKTOP variable.
     * See_Also: $(LINK2 https://specifications.freedesktop.org/menu-spec/latest/apb.html, Registered OnlyShowIn Environments)
     */
    @trusted bool showIn(string desktopEnvironment)
    {
        if (notShowIn().canFind(desktopEnvironment)) {
            return false;
        }
        auto onlyIn = onlyShowIn();
        return onlyIn.empty || onlyIn.canFind(desktopEnvironment);
    }
    
    ///
    unittest
    {
        auto df = new DesktopFile();
        df.notShowIn = ["GNOME", "MATE"];
        assert(df.showIn("KDE"));
        assert(df.showIn("awesome"));
        assert(df.showIn(""));
        assert(!df.showIn("GNOME"));
        df.onlyShowIn = ["LXDE", "XFCE"];
        assert(df.showIn("LXDE"));
        assert(df.showIn("XFCE"));
        assert(!df.showIn(""));
        assert(!df.showIn("awesome"));
        assert(!df.showIn("KDE"));
        assert(!df.showIn("MATE"));
    }
    
protected:
    @trusted override void validateKey(string key, string value) const {
        validateDesktopKeyImpl(groupName(), key, value);
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
    
    ///Options to manage desktop file reading
    static struct DesktopReadOptions
    {
        ///Base $(B ReadOptions) of $(B IniLikeFile).
        IniLikeFile.ReadOptions baseOptions;
        
        alias baseOptions this;
        
        /**
         * Policy about reading Desktop Action groups.
         */
        enum ActionGroupPolicy {
            skip, ///Don't save Desktop Action groups.
            preserve ///Save Desktop Action groups.
        }
        
        /**
         * Policy about reading extension groups (those start with 'X-').
         */
        enum ExtensionGroupPolicy {
            skip, ///Don't save extension groups.
            preserve ///Save extension groups.
        }
        
        /**
         * Policy about reading groups with names which meaning is unknown, i.e. it's not extension nor Desktop Action.
         */
        enum UnknownGroupPolicy {
            skip, ///Don't save unknown groups.
            preserve, ///Save unknown groups.
            throwError ///Throw error when unknown group is encountered.
        }
        
        /**
         * Set policy about unknown groups. By default they are skipped without errors.
         * Note that all groups still need to be preserved if desktop file must be rewritten.
         */
        UnknownGroupPolicy unknownGroupPolicy = UnknownGroupPolicy.skip;
        
        /**
         * Set policy about extension groups. By default they are all preserved. 
         * Set it to skip if you're not willing to support any extensions in your applications.
         * Note that all groups still need to be preserved if desktop file must be rewritten.
         */
        ExtensionGroupPolicy extensionGroupPolicy = ExtensionGroupPolicy.preserve;
        
        /**
         * Set policy about desktop action groups. By default they are all preserved. 
         * Note that all groups still need to be preserved if desktop file must be rewritten.
         */
        ActionGroupPolicy actionGroupPolicy = ActionGroupPolicy.preserve;
    }
    
private:
    @trusted final bool isActionName(string groupName)
    {
        return groupName.startsWith("Desktop Action ");
    }
    
protected:
    @trusted override IniLikeGroup createGroupByName(string groupName) {
        if (groupName == "Desktop Entry") {
            _desktopEntry = new DesktopEntry();
            return _desktopEntry;
        } else if (groupName.startsWith("X-")) {
            if (_options.extensionGroupPolicy == DesktopReadOptions.UnknownGroupPolicy.skip) {
                return null;
            } else {
                return createEmptyGroup(groupName);
            }
        } else if (isActionName(groupName)) {
            if (_options.actionGroupPolicy == DesktopReadOptions.ActionGroupPolicy.skip) {
                return null;
            } else {
                return new DesktopAction(groupName);
            }
        } else {
            final switch(_options.unknownGroupPolicy) {
                case DesktopReadOptions.UnknownGroupPolicy.skip:
                    return null;
                case DesktopReadOptions.UnknownGroupPolicy.preserve:
                    return createEmptyGroup(groupName);
                case DesktopReadOptions.UnknownGroupPolicy.throwError:
                    throw new IniLikeException("Invalid group name: '" ~ groupName ~ "'. Must start with 'Desktop Action ' or 'X-'");
            }
        }
    }
    
public:
    /**
     * Reads desktop file from file.
     * Throws:
     *  $(B ErrnoException) if file could not be opened.
     *  $(B IniLikeReadException) if error occured while reading the file or "Desktop Entry" group is missing.
     */
    @trusted this(string fileName, DesktopReadOptions options = DesktopReadOptions.init) {
        this(iniLikeFileReader(fileName), options, fileName);
    }
    
    /**
     * Reads desktop file from IniLikeReader, e.g. acquired from iniLikeFileReader or iniLikeStringReader.
     * Throws:
     *  $(B IniLikeReadException) if error occured while parsing or "Desktop Entry" group is missing.
     */
    this(IniLikeReader)(IniLikeReader reader, DesktopReadOptions options = DesktopReadOptions.init, string fileName = null)
    {   
        _options = options;
        super(reader, fileName, options.baseOptions);
        enforce(_desktopEntry !is null, new IniLikeReadException("No \"Desktop Entry\" group", 0));
    }
    
    /**
     * Reads desktop file from IniLikeReader, e.g. acquired from iniLikeFileReader or iniLikeStringReader.
     * Throws:
     *  $(B IniLikeReadException) if error occured while parsing or "Desktop Entry" group is missing.
     */
    this(IniLikeReader)(IniLikeReader reader, string fileName, DesktopReadOptions options = DesktopReadOptions.init)
    {
        this(reader, options, fileName);
    }
    
    /**
     * Constructs DesktopFile with "Desktop Entry" group and Version set to 1.0
     */
    @safe this() {
        super();
        _desktopEntry = new DesktopEntry();
        insertGroup(_desktopEntry);
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
    @safe override bool removeGroup(string groupName) nothrow {
        if (groupName == "Desktop Entry") {
            return false;
        }
        return super.removeGroup(groupName);
    }
    
    ///
    unittest
    {
        auto df = new DesktopFile();
        df.addGenericGroup("X-Action");
        assert(df.group("X-Action") !is null);
        df.removeGroup("X-Action");
        assert(df.group("X-Action") is null);
        df.removeGroup("Desktop Entry");
        assert(df.desktopEntry() !is null);
    }
    
    /**
     * Type of desktop entry.
     * Returns: Type of desktop entry.
     * See_Also: $(D DesktopEntry.type)
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
        auto desktopFile = new DesktopFile(iniLikeStringReader("[Desktop Entry]"), ".directory");
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
            import desktopfile.paths;
            
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
     * See_Also: $(D desktopfile.paths.applicationsPaths), $(D desktopfile.utils.desktopId)
     */
    string id(Range)(Range appPaths) const nothrow if (isInputRange!Range && is(ElementType!Range : string)) 
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
         
        auto df = new DesktopFile(iniLikeStringReader(contents), nestedFilePath);
        assert(df.id(appPaths) == "kde-example.desktop");
        
        df = new DesktopFile(iniLikeStringReader(contents), filePath);
        assert(df.id(appPaths) == "example.desktop");
        
        df = new DesktopFile(iniLikeStringReader(contents), wrongFilePath);
        assert(df.id(appPaths).empty);
        
        df = new DesktopFile(iniLikeStringReader(contents));
        assert(df.id(appPaths).empty);
    }
    
    private static struct SplitValues
    {
        @trusted this(string value) nothrow pure {
            _value = value;
            next();
        }
        @nogc @trusted string front() const nothrow pure {
            return _current;
        }
        @trusted void popFront() nothrow pure {
            next();
        }
        @nogc @trusted bool empty() const nothrow pure {
            return _value.empty && _current.empty;
        }
        @nogc @trusted @property auto save() const nothrow pure {
            SplitValues values;
            values._value = _value;
            values._current = _current;
            return values;
        }
    private:
        void next() nothrow pure {
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
    @trusted static auto splitValues(string values) nothrow pure {
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
    static string joinValues(Range)(Range values) if (isInputRange!Range && isSomeString!(ElementType!Range)) {
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
     * See_Also: $(D actions), $(D byAction)
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
     * See_Also: $(D actions), $(D action)
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
     * See_Also: $(D execValue), $(D desktopfile.utils.expandExecArgs), $(D startApplication)
     */
    @safe string[] expandExecValue(in string[] urls = null, string locale = null) const
    {   
        return expandExecArgs(unquoteExec(execValue()), urls, locale);
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
        auto df = new DesktopFile(iniLikeStringReader(contents), "/example.desktop");
        assert(df.expandExecValue(["one", "two"], "ru") == 
        ["quoted program", "--icon", "folder_ru", "-w", "Программа", "-f", "/example.desktop", "one", "two", "one", "one", "one", "two"]);
    }
    
    private @safe string[] expandExecArgs(in string[] execArgs, in string[] urls = null, string locale = null) const
    {
        return .expandExecArgs(execArgs, urls, localizedIconName(locale), localizedDisplayName(locale), fileName());
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
     *  $(D desktopfile.utils.DesktopExecException) if exec string is invalid.
     * See_Also: $(D desktopfile.utils.getTerminalCommand), $(D start), $(D expandExecValue)
     */
    @trusted Pid startApplication(in string[] urls = null, string locale = null, lazy const(string)[] terminalCommand = getTerminalCommand) const
    {
        auto unquotedArgs = unquoteExec(execValue());
        
        SpawnParams params;
        params.urls = urls;
        params.iconName = localizedIconName(locale);
        params.displayName = localizedDisplayName(locale);
        params.fileName = fileName;
        params.workingDirectory = workingDirectory();
        
        if (terminal()) {
            params.terminalCommand = terminalCommand();
        }
        
        return spawnApplication(unquotedArgs, params);
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
     * Opens url defined in .desktop file using $(LINK2 https://portland.freedesktop.org/doc/xdg-open.html, xdg-open).
     * Note:
     *  This function does not check if the type of desktop file is Link. It relies only on "URL" value.
     * Throws:
     *  ProcessException on failure to start the process.
     *  Exception if desktop file does not define URL or it's empty.
     * See_Also: $(D start)
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
     * See_Also: $(D startApplication), $(D startLink)
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
    DesktopReadOptions _options;
}

///
unittest 
{
    import std.file;
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
    
    auto df = new DesktopFile(iniLikeStringReader(desktopFileContents), "doublecmd.desktop");
    assert(df.fileName() == "doublecmd.desktop");
    assert(df.displayName() == "Double Commander");
    assert(df.localizedDisplayName("ru_RU") == "Двухпанельный коммандер");
    assert(df.genericName() == "File manager");
    assert(df.localizedGenericName("ru_RU") == "Файловый менеджер");
    assert(df.comment() == "Double Commander is a cross platform open source file manager with two panels side by side.");
    assert(df.localizedComment("ru_RU") == "Double Commander - кроссплатформенный файловый менеджер.");
    assert(df.iconName() == "doublecmd");
    assert(df.localizedIconName("ru_RU") == "doublecmd_ru");
    assert(df.tryExecValue() == "doublecmd");
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
    tuple(desktopAction.displayName(), desktopAction.localizedDisplayName("ru"), desktopAction.iconName(), desktopAction.execValue())), 
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
    df.categories = ["Development", "Compilers", "One;Two", "Three\\;Four", "New\nLine"];
    
    assert(df.terminal() == true);
    assert(df.type() == DesktopFile.Type.Application);
    assert(equal(df.categories(), ["Development", "Compilers", "One;Two", "Three\\;Four","New\nLine"]));
    
    string contents = 
`# First comment
[Desktop Entry]
Key=Value
# Comment in group`;

    df = new DesktopFile(iniLikeStringReader(contents), "test.desktop");
    assert(df.fileName() == "test.desktop");
    df.removeGroup("Desktop Entry");
    assert(df.group("Desktop Entry") !is null);
    assert(df.desktopEntry() !is null);
    
    contents = 
`[X-SomeGroup]
Key=Value`;

    auto thrown = collectException!IniLikeReadException(new DesktopFile(iniLikeStringReader(contents)));
    assert(thrown !is null);
    assert(thrown.lineNumber == 0);
    
    contents = 
`[Desktop Entry]
Key=Value
Actions=Action1;
[Desktop Action Action1]
Key=Value`;

    alias DesktopFile.DesktopReadOptions DesktopReadOptions;
    DesktopReadOptions readOptions;
    readOptions.actionGroupPolicy = DesktopReadOptions.ActionGroupPolicy.skip;
    df = new DesktopFile(iniLikeStringReader(contents), readOptions);
    assert(df.action("Action1") is null);
    
    contents = 
`[Desktop Entry]
Valid=Key
$=Invalid`;

    thrown = collectException!IniLikeReadException(new DesktopFile(iniLikeStringReader(contents)));
    assert(thrown !is null);
    assert(thrown.entryException !is null);
    assert(thrown.entryException.key == "$");
    assert(thrown.entryException.value == "Invalid");
    
    readOptions = DesktopReadOptions.init;
    readOptions.invalidKeyPolicy = IniLikeGroup.InvalidKeyPolicy.skip;
    assertNotThrown(new DesktopFile(iniLikeStringReader(contents), readOptions));
    
    contents = 
`[Desktop Entry]
Name=Name
[Unknown]
Key=Value`;

    readOptions = DesktopReadOptions.init;
    readOptions.unknownGroupPolicy = DesktopReadOptions.UnknownGroupPolicy.throwError;
    assertThrown(new DesktopFile(iniLikeStringReader(contents), readOptions));
    
    readOptions = DesktopReadOptions.init;
    readOptions.unknownGroupPolicy = DesktopReadOptions.UnknownGroupPolicy.preserve;
    assertNotThrown(df = new DesktopFile(iniLikeStringReader(contents), readOptions));
    assert(df.group("Unknown") !is null);
    
    readOptions = DesktopReadOptions.init;
    readOptions.unknownGroupPolicy = DesktopReadOptions.UnknownGroupPolicy.skip;
    df = new DesktopFile(iniLikeStringReader(contents), readOptions);
    assert(df.group("Unknown") is null);
    
    df = new DesktopFile();
    df.displayName = "Program name";
    assert(df.displayName() == "Program name");
    df.genericName = "Program";
    assert(df.genericName() == "Program");
    df.comment = "Do\nthings";
    assert(df.comment() == "Do\nthings");
    
    df.execValue = "utilname";
    assert(df.execValue() == "utilname");
    
    df.noDisplay = true;
    assert(df.noDisplay());
    df.hidden = true;
    assert(df.hidden());
    df.dbusActivable = true;
    assert(df.dbusActivable());
    df.startupNotify = true;
    assert(df.startupNotify());
    
    df.url = "/some/url";
    assert(df.url == "/some/url");
}
