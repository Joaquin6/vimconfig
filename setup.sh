#!/bin/bash -i

# Requires Bash 4+

# Windows Setup:
#
# Before starting, setup Chocolatey, and install these dependencies:
#
# choco install neovim git editorconfig.core
#
# This needs to be run from a cmd prompt with admin priviledges
# using the Git bash exe.  For example:
#
#   "C:\Program Files\Git\bin\bash.exe" setup.sh <args>
#
# Trying to run this from a git bash mintty or another terminal will fail.
# Windows 10 with WSL/Ubuntu/etc installed will also have it's own `bash` in
# System32.  This will also fail because it will try to install within the
# WSL filesystem

# Bail out on failure
set -e

cd "$HOME"

timestamp=$(date "+%Y%m%d_%H%M%S")
branch="master"

function print_help {
  echo "Usage:
./setup.sh [-r|-u|-h] [branch]

-r      Remote setup, grabs your Vim config from GitHub
-u      Update Vim config from GitHub and update all Plugins
-h      Print this help
branch  The branch name to checkout after setup.
        Defaults to 'master'. Only works with -r or no options
"

  exit 1;
}

if [ $# -gt 2 ]; then
  echo "Too many args...
"

  print_help
fi

function which_silent {
  command -v "$1" > /dev/null
}

function winMklink() {
  local t="${1//\//\\}"
  local s="${2//\//\\}"
  if [[ -d $1 ]]; then
    cmd <<< "mklink /D \"$s\" \"$t\""
  else
    cmd <<< "mklink \"$s\" \"$t\""
  fi
}

function updateSpellFiles() {
  curl 'http://ftp.vim.org/pub/vim/runtime/spell/en.utf-8.spl' > "$HOME/.vim/spell/en.utf-8.spl"
  curl 'http://ftp.vim.org/pub/vim/runtime/spell/en.utf-8.sug' > "$HOME/.vim/spell/en.utf-8.sug"
}

function updateVimPlugins() {
  for vim in "${vims[@]}"; do
    if which_silent "$vim"; then
      "$vim" -N -u "$HOME/.vim/vimrc" -c "try | call dein#update() | finally | qall! | endtry" -V1 -es ||
        { echo "$vim exited with $?, you may need to check your config."; exit 1; }
    fi
  done
}

# Run config, paths are relative to $HOME
if [[ $(uname -s) =~ ^MINGW64_NT ]]; then
  # If running in msys bash, we do windows setup
  mkdir -p AppData/Local/nvim
  toLink=( _vimrc AppData/Local/nvim/init.vim AppData/Local/nvim/ginit.vim AppData/Local/nvim/spell )
  linkTargets=( .vim/vimrc ../../../.vim/vimrc ../../../.vim/ginit.vim ../../../.vim/spell )
  linkCmd="winMklink"

  # Vim will install multiple versions into folders within Program Files (x86)
  # this check may not be necessary since I haven't used gvim in awhile.
  # We should probably replace the windows and nix vims assignment with something
  # thtat just checks the $PATH for vim/nvim
  if [[ -d "/c/Program Files (x86)/Vim/" ]]; then
    # Gets an array of full paths of vims
    # shellcheck disable=SC2207,SC2011
    IFS=$'\n' vims=( $(ls -1 "/c/Program Files (x86)/Vim/" | xargs -n 1 printf "/c/Program Files (x86)/Vim/%s/vim\n") nvim )
  else
    vims=( nvim )
  fi
else
  # Assume we're on some kind of *nix
  toLink=( .vimrc .config/nvim )
  linkTargets=( .vim/vimrc ../.vim )
  linkCmd="ln -s"
  vims=( vim nvim )
fi

case $1 in
"-r")
  echo "Remote setup..."
  shift

  if [ -e ".vim" ]; then
    echo "$HOME/.vim exists, moving to .vim.$timestamp"
    mv .vim ".vim.$timestamp"
  fi

  git clone https://github.com/moshen/vimconfig.git .vim ||
    { echo "Remote clone failed, bailing out..."; exit 1; }

  echo "
"
  ;;

"-u")
  echo "Updating current config..."
  shift

  cd .vim

  # Check for an unclean repo
  { git diff-index --quiet --cached HEAD &&
    git diff-files --quiet; } ||
    { echo "Unclean repo, exiting..."; exit 1; }

  # Get changes from Git!
  git pull origin "$(git rev-parse --abbrev-ref HEAD)" ||
    { echo "Failed to pull changes, exiting..."; exit 1; }

  # Update Spell files
  updateSpellFiles

  # Update Plugins
  updateVimPlugins

  echo "
Done! Your vim config is up-to-date"

  exit 0;
  ;;

"-h")
  print_help
  ;;
"--help")
  print_help
  ;;
esac

if [ "$1" ]; then
  branch=$1
fi

cd .vim

# Grab Dein
git clone https://github.com/Shougo/dein.vim.git dein/repos/github.com/Shougo/dein.vim ||
  { echo "Failed to clone Dein.

If you're trying to update, use the -u flag!"; exit 1; }

if ! git branch --all | grep -q "$branch"; then
  echo "$branch doesn't exist, continuing on master"
  branch="master"
fi

# If we change branches, we want to run the setup.sh from that branch
if [[ $(git rev-parse --abbrev-ref HEAD) != "$branch" ]]; then
  git checkout "$branch" || {
    echo "Checking out $branch failed.  Bailing out";
    exit 1;
  }
  exec ./setup.sh "$branch"
fi

# Link up!
cd "$HOME"

# Create spell directory for NeoVim
mkdir -p .vim/spell

# Download spelling files
updateSpellFiles

# Check for readlink on Solaris/BSD
readlink=$(type -p greadlink readlink | head -1)

for i in "${!toLink[@]}"; do
  if [ -L "${toLink[$i]}" ]; then
    if [ "$readlink" ]; then
      if [ "$($readlink -n "${toLink[$i]}")" == "${linkTargets[$i]}" ]; then
        echo "$HOME/${toLink[$i]} already links to ${linkTargets[$i]}"
        continue
      fi
    fi

    echo "$HOME/${toLink[$i]} exists, moving to ${toLink[$i]}.$timestamp"
    mv "${toLink[$i]}" "${toLink[$i]}.$timestamp"
    $linkCmd "${linkTargets[$i]}" "${toLink[$i]}"

  elif [ -e "${toLink[$i]}" ]; then
    echo "$HOME/${toLink[$i]} exists, moving to ${toLink[$i]}.$timestamp"
    mv "${toLink[$i]}" "${toLink[$i]}.$timestamp"
    $linkCmd "${linkTargets[$i]}" "${toLink[$i]}"

  else
    $linkCmd "${linkTargets[$i]}" "${toLink[$i]}"
  fi
done

# Install Plugins
updateVimPlugins

echo "Done!  Vim is fully configured."

exit 0
