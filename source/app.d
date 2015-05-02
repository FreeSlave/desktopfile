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

string currentLocale() @safe
{
    return environment.get("LC_CTYPE", environment.get("LC_ALL", environment.get("LANG")));
}

string makeLocaleName(string lang, string country = null, string encoding = null, string modifier = null) pure nothrow @trusted
{
    return lang ~ (country.length ? "_"~country : "") ~ (encoding.length ? "."~encoding : "") ~ (modifier.length ? "@"~modifier : "");
}

Tuple!(string, string, string, string) parseLocaleName(string locale) pure nothrow @nogc @trusted
{
    auto modifiderSplit = findSplit(locale, "@");
    auto modifier = modifiderSplit[2];
    
    auto encodongSplit = findSplit(modifiderSplit[0], ".");
    auto encoding = encodongSplit[2];
    
    auto countrySplit = findSplit(encodongSplit[0], "_");
    auto country = countrySplit[2];
    
    auto lang = countrySplit[0];
    
    return tuple(lang, country, encoding, modifier);
}

string localizedKey(string key, string locale) pure nothrow @safe
{
    auto t = parseLocaleName(locale);
    if (!t[2].empty) {
        locale = makeLocaleName(t[0], t[1], null, t[3]);
    }
    return key ~ "[" ~ locale ~ "]";
}

string localizedKey(string key, string lang, string country, string modifier = null) pure nothrow @safe
{
    return key ~ "[" ~ makeLocaleName(lang, country, null, modifier) ~ "]";
}

/** Separates key name into non-localized key and locale name.
 *  If key is not localized returns original key and empty string.
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

private bool isValidKeyChar(char c) pure nothrow @nogc @safe
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-';
}

private bool isValidKey(string key) pure nothrow @nogc @safe
{
    for (size_t i = 0; i<key.length; ++i) {
        if (!key[i].isValidKeyChar()) {
            return false;
        }
    }
    return true;
}

private bool isTrue(string value) pure nothrow @nogc @safe {
    return (value == "true" || value == "1");
}

private bool isFalse(string value) pure nothrow @nogc @safe {
    return (value == "false" || value == "0");
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

class DesktopGroup
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
    
public:
    string opIndex(string key) const @safe @nogc nothrow {
        auto i = key in _indices;
        assert(_values[*i].type == Line.Type.KeyValue);
        assert(_values[*i].key == key);
        return _values[*i].value;
    }
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
    string opIndexAssign(string value, string key, string locale) @safe {
        string keyName = localizedKey(key, locale);
        return this[keyName] = value;
    }
    
    bool contains(string key) const @safe @nogc nothrow {
        return value(key) !is null;
    }
    
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
    
    string localizedValue(string key, string locale, string defaultValue = null) const @safe nothrow {
        //Any ideas how to get rid of this boilerplate and make less allocations?
        auto t = parseLocaleName(locale);
        auto lang = t[0];
        auto country = t[1];
        auto modifier = t[3];
        
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
    
    string localizedValue(string key) const @safe nothrow {
        try {
            string locale = currentLocale();
            return localizedValue(key, locale);
        } catch(Exception e) {
            return value(key);
        }
    }
    
    void setLocalizedValue(string key, string locale, string value) @safe {
        this[key, locale] = value;
    }
    
    void removeEntry(string key) @safe nothrow {
        auto pick = key in _indices;
        if (pick) {
            _values[*pick].makeNone();
        }
    }
    
    auto byKeyValue() const @safe @nogc nothrow {
        return _values.filter!(v => v.type == Line.Type.KeyValue).map!(v => tuple(v.key, v.value));
    }
    
private:
    void addComment(string comment) {
        _values ~= Line(comment);
    }
    
    size_t[string] _indices;
    Line[] _values;
}

class DesktopFile
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
     * Reads desktop file from file
     * Throws:
     *  $(B ErrnoException) if file could not be opened
     *  $(B DesktopFileException) if error occured while reading the file
     */
    static DesktopFile loadFromFile(string fileName, ReadOptions options = ReadOptions.noOptions) @trusted {
        auto f = File(fileName, "r");
        return new DesktopFile(f.byLine().map!(s => s.idup), options, fileName);
    }
    
    /**
     * Reads desktop file from string
     * Throws:
     *  $(B DesktopFileException) if error occured while parsing the contents
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
    
    void save(string fileName) const {
        throw new Exception("Savind to file is not implemented yet");
    }
    string save() const {
        throw new Exception("Saving to string is not implemented yet");
    }
    
    inout(DesktopGroup) group(string groupName) @safe @nogc nothrow inout {
        auto pick = groupName in _groupIndices;
        if (pick) {
            return _groups[*pick].group;
        }
        return null;
    }
    
    void addGroup(string groupName, DesktopGroup desktopGroup) @safe nothrow {
        assert(groupName.length && desktopGroup !is null);
        
        auto pick = group(groupName);
        if (pick is null) {
            _groupIndices[groupName] = _groups.length;
            _groups ~= GroupPair(groupName, desktopGroup);
        }
    }
    
    void addGroup(string groupName) @safe nothrow {
        addGroup(groupName, new DesktopGroup);
    }
    
    auto byGroup() const {
        return _groups[];
    }
    
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
    
    string name() const @safe @nogc nothrow {
        return value("Name");
    }
    string localizedName(string locale) const @safe nothrow {
        return localizedValue("Name", locale);
    }
    
    string genericName() const @safe @nogc nothrow {
        return value("GenericName");
    }
    string localizedGenericName(string locale) const @safe nothrow {
        return localizedValue("GenericName", locale);
    }
    
    string comment() const @safe @nogc nothrow {
        return value("Comment");
    }
    string localizedComment(string locale) const @safe nothrow {
        return localizedValue("Comment", locale);
    }
    
    string exec() const @safe @nogc nothrow {
        return value("Exec");
    }
    
    string tryExec() const @safe @nogc nothrow {
        return value("TryExec");
    }
    
    string iconName() const @safe @nogc nothrow {
        string iconPath = value("Icon");
        if (iconPath is null) {
            iconPath = value("X-Window-Icon");
        }
        return iconPath;
    }
    
    bool noDisplay() const @safe @nogc nothrow {
        return isTrue(value("NoDisplay"));
    }
    
    bool hidden() const @safe @nogc nothrow {
        return isTrue(value("Hidden"));
    }
    
    string workingDirectory() const @safe @nogc nothrow {
        return value("Path");
    }
    
    bool terminal() const @safe @nogc nothrow {
        return isTrue(value("Terminal"));
    }
    
    private static auto splitValues(string values) @trusted {
        static bool notEmpty(string s) @nogc nothrow { return s.length != 0; }
        
        return values.splitter(';').filter!notEmpty;
    }
    
    auto categories() const @safe {
        return splitValues(value("Categories"));
    }
    
    auto mimeTypes() const @safe {
        return splitValues(value("MimeTypes"));
    }
    
    inout(DesktopGroup) desktopEntry() @safe @nogc nothrow inout {
        return _desktopEntry;
    }
    alias _desktopEntry this;
    
    
    string[] expandExecString(in string[] urls = null) const @safe 
    {
        if (type() != Type.Application) {
            return null;
        }
        
        string[] toReturn;
        auto execStr = exec().unescapeExec(); //add unquoting
        
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
    
    void startApplication(string[] urls = null) const @safe
    {
        auto args = expandExecString(urls);
        if (args.empty || type() != Type.Application) {
            return;
        }
        
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
        
        spawnProcess(args, null, Config.none, workingDirectory());
    }
    
private:
    struct GroupPair {
        string name;
        DesktopGroup group;
    }
    
    DesktopGroup _desktopEntry;
    string _fileName;
    
    size_t[string] _groupIndices;
    GroupPair[] _groups;
    
    string[] firstLines;
}

unittest 
{
    assert(makeLocaleName("ru", "RU") == "ru_RU");
    assert(makeLocaleName("ru", "RU", "UTF-8") == "ru_RU.UTF-8");
    assert(makeLocaleName("ru", "RU", "UTF-8", "mod") == "ru_RU.UTF-8@mod");
    assert(makeLocaleName("ru", null, null, "mod") == "ru@mod");
    
    assert(parseLocaleName("ru_RU.UTF-8@mod") == tuple("ru", "RU", "UTF-8", "mod"));
    assert(parseLocaleName("ru@mod") == tuple("ru", string.init, string.init, "mod"));
    
    assert(localizedKey("Name", "ru_RU") == "Name[ru_RU]");
    assert(localizedKey("Name", "ru_RU.UTF-8") == "Name[ru_RU]");
    assert(localizedKey("Name", "ru", "RU") == "Name[ru_RU]");
    
    assert(separateFromLocale("Name[ru_RU]") == tuple("Name", "ru_RU"));
    assert(separateFromLocale("Name") == tuple("Name", string.init));
    
    
    auto group = new DesktopGroup;
    group["Name"] = "Programmer";
    group["Name[ru_RU]"] = "Разработчик";
    group["Name[ru@jargon]"] = "Кодер";
    group["Name[ru]"] = "Программист";
    
    assert(group["Name"] == "Programmer");
    assert(group.localizedValue("Name", "ru@jargon") == "Кодер");
    assert(group.localizedValue("Name", "ru_RU@jargon") == "Разработчик");
    assert(group.localizedValue("Name", "ru") == "Программист");
    assert(group.localizedValue("Name", "unexesting locale") == "Programmer");
    
    assert("\\next\nline".escapeValue() == `\\next\nline`);
    
    assert(`\\next\nline`.unescapeValue() == "\\next\nline");
}

void main(string[] args)
{
    if (args.length < 3) {
        writefln("Usage: %s <read|exec> <desktop-file>", args[0]);
        return;
    }
    
    auto df = DesktopFile.loadFromFile(args[2]);
    if (args[1] == "read") {
        foreach(group; df.byGroup()) {
            writefln("[%s]", group.name);
            foreach(t; group.group.byKeyValue()) {
                writefln("%s : %s", t[0], t[1]);
            }
        }
    } else if (args[1] == "exec") {
        writeln("Exec:", df.expandExecString());
        df.startApplication();
    }
}
