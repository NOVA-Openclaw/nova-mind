#!/usr/bin/env awk -f
# Detect 'local' declarations that are not inside a function body.
# This is a cheap static check for agent-install.sh.  It tracks brace
# depth, function definitions, strings, comments, parameter expansions,
# and heredocs well enough for the installer's actual content.

BEGIN {
    depth = 0
    in_function = 0
    in_single = 0
    in_double = 0
    in_param = 0
    param_depth = 0
    heredoc = ""
    heredoc_indent = 0
    errors = 0
}

function is_function_def(line) {
    gsub(/^[ \t]+|[ \t]+$/, "", line)
    if (line ~ /^[A-Za-z_][A-Za-z0-9_]*[ \t]*\([ \t]*\)[ \t]*\{/) return 1
    if (line ~ /^function[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*(\([ \t]*\))?[ \t]*\{/) return 1
    return 0
}

{
    line = $0

    if (heredoc != "") {
        test_line = line
        if (heredoc_indent) sub(/^[\t]+/, "", test_line)
        if (test_line == heredoc) {
            heredoc = ""
            heredoc_indent = 0
        }
        next
    }

    cleaned = ""
    i = 1
    while (i <= length(line)) {
        c = substr(line, i, 1)

        if (in_single) {
            cleaned = cleaned c
            if (c == "'") in_single = 0
            i++
            continue
        }

        if (in_double) {
            cleaned = cleaned c
            if (c == "\\") {
                if (i < length(line)) {
                    cleaned = cleaned substr(line, i + 1, 1)
                    i += 2
                } else {
                    i++
                }
                continue
            }
            if (c == "\"") in_double = 0
            i++
            continue
        }

        if (in_param) {
            if (c == "{") param_depth++
            else if (c == "}") {
                param_depth--
                if (param_depth == 0) in_param = 0
            }
            i++
            continue
        }

        if (c == "'") {
            in_single = 1
            cleaned = cleaned c
            i++
            continue
        }
        if (c == "\"") {
            in_double = 1
            cleaned = cleaned c
            i++
            continue
        }
        if (c == "#") break

        if (c == "$" && substr(line, i + 1, 1) == "{") {
            in_param = 1
            param_depth = 1
            i += 2
            continue
        }

        if (c == "<" && substr(line, i + 1, 1) == "<") {
            i += 2
            if (substr(line, i, 1) == "-") {
                heredoc_indent = 1
                i++
            }
            while (i <= length(line) && substr(line, i, 1) ~ /[ \t]/) i++
            marker = ""
            if (substr(line, i, 1) == "'") {
                i++
                while (i <= length(line) && substr(line, i, 1) != "'") {
                    marker = marker substr(line, i, 1)
                    i++
                }
                if (substr(line, i, 1) == "'") i++
            } else if (substr(line, i, 1) == "\"") {
                i++
                while (i <= length(line) && substr(line, i, 1) != "\"") {
                    marker = marker substr(line, i, 1)
                    i++
                }
                if (substr(line, i, 1) == "\"") i++
            } else {
                while (i <= length(line) && substr(line, i, 1) ~ /[A-Za-z0-9_]/) {
                    marker = marker substr(line, i, 1)
                    i++
                }
            }
            heredoc = marker
            next
        }

        if (c == "{") {
            if (depth == 0 && is_function_def(cleaned c)) in_function = 1
            depth++
            cleaned = cleaned c
            i++
            continue
        }
        if (c == "}") {
            if (depth > 0) {
                depth--
                if (depth == 0 && in_function) in_function = 0
            }
            cleaned = cleaned c
            i++
            continue
        }

        cleaned = cleaned c
        i++
    }

    if (depth == 0 && !in_function && !in_single && !in_double && !in_param) {
        stripped = cleaned
        gsub(/^[ \t]+/, "", stripped)
        if (stripped ~ /^local[ \t]/) {
            print FILENAME ":" NR ": top-level 'local' declaration: " stripped
            errors++
        }
    }
}

END {
    if (errors > 0) exit 1
    print "OK: no top-level 'local' declarations found"
    exit 0
}
