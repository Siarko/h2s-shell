# shellcheck shell=bash
# The reader of an element's about.txt (mockups/<kind>/<name>/about.txt), sourced by the
# mockups' tools (tests/mockup.sh, tests/run-mockups.sh); the root entry (mockup.qml) reads
# the same format with its own reader, by the same rules. Plain bash, no other program.
#
# The format, a line each:
#   # …                          a comment (as is a blank line)
#   description: <text>          once: what the element is, at most 100 characters
#   state: <name> <description>  a component's or a view's state, in shot order
#   scene: <name> <description>  a plan's scene (the wrong keyword for the kind is an error)
#   family: <family>             at most once: the kind of element it is (fields, choices, …),
#                                which the gallery groups its sections by (mockups/kit/Gallery.qml)
#   parent: <element>            at most once, instead of a family: the element (a folder's
#                                name of the same kind) it is part of, beside which the gallery
#                                shows it, in that one's family
# A name matches ^[A-Za-z0-9][A-Za-z0-9-]*$ (capitals for a name the shell itself spells so,
# as a button kind "saveChange") and is not repeated; its description is required, at
# most 100 characters; at least one and at most 30 states or scenes. A family or a parent
# matches ^[a-z0-9][a-z0-9-]*$; neither is required.
#
# about_read <element folder> <state | scene>
#   sets about_description, about_family, about_parent ("" when not declared),
#   about_names and about_descriptions (arrays, in order) and
#   about_errors (each "about.txt line <n>: …" or "about.txt: …"); returns 0 when the file
#   is as the format says, 1 otherwise (what could be read is still set)

about_limit_text=100
about_limit_names=30

about_read() {
    local folder=$1 word=$2 other file line number=0 keyword rest name text
    local LC_ALL=C.UTF-8
    local -A seen=()
    about_description=""
    about_family=""
    about_parent=""
    about_names=()
    about_descriptions=()
    about_errors=()
    [ "$word" = state ] && other=scene || other=state
    file=$folder/about.txt
    if [ ! -f "$file" ]; then
        about_errors+=("about.txt is missing: every element declares its description and its ${word}s there")
        return 1
    fi
    if [ ! -r "$file" ]; then
        about_errors+=("about.txt cannot be read")
        return 1
    fi
    local descriptions=0 declared=0 families=0 parents=0
    while IFS= read -r line || [ -n "$line" ]; do
        number=$((number + 1))
        line=${line%$'\r'}
        [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]] && continue
        if ! [[ "$line" =~ ^([a-z]+):(.*)$ ]]; then
            about_errors+=("about.txt line $number: not 'description:', '$word:', 'family:', 'parent:' or a comment")
            continue
        fi
        keyword=${BASH_REMATCH[1]}
        rest=${BASH_REMATCH[2]}
        # Trimmed of the blanks at both ends
        rest=${rest#"${rest%%[![:space:]]*}"}
        rest=${rest%"${rest##*[![:space:]]}"}
        case $keyword in
            description)
                descriptions=$((descriptions + 1))
                if [ "$descriptions" -gt 1 ]; then
                    about_errors+=("about.txt line $number: a second description")
                elif [ -z "$rest" ]; then
                    about_errors+=("about.txt line $number: the description is empty")
                elif [ ${#rest} -gt $about_limit_text ]; then
                    about_errors+=("about.txt line $number: the description is ${#rest} characters, over $about_limit_text")
                else
                    about_description=$rest
                fi
                ;;
            "$word")
                declared=$((declared + 1))
                name=${rest%%[[:space:]]*}
                text=${rest#"$name"}
                text=${text#"${text%%[![:space:]]*}"}
                if [ -z "$name" ]; then
                    about_errors+=("about.txt line $number: a $word without a name")
                elif ! [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]]; then
                    about_errors+=("about.txt line $number: the $word name '$name' is not letters, digits and '-' (starting with a letter or digit)")
                elif [ -n "${seen[$name]:-}" ]; then
                    about_errors+=("about.txt line $number: the $word name '$name' is repeated (line ${seen[$name]})")
                elif [ -z "$text" ]; then
                    about_errors+=("about.txt line $number: the $word '$name' has no description")
                elif [ ${#text} -gt $about_limit_text ]; then
                    about_errors+=("about.txt line $number: the $word '$name' has a description of ${#text} characters, over $about_limit_text")
                else
                    seen[$name]=$number
                    about_names+=("$name")
                    about_descriptions+=("$text")
                fi
                ;;
            family | parent)
                if [ "$keyword" = family ]; then
                    families=$((families + 1))
                    [ "$families" -gt 1 ] && { about_errors+=("about.txt line $number: a second family"); continue; }
                else
                    parents=$((parents + 1))
                    [ "$parents" -gt 1 ] && { about_errors+=("about.txt line $number: a second parent"); continue; }
                fi
                if ! [[ "$rest" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
                    about_errors+=("about.txt line $number: the $keyword '$rest' is not lowercase letters, digits and '-'")
                elif [ "$keyword" = family ]; then
                    about_family=$rest
                else
                    about_parent=$rest
                fi
                ;;
            "$other")
                if [ "$word" = state ]; then
                    about_errors+=("about.txt line $number: 'scene:' is a plan's; a component or a view declares 'state:' lines")
                else
                    about_errors+=("about.txt line $number: 'state:' is a component's or a view's; a plan declares 'scene:' lines")
                fi
                ;;
            *)
                about_errors+=("about.txt line $number: '$keyword:' is not 'description:', '$word:', 'family:' or 'parent:'")
                ;;
        esac
    done < "$file"
    [ "$descriptions" -gt 0 ] || about_errors+=("about.txt: no 'description:' line")
    [ "$declared" -gt 0 ] || about_errors+=("about.txt: no '$word:' line")
    [ "$families" -gt 0 ] && [ "$parents" -gt 0 ] \
        && about_errors+=("about.txt: a family and a parent: a part takes its parent's family")
    [ -n "$about_parent" ] && [ "$about_parent" = "${folder##*/}" ] \
        && about_errors+=("about.txt: the parent is the element itself")
    [ ${#about_names[@]} -le $about_limit_names ] \
        || about_errors+=("about.txt: ${#about_names[@]} ${word}s, over $about_limit_names")
    [ ${#about_errors[@]} -eq 0 ]
}
