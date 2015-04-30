module desktopfile;

private {
    import std.algorithm : findSplit, splitter, equal;
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

auto makeLocaleNameChain(string lang, string country = null, string encoding = null, string modifier = null) pure @trusted
{
    return chain(lang, country.length ? "_" : string.init, country.toUpper(), 
                 encoding.length ? "." : string.init, encoding.toUpper(), 
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

string localizedKeyName(string key, string locale) nothrow @safe
{
    return key ~ "[" ~ locale ~ "]";
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

private string lookupLocalizedKey(const(string[string]) entries, string key, string locale, lazy string defaultValue = null)
{
    auto t = parseLocaleName(locale);
    auto lang = t[0];
    auto country = t[1];
    auto modifier = t[3];
    
    if (lang.length) {
        const(string)* pick;
        
        if (country.length && modifier.length) {
            pick = localizedKeyName(key, makeLocaleName(lang, country, null, modifier)) in entries;
            if (pick) {
                return *pick;
            }
        }
        
        if (country.length) {
            pick = localizedKeyName(key, makeLocaleName(lang, country)) in entries;
            if (pick) {
                return *pick;
            }
        }
        
        if (modifier.length) {
            pick = localizedKeyName(key, makeLocaleName(lang, null, null, modifier)) in entries;
            if (pick) {
                return *pick;
            }
        }
        
        pick = localizedKeyName(key, makeLocaleName(lang)) in entries;
        if (pick) {
            return *pick;
        }
    }
    
    return entries.get(key, defaultValue);
}

struct DesktopGroup
{
public:
    string opIndex(string key) const {
        return _entries[key];
    }
    string opIndexAssign(string value, string key) {
        return _entries[key] = value;
    }
    
    string value(string key, lazy string defaultValue = null) const {
        return _entries.get(key, defaultValue);
    }
    
    string localizedValue(string key, string locale, lazy string defaultValue = null) const {
        return lookupLocalizedKey(_entries, key, locale, defaultValue);
    }
    
    void setLocalizedValue(string key, string locale, string value) {
        string localizedKey = localizedKeyName(key, locale);
        _entries[localizedKey] = value;
    }
    
    void removeEntry(string key) {
        _entries.remove(key);
    }
    
    auto byKey() {
        return _entries.byKey();
    }
    
private:
    string[string] _entries;
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
        noOptions, 
        desktopEntryOnly, /// Ignore other groups than Desktop Entry
        preserveComments /// Preserve comments and empty strings
    }
    
    this(string fileName)
    {
        auto f = File(fileName, "r");
        
        
        string currentGroup;
        foreach(sline; f.byLine()) {
            string line = sline.idup;
            line = stripLeft(line);
            
            if (line.startsWith("#")) {
                continue;
            }
            
            if (line.startsWith("[") && line.endsWith("]")) {
                string groupName = line[1..$-1];
                enforce(groupName.length, "empty group name");
                enforce(groupName !in _groups, "group is defined more than once");
                
                if (currentGroup is null) {
                    enforce(groupName == "Desktop Entry", "the first group must be Desktop Entry");
                }
                
                _groups[groupName] = DesktopGroup();
                currentGroup = groupName;
            } else {
                auto t = line.findSplit("=");
                
                enforce(t[1].length, "not key-value pair, nor group start nor comment");
                enforce(currentGroup.length, "met key-value pair before any group");
                assert(currentGroup in _groups, "logic error: currentGroup is not in _groups");
                
                _groups[currentGroup][t[0]] = t[2];
            }
        }
        
        _desktopEntry = "Desktop Entry" in _groups;
        enforce(_desktopEntry, "Desktop Entry group is missing");
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
        string t = _desktopEntry.value("Type");
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
        return _desktopEntry.value("Name");
    }
    string localizedName(string locale) const {
        return _desktopEntry.localizedValue("Name", locale);
    }
    
    string genericName() const {
        return _desktopEntry.value("GenericName");
    }
    string localizedGenericName(string locale) const {
        return _desktopEntry.localizedValue("GenericName", locale);
    }
    
    string comment() const {
        return _desktopEntry.value("Comment");
    }
    string localizedComment(string locale) const {
        return _desktopEntry.localizedValue("Comment", locale);
    }
    
    string icon() const {
        string iconPath = _desktopEntry.value("Icon");
        if (iconPath is null) {
            iconPath = _desktopEntry.value("X-Window-Icon");
        }
        return iconPath;
    }
    
    bool noDisplay() const {
        return isTrue(_desktopEntry.value("NoDisplay"));
    }
    
    bool hidden() const {
        return isTrue(_desktopEntry.value("Hidden"));
    }
    
    string workingDirectory() const {
        return _desktopEntry.value("Path");
    }
    
    bool terminal() const {
        return isTrue(_desktopEntry.value("Terminal"));
    }
    
    auto categories() const {
        return _desktopEntry.value("Categories").splitter(';');
    }
    
    auto mimeTypes() const {
        return _desktopEntry.value("MimeTypes").splitter(';');
    }
    
    inout(DesktopGroup)* desktopEntry() inout {
        return _desktopEntry;
    }
    alias _desktopEntry this;
private:
    DesktopGroup* _desktopEntry;
    string _fileName;
    DesktopGroup[string] _groups;
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
    
    assert(localizedKeyName("Name", "ru_RU") == "Name[ru_RU]");
    
    assert(separateFromLocale("Name[ru_RU]") == tuple("Name", "ru_RU"));
    assert(separateFromLocale("Name") == tuple("Name", string.init));
    
    
    string[string] entries = [ 
        "Name" : "Programmer", 
        "Name[ru_RU]" : "Разработчик", 
        "Name[ru@jargon]" : "Кодер", 
        "Name[ru]" : "Программирование" 
    ];
    
    assert(lookupLocalizedKey(entries, "Name", "ru_RU@jargon") == "Разработчик");
}

void main(string[] args)
{
    if (args.length < 2) {
        writefln("Usage: %s <desktop-file>", args[0]);
        return;
    }
    auto df = new DesktopFile(args[1]);
    foreach(key; df.byKey()) {
        writeln(key);
    }
}
