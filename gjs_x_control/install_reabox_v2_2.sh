#!/usr/bin/env bash
set -euo pipefail

echo "ReaBox installer v2.2 (portable HOME + startup)"

# ReaBox installer v2.2 - PORTABLE HOME + STARTUP
#
# Installeert:
#   Lua     -> $HOME/.config/REAPER/Scripts/gjs/gjs_x_control/
#   JSFX    -> $HOME/.config/REAPER/Scripts/gjs/gjs_x_control/jsfx/
#   JSFX    -> $HOME/.config/REAPER/Effects/gjs/
#   Startup -> $HOME/.config/REAPER/Scripts/__startup.lua
#
# Gebruik:
#   ./install_reagroove_v2.sh
#   ./install_reagroove_v2.sh /pad/naar/build.zip
#   ./install_reagroove_v2.sh /pad/naar/git-checkout
#   ./install_reagroove_v2.sh --no-pull /pad/naar/git-checkout
#
# Zonder argument:
#   1. als dit script in een git-repo staat: gebruik die repo;
#   2. anders: gebruik de nieuwste .zip in de huidige directory.
#
# Bij een git-checkout wordt standaard eerst:
#   git pull --ff-only
# uitgevoerd. Gebruik --no-pull om dat over te slaan.

REAPER_ROOT="$HOME/.config/REAPER"
LUA_DEST="$REAPER_ROOT/Scripts/gjs/gjs_x_control"
SCRIPT_JSFX_DEST="$LUA_DEST/jsfx"
EFFECTS_JSFX_DEST="$REAPER_ROOT/Effects/gjs"
STARTUP_DEST="$REAPER_ROOT/Scripts/__startup.lua"

DO_PULL=1
SOURCE=""

usage() {
    cat <<EOF
Gebruik:
  $0 [--no-pull] [zip-of-git-map]

Voorbeelden:
  $0
  $0 ~/Downloads/gjs_x_control_build.zip
  $0 ~/src/gjs_x_control
  $0 --no-pull ~/src/gjs_x_control
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-pull)
            DO_PULL=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [[ -n "$SOURCE" ]]; then
                echo "Fout: te veel argumenten."
                usage
                exit 1
            fi
            SOURCE="$1"
            shift
            ;;
    esac
done

TMP=""
cleanup() {
    if [[ -n "${TMP:-}" && -d "$TMP" ]]; then
        rm -rf "$TMP"
    fi
}
trap cleanup EXIT

find_repo_root() {
    local start="$1"
    git -C "$start" rev-parse --show-toplevel 2>/dev/null || true
}

if [[ -z "$SOURCE" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_ROOT="$(find_repo_root "$SCRIPT_DIR")"

    if [[ -n "$REPO_ROOT" ]]; then
        SOURCE="$REPO_ROOT"
    else
        SOURCE="$(find . -maxdepth 1 -type f -name '*.zip' -printf '%T@ %p\n' \
            | sort -nr \
            | head -n 1 \
            | cut -d' ' -f2- || true)"
    fi
fi

if [[ -z "$SOURCE" ]]; then
    echo "Fout: geen git-checkout of zip gevonden."
    exit 1
fi

SOURCE="$(readlink -f "$SOURCE")"

if [[ -d "$SOURCE" ]]; then
    SRC="$SOURCE"

    if [[ -d "$SRC/.git" || -n "$(find_repo_root "$SRC")" ]]; then
        REPO_ROOT="$(find_repo_root "$SRC")"
        [[ -n "$REPO_ROOT" ]] && SRC="$REPO_ROOT"

        echo "Git-bron: $SRC"

        if [[ "$DO_PULL" -eq 1 ]]; then
            echo "Git pull..."
            git -C "$SRC" pull --ff-only

            if [[ -f "$SRC/.gitmodules" ]]; then
                echo "Git submodules..."
                git -C "$SRC" submodule update --init --recursive
            fi
        else
            echo "Git pull overgeslagen (--no-pull)."
        fi
    fi

elif [[ -f "$SOURCE" && "$SOURCE" == *.zip ]]; then
    TMP="$(mktemp -d)"
    echo "ZIP: $SOURCE"
    echo "Uitpakken..."
    unzip -q "$SOURCE" -d "$TMP"

    if [[ -d "$TMP/gjs_x_control" ]]; then
        SRC="$TMP/gjs_x_control"
    else
        # Als er bestanden direct op de ZIP-root staan, is die root de bron.
        # Dit is de normale ReaGroove-build: Lua bovenin + jsfx/ ernaast.
        mapfile -t TOP_FILES < <(find "$TMP" -mindepth 1 -maxdepth 1 -type f)
        mapfile -t TOP_DIRS < <(find "$TMP" -mindepth 1 -maxdepth 1 -type d)

        if [[ "${#TOP_FILES[@]}" -gt 0 ]]; then
            SRC="$TMP"
        elif [[ "${#TOP_DIRS[@]}" -eq 1 ]]; then
            # Alleen afdalen wanneer de ZIP echt slechts één wrapper-map bevat.
            SRC="${TOP_DIRS[0]}"
        else
            SRC="$TMP"
        fi
    fi
else
    echo "Fout: bron bestaat niet of is geen ondersteunde zip/map:"
    echo "  $SOURCE"
    exit 1
fi

# Als de git-repo een gjs_x_control submap bevat, gebruik die.
if [[ -d "$SRC/gjs_x_control" ]]; then
    SRC="$SRC/gjs_x_control"
fi

if [[ ! -d "$SRC" ]]; then
    echo "Fout: bronmap niet gevonden."
    exit 1
fi

mkdir -p "$LUA_DEST" "$SCRIPT_JSFX_DEST" "$EFFECTS_JSFX_DEST"

echo
echo "Bron:"
echo "  $SRC"

echo
echo "Lua/scripts -> $LUA_DEST"
find "$SRC" -maxdepth 1 -type f \( \
    -name '*.lua' -o \
    -name '*.txt' -o \
    -name '*.ini' -o \
    -name '*.json' \
\) ! -name '__startup.lua' -print0 | while IFS= read -r -d '' file; do
    echo "  $(basename "$file")"
    cp -f "$file" "$LUA_DEST/"
done

if [[ -d "$SRC/jsfx" ]]; then
    echo
    echo "JSFX -> $SCRIPT_JSFX_DEST"
    echo "JSFX -> $EFFECTS_JSFX_DEST"

    find "$SRC/jsfx" -type f -print0 | while IFS= read -r -d '' file; do
        rel="${file#"$SRC/jsfx/"}"

        dest_script="$SCRIPT_JSFX_DEST/$rel"
        dest_effects="$EFFECTS_JSFX_DEST/$rel"

        mkdir -p "$(dirname "$dest_script")"
        mkdir -p "$(dirname "$dest_effects")"

        echo "  $rel"
        cp -f "$file" "$dest_script"
        cp -f "$file" "$dest_effects"
    done
else
    echo
    echo "Waarschuwing: geen jsfx-map gevonden in:"
    echo "  $SRC"
fi


echo
echo "Startup -> $STARTUP_DEST"
mkdir -p "$(dirname "$STARTUP_DEST")"
cat > "$STARTUP_DEST" <<'REABOX_STARTUP_LUA'
-- __startup.lua
-- Loads the default ReaBox project directly from:
--   $HOME/ReaBox/default/Media/projlist.RPL
-- Then runs the startup-only control command.

local function get_home()
    local home = os.getenv("HOME") or os.getenv("USERPROFILE")
    if not home or home == "" then
        home = (os.getenv("HOMEDRIVE") or "") .. (os.getenv("HOMEPATH") or "")
    end
    if not home or home == "" then return nil end
    return home:gsub("\\", "/")
end

local function load_default_project()
    local home = get_home()
    if not home then return false end

    local default_dir = home .. "/ReaBox/default"
    local rpl_file = default_dir .. "/Media/projlist.RPL"
    local f = io.open(rpl_file, "r")
    if not f then return false end

    local projects = {}
    for raw_line in f:lines() do
        local line = (raw_line or ""):gsub("\r", ""):match("^%s*(.-)%s*$")
        line = line:gsub('^"', ''):gsub('"$', '')

        if line ~= "" and line:lower():match("%.rpp$") then
            local is_absolute = line:sub(1, 1) == "/"
                or line:match("^%a:[/\\]") ~= nil
                or line:sub(1, 2) == "//"
            local rpp = is_absolute and line or (default_dir .. "/" .. line)
            rpp = rpp:gsub("\\", "/")
            if reaper.file_exists(rpp) then
                projects[#projects + 1] = rpp
            end
        end
    end
    f:close()

    if #projects == 0 then return false end

    reaper.Main_OnCommand(41898, 0)
    reaper.Main_OnCommand(40886, 0)
    reaper.Main_openProject(projects[1])

    for i = 2, #projects do
        reaper.Main_OnCommand(40859, 0)
        reaper.Main_openProject(projects[i])
    end

    reaper.Main_OnCommand(40861, 0)
    return true
end

if not load_default_project() then return end

local cmd1 = reaper.NamedCommandLookup(
    "_RS3754d4350a620104eb9535633b4eada50556a5d9"
)

if cmd1 ~= 0 then
    reaper.Main_OnCommand(cmd1, 0)
end
REABOX_STARTUP_LUA
chmod 644 "$STARTUP_DEST"

echo
echo "Klaar."
echo "Lua:"
echo "  $LUA_DEST"
echo "JSFX kopie 1:"
echo "  $SCRIPT_JSFX_DEST"
echo "JSFX kopie 2:"
echo "  $EFFECTS_JSFX_DEST"
echo "Startup:"
echo "  $STARTUP_DEST"


# Laat bij een Git-bron aan het eind zien wat lokaal gewijzigd is.
REPO_ROOT="$(find_repo_root "$SRC")"
if [[ -n "$REPO_ROOT" ]]; then
    echo
    echo "Git status:"
    git -C "$REPO_ROOT" status --short
fi
