module desktopfile.isfreedesktop;

version(OSX) {
    enum isFreedesktop = false;
} else version(Android) {
    enum isFreedesktop = false;
} else version(Posix) {
    enum isFreedesktop = true;
} else {
    enum isFreedesktop = false;
}
