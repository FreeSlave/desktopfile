/**
 * Reading, writing and executing .desktop file
 * 
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * See_Also: $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/index.html, Desktop Entry Specification)
 */

module desktopfile;

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
    import std.typecons;
}

/**
 * Exception thrown when error occures during the .desktop file read.
 */
class DesktopFileException : Exception
{
    this(string msg, size_t lineNumber, string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure nothrow @safe {
        super(msg, file, line, next);
        _lineNumber = lineNumber;
    }
    
    ///Number of line in desktop file where the exception occured, starting from 1. Don't be confused with $(B line) property of $(B Throwable).
    size_t lineNumber() const {
        return _lineNumber;
    }
    
private:
    size_t _lineNumber;
}

private alias LocaleTuple = Tuple!(string, "lang", string, "country", string, "encoding", string, "modifier");
private alias KeyValueTuple = Tuple!(string, "key", string, "value");

/** Retrieves current locale probing environment variables LC_TYPE, LC_ALL and LANG (in this order)
 * Returns: locale in posix form or empty string if could not determine locale
 */
string currentLocale() @safe
{
    return environment.get("LC_CTYPE", environment.get("LC_ALL", environment.get("LANG")));
}

/**
 * Returns: locale name in form lang_COUNTRY.ENCODING@MODIFIER
 */
string makeLocaleName(string lang, string country = null, string encoding = null, string modifier = null) pure nothrow @safe
{
    return lang ~ (country.length ? "_"~country : "") ~ (encoding.length ? "."~encoding : "") ~ (modifier.length ? "@"~modifier : "");
}

/**
 * Parses locale name into the tuple of 4 values corresponding to language, country, encoding and modifier
 * Returns: Tuple!(string, "lang", string, "country", string, "encoding", string, "modifier")
 */
auto parseLocaleName(string locale) pure nothrow @nogc @trusted
{
    auto modifiderSplit = findSplit(locale, "@");
    auto modifier = modifiderSplit[2];
    
    auto encodongSplit = findSplit(modifiderSplit[0], ".");
    auto encoding = encodongSplit[2];
    
    auto countrySplit = findSplit(encodongSplit[0], "_");
    auto country = countrySplit[2];
    
    auto lang = countrySplit[0];
    
    return LocaleTuple(lang, country, encoding, modifier);
}

/**
 * Returns: localized key in form key[locale]. Automatically omits locale encoding if present.
 */
string localizedKey(string key, string locale) pure nothrow @safe
{
    auto t = parseLocaleName(locale);
    if (!t.encoding.empty) {
        locale = makeLocaleName(t.lang, t.country, null, t.modifier);
    }
    return key ~ "[" ~ locale ~ "]";
}

/**
 * Ditto, but constructs locale name from arguments.
 */
string localizedKey(string key, string lang, string country, string modifier = null) pure nothrow @safe
{
    return key ~ "[" ~ makeLocaleName(lang, country, null, modifier) ~ "]";
}

/** 
 * Separates key name into non-localized key and locale name.
 * If key is not localized returns original key and empty string.
 * Returns: tuple of key and locale name;
 */
Tuple!(string, string) separateFromLocale(string key) nothrow @nogc @trusted {
    if (key.endsWith("]")) {
        auto t = key.findSplit("[");
        if (t[1].length) {
            return tuple(t[0], t[2][0..$-1]);
        }
    }
    return tuple(key, string.init);
}

/**
 * Tells whether the character is valid for desktop entry key.
 * Note: This does not include characters presented in locale names.
 */
bool isValidKeyChar(char c) pure nothrow @nogc @safe
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-';
}


/**
 * Tells whethe the string is valid dekstop entry key.
 * Note: This does not include characters presented in locale names. Use $(B separateFromLocale) to get non-localized key to pass it to this function
 */
bool isValidKey(string key) pure nothrow @nogc @safe
{
    for (size_t i = 0; i<key.length; ++i) {
        if (!key[i].isValidKeyChar()) {
            return false;
        }
    }
    return true;
}

/**
 * Tells whether the dekstop entry value presents true
 */
bool isTrue(string value) pure nothrow @nogc @safe {
    return (value == "true" || value == "1");
}

/**
 * Tells whether the desktop entry value presents false
 */
bool isFalse(string value) pure nothrow @nogc @safe {
    return (value == "false" || value == "0");
}

/**
 * Check if the desktop entry value can be interpreted as boolean value.
 */
bool isBoolean(string value) pure nothrow @nogc @safe {
    return isTrue(value) || isFalse(value);
}

string escapeValue(string value) @trusted nothrow pure {
    return value.replace("\\", `\\`).replace("\n", `\n`).replace("\r", `\r`).replace("\t", `\t`);
}

string doUnescape(string value, in Tuple!(char, char)[] pairs) @trusted nothrow pure {
    auto toReturn = appender!string();
    
    for (size_t i = 0; i < value.length; i++) {
        if (value[i] == '\\') {
            if (i < value.length - 1) {
                char c = value[i+1];
                auto t = pairs.find!"a[0] == b[0]"(tuple(c,c));
                if (!t.empty) {
                    toReturn.put(t.front[1]);
                    i++;
                    continue;
                }
            }
        }
        toReturn.put(value[i]);
    }
    return toReturn.data;
}

string unescapeValue(string value) @trusted nothrow pure
{
    static immutable Tuple!(char, char)[] pairs = [
       tuple('s', ' '),
       tuple('n', '\n'),
       tuple('r', '\r'),
       tuple('t', '\t'),
       tuple('\\', '\\')
    ];
    return doUnescape(value, pairs);
}

string unescapeExec(string str) @trusted nothrow pure
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
 * This class represents the group in the desktop file. 
 * You can create and use instances of this class only in the context of $(B DesktopFile) instance.
 */
final class DesktopGroup
{
private:
    static struct Line
    {
        enum Type
        {
            None, 
            Comment, 
            KeyValue
        }
        
        this(string comment) @safe {
            _first = comment;
            _type = Type.Comment;
        }
        
        this(string key, string value) @safe {
            _first = key;
            _second = value;
            _type = Type.KeyValue;
        }
        
        string comment() @safe @nogc nothrow const {
            return _first;
        }
        
        string key() @safe @nogc nothrow const {
            return _first;
        }
        
        string value() @safe @nogc nothrow const {
            return _second;
        }
        
        Type type() @safe @nogc nothrow const {
            return _type;
        }
        
        void makeNone() @safe @nogc nothrow {
            _type = Type.None;
        }
        
    private:
        Type _type = Type.None;
        string _first;
        string _second;
    }
    
    this(string name) @safe @nogc nothrow {
        _name = name;
    }
    
public:
    
    /**
     * Returns: the value associated with the key
     * Note: it's an error to access nonexistent value
     */
    string opIndex(string key) const @safe @nogc nothrow {
        auto i = key in _indices;
        assert(_values[*i].type == Line.Type.KeyValue);
        assert(_values[*i].key == key);
        return _values[*i].value;
    }
    
    /**
     * Inserts new value or replaces the old one if value associated with key already exists.
     * Returns: inserted/updated value
     * Throws: $(B Exception) if key is not valid
     * See_Also: isValidKey
     */
    string opIndexAssign(string value, string key) @safe {
        enforce(separateFromLocale(key)[0].isValidKey(), "key contains invalid characters");
        auto pick = key in _indices;
        if (pick) {
            return (_values[*pick] = Line(key, value)).value;
        } else {
            _indices[key] = _values.length;
            _values ~= Line(key, value);
            return value;
        }
    }
    /**
     * Ditto, but also allows to specify the locale.
     * See_Also: setLocalizedValue, localizedValue
     */
    string opIndexAssign(string value, string key, string locale) @safe {
        string keyName = localizedKey(key, locale);
        return this[keyName] = value;
    }
    
    /**
     * Tells if group contains value associated with the key.
     */
    bool contains(string key) const @safe @nogc nothrow {
        return value(key) !is null;
    }
    
    /**
     * Returns: the value associated with the key, or defaultValue if group does not contain item with this key.
     */
    string value(string key, string defaultValue = null) const @safe @nogc nothrow {
        auto pick = key in _indices;
        if (pick) {
            if(_values[*pick].type == Line.Type.KeyValue) {
                assert(_values[*pick].key == key);
                return _values[*pick].value;
            }
        }
        return defaultValue;
    }
    
    /**
     * Performs locale matching lookup as described in $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s04.html, Localized values for keys).
     * Returns: the localized value associated with key and locale, or defaultValue if group does not contain item with this key.
     */
    string localizedValue(string key, string locale, string defaultValue = null) const @safe nothrow {
        //Any ideas how to get rid of this boilerplate and make less allocations?
        auto t = parseLocaleName(locale);
        auto lang = t.lang;
        auto country = t.country;
        auto modifier = t.modifier;
        
        if (lang.length) {
            string pick;
            
            if (country.length && modifier.length) {
                pick = value(localizedKey(key, locale));
                if (pick !is null) {
                    return pick;
                }
            }
            
            if (country.length) {
                pick = value(localizedKey(key, lang, country));
                if (pick !is null) {
                    return pick;
                }
            }
            
            if (modifier.length) {
                pick = value(localizedKey(key, lang, null, modifier));
                if (pick !is null) {
                    return pick;
                }
            }
            
            pick = value(localizedKey(key, lang, null));
            if (pick !is null) {
                return pick;
            }
        }
        
        return value(key, defaultValue);
    }
    
    /**
     * Ditto, but uses the current locale.
     */
    string localizedValue(string key) const @safe nothrow {
        try {
            string locale = currentLocale();
            return localizedValue(key, locale);
        } catch(Exception e) {
            return value(key);
        }
    }
    
    /**
     * Same as localized version of opIndexAssign, but uses function syntax.
     */
    void setLocalizedValue(string key, string locale, string value) @safe {
        this[key, locale] = value;
    }
    
    /**
     * Removes entry by key. To remove localized values use localizedKey.
     */
    void removeEntry(string key) @safe nothrow {
        auto pick = key in _indices;
        if (pick) {
            _values[*pick].makeNone();
        }
    }
    
    /**
     * Returns: range of Tuple!(string, "key", string, "value")
     */
    auto byKeyValue() const @safe @nogc nothrow {
        return _values.filter!(v => v.type == Line.Type.KeyValue).map!(v => KeyValueTuple(v.key, v.value));
    }
    
    /**
     * Returns: the name of group
     */
    string name() const @safe @nogc nothrow {
        return _name;
    }
    
private:
    void addComment(string comment) {
        _values ~= Line(comment);
    }
    
    size_t[string] _indices;
    Line[] _values;
    string _name;
}

/**
 * Represents .desktop file.
 * 
 */
final class DesktopFile
{
public:
    enum Type
    {
        Unknown, ///Desktop entry is unknown type
        Application, ///Desktop describes application
        Link, ///Desktop describes URL
        Directory ///Desktop entry describes directory settings
    }
    
    enum ReadOptions
    {
        noOptions = 0, /// Read all groups and skip comments and empty lines
        desktopEntryOnly = 1, /// Ignore other groups than Desktop Entry
        preserveComments = 2 /// Preserve comments and empty lines
    }
    
    /**
     * Reads desktop file from file.
     * Throws:
     *  $(B ErrnoException) if file could not be opened.
     *  $(B DesktopFileException) if error occured while reading the file.
     */
    static DesktopFile loadFromFile(string fileName, ReadOptions options = ReadOptions.noOptions) @trusted {
        auto f = File(fileName, "r");
        return new DesktopFile(f.byLine().map!(s => s.idup), options, fileName);
    }
    
    /**
     * Reads desktop file from string.
     * Throws:
     *  $(B DesktopFileException) if error occured while parsing the contents.
     */
    static DesktopFile loadFromString(string contents, ReadOptions options = ReadOptions.noOptions, string fileName = null) @trusted {
        return new DesktopFile(contents.splitLines(), options, fileName);
    }
    
    private this(Range)(Range byLine, ReadOptions options, string fileName) @trusted
    {   
        size_t lineNumber = 0;
        string currentGroup;
        
        try {
            foreach(line; byLine) {
                lineNumber++;
                line = strip(line);
                
                if (line.empty || line.startsWith("#")) {
                    if (options & ReadOptions.preserveComments) {
                        if (currentGroup is null) {
                            firstLines ~= line;
                        } else {
                            group(currentGroup).addComment(line);
                        }
                    }
                    
                    continue;
                }
                
                if (line.startsWith("[") && line.endsWith("]")) {
                    string groupName = line[1..$-1];
                    enforce(groupName.length, "empty group name");
                    enforce(group(groupName) is null, "group is defined more than once");
                    
                    if (currentGroup is null) {
                        enforce(groupName == "Desktop Entry", "the first group must be Desktop Entry");
                    } else if (options & ReadOptions.desktopEntryOnly) {
                        break;
                    }
                    
                    addGroup(groupName);
                    currentGroup = groupName;
                } else {
                    auto t = line.findSplit("=");
                    
                    enforce(t[1].length, "not key-value pair, nor group start nor comment");
                    enforce(currentGroup.length, "met key-value pair before any group");
                    assert(group(currentGroup) !is null, "logic error: currentGroup is not in _groups");
                    
                    group(currentGroup)[t[0]] = t[2];
                }
            }
            
            _desktopEntry = group("Desktop Entry");
            enforce(_desktopEntry !is null, "Desktop Entry group is missing");
            _fileName = fileName;
        }
        catch (Exception e) {
            throw new DesktopFileException(e.msg, lineNumber, e.file, e.line, e.next);
        }
    }
    
    /**
     * Returns: file name as was specified on the object creating
     */
    string fileName() @safe @nogc nothrow const {
        return  _fileName;
    }
    
    /**
     * Saves object to file using Desktop File format.
     * Throws: ErrnoException if the file could not be opened or an error writing to the file occured.
     */
    void saveToFile(string fileName) const {
        auto f = File(fileName, "w");
        void dg(string line) {
            f.writeln(line);
        }
        save(&dg);
    }
    
    /**
     * Saves object to string using Desktop File format.
     */
    string saveToString() const {
        auto a = appender!(string[])();
        void dg(string line) {
            a.put(line);
        }
        save(&dg);
        return a.data.join("\n");
    }
    
    private alias SaveDelegate = void delegate(string);
    
    private void save(SaveDelegate sink) const {
        foreach(line; firstLines) {
            sink(line);
        }
        
        foreach(group; byGroup()) {
            sink("[" ~ group.name ~ "]");
            foreach(line; group._values) {
                if (line.type == DesktopGroup.Line.Type.Comment) {
                    sink(line.comment);
                } else if (line.type == DesktopGroup.Line.Type.KeyValue) {
                    sink(line.key ~ "=" ~ line.value);
                }
            }
        }
    }
    
    /**
     * Returns: DesktopGroup instance associated with groupName or $(B null) if not found.
     */
    inout(DesktopGroup) group(string groupName) @safe @nogc nothrow inout {
        auto pick = groupName in _groupIndices;
        if (pick) {
            return _groups[*pick];
        }
        return null;
    }
    
    /**
     * Creates new group usin groupName.
     * Returns: newly created instance of DesktopGroup.
     * Throws: Exception if group with such name already exists or groupName is empty.
     */
    DesktopGroup addGroup(string groupName) @safe {
        enforce(groupName.length, "group name is empty");
        
        auto desktopGroup = new DesktopGroup(groupName);
        enforce(group(groupName) is null, "group already exists");
        _groupIndices[groupName] = _groups.length;
        _groups ~= desktopGroup;
        
        return desktopGroup;
    }
    
    /**
     * Range of groups in order how they are defined in .desktop file. The first group is always $(B Desktop Entry).
     */
    auto byGroup() const {
        return _groups[];
    }
    
    /**
     * Returns: Type of desktop entry.
     */
    Type type() const @safe @nogc nothrow {
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
        if (_fileName.extension == ".directory") {
            return Type.Directory;
        }
        
        return Type.Unknown;
    }
    
    /**
     * Specific name of the application, for example "Mozilla".
     * Returns: the value associated with "Name" key.
     */
    string name() const @safe @nogc nothrow {
        return value("Name");
    }
    ///ditto, but returns localized value using current locale.
    string localizedName() const @safe nothrow {
        return localizedValue("Name");
    }
    
    /**
     * Generic name of the application, for example "Web Browser".
     * Returns: the value associated with "GenericName" key.
     */
    string genericName() const @safe @nogc nothrow {
        return value("GenericName");
    }
    ///ditto, but returns localized value using current locale.
    string localizedGenericName() const @safe nothrow {
        return localizedValue("GenericName");
    }
    
    /**
     * Tooltip for the entry, for example "View sites on the Internet".
     * Returns: the value associated with "Comment" key.
     */
    string comment() const @safe @nogc nothrow {
        return value("Comment");
    }
    ///ditto, but returns localized value using current locale.
    string localizedComment() const @safe nothrow {
        return localizedValue("Comment");
    }
    
    /** 
     * Returns: the value associated with "Exec" key.
     * Note: don't use this to start the program. Consider using expandExecString or startApplication instead.
     */
    string execString() const @safe @nogc nothrow {
        return value("Exec");
    }
    
    
    /**
     * Returns: the value associated with "TryExec" key.
     */
    string tryExecString() const @safe @nogc nothrow {
        return value("TryExec");
    }
    
    /**
     * Returns: the value associated with "Icon" key. If not found it also tries "X-Window-Icon".
     * Note: this function returns Icon as it's defined in .desktop file. It does not provides any lookup of actual icon file on the system.
     */
    string iconName() const @safe @nogc nothrow {
        string iconPath = value("Icon");
        if (iconPath is null) {
            iconPath = value("X-Window-Icon");
        }
        return iconPath;
    }
    
    /**
     * Returns: the value associated with "NoDisplay" key converted to bool using isTrue.
     */
    bool noDisplay() const @safe @nogc nothrow {
        return isTrue(value("NoDisplay"));
    }
    
    /**
     * Returns: the value associated with "Hidden" key converted to bool using isTrue.
     */
    bool hidden() const @safe @nogc nothrow {
        return isTrue(value("Hidden"));
    }
    
    /**
     * The working directory to run the program in.
     * Returns: the value associated with "Path" key.
     */
    string workingDirectory() const @safe @nogc nothrow {
        return value("Path");
    }
    
    /**
     * Whether the program runs in a terminal window.
     * Returns: the value associated with "Hidden" key converted to bool using isTrue.
     */
    bool terminal() const @safe @nogc nothrow {
        return isTrue(value("Terminal"));
    }
    
    /**
     * Some keys can have multiple values, separated by semicolon. This function helps to parse such kind of strings to the range.
     * Returns: the range of multiple values.
     */
    static auto splitValues(string values) @trusted {
        static bool notEmpty(string s) @nogc nothrow { return s.length != 0; }
        
        return values.splitter(';').filter!notEmpty;
    }
    
    /**
     * Categories this program belongs to.
     * Returns: the range of multiple values associated with "Categories" key.
     */
    auto categories() const @safe {
        return splitValues(value("Categories"));
    }
    
    /**
     * A list of strings which may be used in addition to other metadata to describe this entry.
     * Returns: the range of multiple values associated with "Keywords" key.
     */
    auto keywords() const @safe {
        return splitValues(value("Keywords"));
    }
    
    /**
     * Returns: instance of "Desktop Entry" group.
     */
    inout(DesktopGroup) desktopEntry() @safe @nogc nothrow inout {
        return _desktopEntry;
    }
    
    
    /**
     * This alias allows to call functions related to "Desktop Entry" group without need to call desktopEntry explicitly.
     */
    alias desktopEntry this;
    
    /**
     * Expands Exec string into the array of command line arguments to use to start the program.
     */
    string[] expandExecString(in string[] urls = null) const @safe
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
     * Starts the program associated with this .desktop file using urls as command line params.
     * Note: 
     *  If the program should be run in terminal it tries to find system defined terminal emulator to run in.
     *  First, it probes $(B TERM) environment variable. If not found, checks if /usr/bin/x-terminal-emulator exists on Linux and use it on success.
     *  Defaulted to xterm, if could not determine other terminal emulator.
     * Note:
     *  This function does check if the type of desktop file is Application. It relies only on "Exec" value.
     * Returns:
     *  Pid of started process.
     * Throws:
     *  ProcessException on failure to start the process.
     *  Exception if expanded exec string is empty.
     */
    Pid startApplication(string[] urls = null) const @trusted
    {
        auto args = expandExecString(urls);
        enforce(args.length, "No command line params to run the program. Is Exec missing?");
        
        if (terminal()) {
            string term = environment.get("TERM");
            
            version(linux) {
                if (term is null) {
                    string debianTerm = "/usr/bin/x-terminal-emulator";
                    if (debianTerm.exists) {
                        term = debianTerm;
                    }
                }
            }
            
            if (term is null) {
                term = "xterm";
            }
            
            args = [term, "-e"] ~ args;
        }
        
        return spawnProcess(args, null, Config.none, workingDirectory());
    }
    
    ///ditto, but uses the only url.
    Pid startApplication(in string url) const @trusted
    {
        return startApplication([url]);
    }
    
    Pid startLink() const @trusted
    {
        string url = value("URL");
        return spawnProcess(["xdg-open", url], null, Config.none);
    }
    
private:
    DesktopGroup _desktopEntry;
    string _fileName;
    
    size_t[string] _groupIndices;
    DesktopGroup[] _groups;
    
    string[] firstLines;
}

unittest 
{
    //Test locale-related functions
    assert(makeLocaleName("ru", "RU") == "ru_RU");
    assert(makeLocaleName("ru", "RU", "UTF-8") == "ru_RU.UTF-8");
    assert(makeLocaleName("ru", "RU", "UTF-8", "mod") == "ru_RU.UTF-8@mod");
    assert(makeLocaleName("ru", null, null, "mod") == "ru@mod");
    
    assert(parseLocaleName("ru_RU.UTF-8@mod") == tuple("ru", "RU", "UTF-8", "mod"));
    assert(parseLocaleName("ru@mod") == tuple("ru", string.init, string.init, "mod"));
    assert(parseLocaleName("ru_RU") == tuple("ru", "RU", string.init, string.init));
    
    assert(localizedKey("Name", "ru_RU") == "Name[ru_RU]");
    assert(localizedKey("Name", "ru_RU.UTF-8") == "Name[ru_RU]");
    assert(localizedKey("Name", "ru", "RU") == "Name[ru_RU]");
    
    assert(separateFromLocale("Name[ru_RU]") == tuple("Name", "ru_RU"));
    assert(separateFromLocale("Name") == tuple("Name", string.init));
    
    //Test locale matching lookup
    auto group = new DesktopGroup("Desktop Entry");
    group["Name"] = "Programmer";
    group["Name[ru_RU]"] = "Разработчик";
    group["Name[ru@jargon]"] = "Кодер";
    group["Name[ru]"] = "Программист";
    group["GenericName"] = "Program";
    group["GenericName[ru]"] = "Программа";
    assert(group["Name"] == "Programmer");
    assert(group.localizedValue("Name", "ru@jargon") == "Кодер");
    assert(group.localizedValue("Name", "ru_RU@jargon") == "Разработчик");
    assert(group.localizedValue("Name", "ru") == "Программист");
    assert(group.localizedValue("Name", "nonexistent locale") == "Programmer");
    assert(group.localizedValue("GenericName", "ru_RU") == "Программа");
    
    //Test escaping and unescaping
    assert("\\next\nline".escapeValue() == `\\next\nline`);
    assert(`\\next\nline`.unescapeValue() == "\\next\nline");
    
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
    
    auto df = DesktopFile.loadFromString(desktopFileContents, DesktopFile.ReadOptions.preserveComments);
    assert(df.name() == "Double Commander");
    assert(df.genericName() == "File manager");
    assert(df.localizedValue("GenericName", "ru_RU") == "Файловый менеджер");
    assert(!df.terminal());
    assert(df.type() == DesktopFile.Type.Application);
    assert(equal(df.categories(), ["Application", "Utility", "FileManager"]));
    
    assert(df.saveToString() == desktopFileContents);
}
