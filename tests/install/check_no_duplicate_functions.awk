#!/usr/bin/awk -f
# Fail if any shell function is defined more than once in the input file(s).
# Matches both `name() {` and `function name[ ()] {` forms.

BEGIN {
    errors = 0
}

function function_name(line) {
    gsub(/^[ \t]+|[ \t]+$/, "", line)
    if (line ~ /^function[ \t]+/) {
        sub(/^function[ \t]+/, "", line)
    }
    sub(/[ \t]*\(.*$/, "", line)
    sub(/[ \t]*\{.*$/, "", line)
    return line
}

{
    original = $0
}

/^[ \t]*([A-Za-z_][A-Za-z0-9_]*[ \t]*\([ \t]*\)|function[ \t]+[A-Za-z_][A-Za-z0-9_]*)[ \t]*\{/ {
    name = function_name(original)
    if (name == "") next
    if (name in seen) {
        print FILENAME ":" NR ": duplicate function definition: " name
        print FILENAME ":" seen[name] ": previous definition of " name
        errors++
    } else {
        seen[name] = NR
    }
}

END {
    if (errors > 0) exit 1
    print "OK: no duplicate function definitions found"
    exit 0
}
