module desktopfile;

private {
    import std.algorithm;
    import std.array;
    import std.conv;
    import std.exception;
    import std.path;
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

auto makeLocaleNameChain(string lang, string country = null, string encoding = null, string modifier = null) pure nothrow @nogc @trusted
{
    return chain(lang, country.length ? "_" : string.init, country, 
                 encoding.length ? "." : string.init, encoding, 
                 modifier.length ? "@" : string.init, modifier);
}

string makeLocaleName(string lang, string country = null, string encoding = null, string modifier = null) pure @trusted
{
    return to!string(makeLocaleNameChain(lang, country, encoding, modifier));
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
    return key ~ "[" ~ locale ~ "]";
}

string localizedKey(string key, string lang, string country, string modifier = null) pure @safe
{
    return key ~ "[" ~ makeLocaleName(lang, country, modifier) ~ "]";
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

private bool isTrue(string str) pure nothrow @nogc @safe {
    return (str == "true" || str == "1");
}

private bool isFalse(string str) pure nothrow @nogc @safe {
    return (str == "false" || str == "0");
}

struct DesktopGroup
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
        
        this(string comment) {
            _first = comment;
            _type = Type.Comment;
        }
        
        this(string key, string value) {
            _first = key;
            _second = value;
            _type = Type.KeyValue;
        }
        
        string comment() const {
            return _first;
        }
        
        string key() const {
            return _first;
        }
        
        string value() const {
            return _second;
        }
        
        Type type() const {
            return _type;
        }
        
        void makeNone() {
            _type = Type.None;
        }
        
    private:
        Type _type = Type.None;
        string _first;
        string _second;
    }
    
public:
    string opIndex(string key) const {
        size_t i = _indices[key];
        assert(i < _values.length);
        assert(_values[i].type == Line.Type.KeyValue);
        
        return _values[i].value;
    }
    string opIndexAssign(string value, string key) {
        auto pick = key in _indices;
        if (pick) {
            assert(_values[*pick].type == Line.Type.KeyValue);
            return (_values[*pick] = Line(key, value)).value;
        } else {
            _indices[key] = _values.length;
            _values ~= Line(key, value);
            return value;
        }
    }
    
    string value(string key, lazy string defaultValue = null) const {
        auto pick = key in _indices;
        if (pick) {
            assert(_values[*pick].type == Line.Type.KeyValue);
            return _values[*pick].value;
        } else {
            return defaultValue();
        }
    }
    
    string localizedValue(string key, string locale, lazy string defaultValue = null) const {
        //Any ideas how to get rid of this boilerplate and make less allocations?
        auto t = parseLocaleName(locale);
        auto lang = t[0];
        auto country = t[1];
        auto modifier = t[3];
        
        if (lang.length) {
            string pick;
            
            if (country.length && modifier.length) {
                pick = value(localizedKey(key, makeLocaleName(lang, country, null, modifier)));
                if (pick !is null) {
                    return pick;
                }
            }
            
            if (country.length) {
                pick = value(localizedKey(key, makeLocaleName(lang, country)));
                if (pick !is null) {
                    return pick;
                }
            }
            
            if (modifier.length) {
                pick = value(localizedKey(key, makeLocaleName(lang, null, null, modifier)));
                if (pick !is null) {
                    return pick;
                }
            }
            
            pick = value(localizedKey(key, makeLocaleName(lang)));
            if (pick !is null) {
                return pick;
            }
        }
        
        return value(key, defaultValue);
    }
    
    void setLocalizedValue(string key, string locale, string value) {
        auto t = parseLocaleName(locale);
        string keyName = localizedKey(key, makeLocaleName(t[0], t[1], null, t[2]));
        this[keyName] = value;
    }
    
    void removeEntry(string key) {
        auto pick = key in _indices;
        if (pick) {
            assert(_values[*pick].type == Line.Type.KeyValue);
            _indices.remove(key);
            _values[*pick].makeNone();
        }
    }
    
    auto byKeyValue() const {
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
        noOptions = 0, 
        desktopEntryOnly = 1, /// Ignore other groups than Desktop Entry
        preserveComments = 2 /// Preserve comments and empty strings
    }
    
    static DesktopFile loadFromFile(string fileName, ReadOptions options = ReadOptions.noOptions) {
        auto f = File(fileName, "r");
        return new DesktopFile(f.byLine().map!(s => s.idup), options, fileName);
    }
    
    static DesktopFile loadFromString(string contents, ReadOptions options = ReadOptions.noOptions, string fileName = null) {
        return new DesktopFile(contents.splitLines(), options, fileName);
    }
    
    private this(Range)(Range byLine, ReadOptions options, string fileName)
    {   
        size_t lineNumber = 0;
        string currentGroup;
        foreach(line; byLine) {
            lineNumber++;
            line = strip(line);
            
            if (line.empty || line.startsWith("#")) {
                if (options & ReadOptions.preserveComments) {
                    if (currentGroup is null) {
                        firstLines ~= line;
                    } else {
                        _groups[currentGroup].addComment(line);
                    }
                }
                
                continue;
            }
            
            if (line.startsWith("[") && line.endsWith("]")) {
                string groupName = line[1..$-1];
                enforce(groupName.length, new DesktopFileException("empty group name", lineNumber));
                enforce(groupName !in _groups, new DesktopFileException("group is defined more than once", lineNumber));
                
                if (currentGroup is null) {
                    enforce(groupName == "Desktop Entry", new DesktopFileException("the first group must be Desktop Entry", lineNumber));
                } else if (options & ReadOptions.desktopEntryOnly) {
                    break;
                }
                
                _groups[groupName] = DesktopGroup();
                currentGroup = groupName;
            } else {
                auto t = line.findSplit("=");
                
                enforce(t[1].length, new DesktopFileException("not key-value pair, nor group start nor comment", lineNumber));
                enforce(currentGroup.length, new DesktopFileException("met key-value pair before any group", lineNumber));
                assert(currentGroup in _groups, "logic error: currentGroup is not in _groups");
                
                _groups[currentGroup][t[0]] = t[2];
            }
        }
        
        _desktopEntry = "Desktop Entry" in _groups;
        enforce(_desktopEntry, "Desktop Entry group is missing");
        _fileName = fileName;
    }
    
    void save(string fileName) const {
        throw new Exception("Savind to file is not implemented yet");
    }
    string save() const {
        throw new Exception("Saving to string is not implemented yet");
    }
    
    inout(DesktopGroup)* group(string groupName) inout {
        return groupName in _groups;
    }
    
    Type type() const {
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
    
    string name() const {
        return value("Name");
    }
    string localizedName(string locale) const {
        return localizedValue("Name", locale);
    }
    
    string genericName() const {
        return value("GenericName");
    }
    string localizedGenericName(string locale) const {
        return localizedValue("GenericName", locale);
    }
    
    string comment() const {
        return value("Comment");
    }
    string localizedComment(string locale) const {
        return localizedValue("Comment", locale);
    }
    
    string exec() const {
        return value("Exec");
    }
    
    string tryExec() const {
        return value("TryExec");
    }
    
    string icon() const {
        string iconPath = value("Icon");
        if (iconPath is null) {
            iconPath = value("X-Window-Icon");
        }
        return iconPath;
    }
    
    bool noDisplay() const {
        return isTrue(value("NoDisplay"));
    }
    
    bool hidden() const {
        return isTrue(value("Hidden"));
    }
    
    string workingDirectory() const {
        return value("Path");
    }
    
    bool terminal() const {
        return isTrue(value("Terminal"));
    }
    
    private static auto splitValues(string values) {
        return values.splitter(';').filter!(s => s.length);
    }
    
    auto categories() const {
        return splitValues(value("Categories"));
    }
    
    auto mimeTypes() const {
        return splitValues(value("MimeTypes"));
    }
    
    inout(DesktopGroup)* desktopEntry() inout {
        return _desktopEntry;
    }
    alias _desktopEntry this;
private:
    DesktopGroup* _desktopEntry;
    string _fileName;
    DesktopGroup[string] _groups;
    
    string[] firstLines;
}

unittest 
{
    assert(makeLocaleName("ru", "RU") == "ru_RU");
    assert(makeLocaleName("ru", "RU", "UTF-8") == "ru_RU.UTF-8");
    assert(makeLocaleName("ru", "RU", "UTF-8", "mod") == "ru_RU.UTF-8@mod");
    assert(makeLocaleName("ru", null, null, "mod") == "ru@mod");
    
    assert(equal(makeLocaleNameChain("ru", "RU", "UTF-8", "mod"), "ru_RU.UTF-8@mod"));
    
    assert(parseLocaleName("ru_RU.UTF-8@mod") == tuple("ru", "RU", "UTF-8", "mod"));
    assert(parseLocaleName("ru@mod") == tuple("ru", string.init, string.init, "mod"));
    
    assert(localizedKey("Name", "ru_RU") == "Name[ru_RU]");
    assert(localizedKey("Name", "ru", "RU") == "Name[ru_RU");
    
    assert(separateFromLocale("Name[ru_RU]") == tuple("Name", "ru_RU"));
    assert(separateFromLocale("Name") == tuple("Name", string.init));
    
    
    DesktopGroup group;
    group["Name"] = "Programmer";
    group["Name[ru_RU]"] = "Разработчик";
    group["Name[ru@jargon]"] = "Кодер";
    group["Name[ru]"] = "Программист";
    
    assert(group["Name"] == "Programmer");
    assert(group.localizedValue("Name", "ru@jargon") == "Кодер");
    assert(group.localizedValue("Name", "ru_RU@jargon") == "Разработчик");
    assert(group.localizedValue("Name", "ru") == "Программист");
    assert(group.localizedValue("Name", "unexesting locale") == "Programmer");
}

void main(string[] args)
{
    if (args.length < 2) {
        writefln("Usage: %s <desktop-file>", args[0]);
        return;
    }
    auto df = DesktopFile.loadFromFile(args[1]);
    foreach(t; df.byKeyValue()) {
        writefln("%s : %s", t[0], t[1]);
    }
}
