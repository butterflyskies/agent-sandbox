# Shared setup for run scripts. Source this, don't execute it.
# Provides: ROOT_DIR, IMAGE, HOME_VOL, PODMAN_ARGS array

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
IMAGE="${IMAGE:-agent-sandbox}"
HOME_VOL="${HOME_VOL:-${ROOT_DIR}/home}"

if [[ ! -d "$HOME_VOL" ]]; then
    echo "No persistent home at $HOME_VOL"
    echo "Run ./skeleton/init.sh first, or set HOME_VOL to your volume path."
    exit 1
fi

PODMAN_ARGS=(
    -it --rm
    --cap-drop=ALL
    --security-opt=no-new-privileges
    --hostname agent-sandbox
    -v "${HOME_VOL}:/home/agent:Z"
)
