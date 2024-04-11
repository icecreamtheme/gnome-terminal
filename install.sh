#!/usr/bin/env bash
dir=$(dirname "$0")

# palette
bd_color='#696969'
bg_color=#000000
fg_color=#E6EB55
color00=#000000
color01=#FE435B
color02=#F00359
color03=#FDBA21
color04=#3545A1
color05=#23855D
color06=#583C6F
color07=#9387C0
color08=#696969
color09=#FF78C6
color11=#BF2E76
color12=#E6EB55
color13=#206BC4
color14=#4EEF76
color15=#C279CF
color16=#E4E4E4


declare -a schemes
schemes=($(cd $dir/colors && echo * && cd - > /dev/null))

gnomeVersion="$(expr \
    "$(LANGUAGE=en_US.UTF-8 gnome-terminal --version)" : \
    '^[^[:digit:]]* \(\([[:digit:]]*\.*\)*\)' \
)"

# newGnome=1 if the gnome-terminal version >= 3.8
if [[ ("$(echo "$gnomeVersion" | cut -d"." -f1)" = "3" && \
       "$(echo "$gnomeVersion" | cut -d"." -f2)" -ge 8) || \
       "$(echo "$gnomeVersion" | cut -d"." -f1)" -ge 4 ]]
  then newGnome="1"
  dconfdir=/org/gnome/terminal/legacy/profiles:
else
  newGnome=0
  gconfdir=/apps/gnome-terminal/profiles
fi

die() {
  echo $1
  exit ${2:-1}
}

in_array() {
  local e
  for e in "${@:2}"; do [[ $e == $1 ]] && return 0; done
  return 1
}


gnomeVersion="$(expr "$(gnome-terminal --version)" : '.* \(.*[.].*[.].*\)$')"

declare -a profiles
if [ "$newGnome" = "1" ]
  then profiles=($(dconf list $dconfdir/ | grep ^: | sed 's/\///g'))
else
  profiles=($(gconftool-2 -R $gconfdir | grep $gconfdir | cut -d/ -f5 |  \
           cut -d: -f1))
fi



get_uuid() {
  # Print the UUID linked to the profile name sent in parameter
  local profile_name=$1
  for i in ${!profiles[*]}
    do
      if [[ "$(dconf read $dconfdir/${profiles[i]}/visible-name)" == \
          "'$profile_name'" ]]
        then echo "${profiles[i]}"
        return 0
      fi
    done
  echo "$profile_name"
}

validate_profile() {
  local profile=$1
  in_array $profile "${profiles[@]}" || die "$profile is not a valid profile" 3
}

get_profile_name() {
  local profile_name

  # dconf still return "" when the key does not exist, gconftool-2 return 0,
  # but it does priint error message to STDERR, and command substitution
  # only gets STDOUT which means nothing at this point.
  if [ "$newGnome" = "1" ]
    then profile_name="$(dconf read $dconfdir/$1/visible-name | sed s/^\'// | \
        sed s/\'$//)"
  else
    profile_name=$(gconftool-2 -g $gconfdir/$1/visible_name)
  fi
  [[ -z $profile_name ]] && die "$1 (No name)" 3
  echo $profile_name
}

interactive_new_profile() {
  local confirmation

  echo    "No profile found"
  echo    "You need to create a new default profile to continue. Continue?"
  echo -n "(YES to continue) "

  read confirmation
  if [[ $(echo $confirmation | tr '[:lower:]' '[:upper:]') != YES ]]
  then
    die "ERROR: Confirmation failed -- ABORTING!"
  fi

  echo -e "Profile \"Default\" created\n"
}

interactive_select_profile() {
  local profile_key
  local profile_name
  local profile_names
  local profile_count=$#

  declare -a profile_names
  while [ $# -gt 0 ]
  do
    profile_names[$(($profile_count - $#))]=$(get_profile_name $1)
    shift
  done

  set -- "${profile_names[@]}"

  echo "Please select a Gnome Terminal profile:"
  select profile_name
  do
    if [[ -z $profile_name ]]
    then
      die "ERROR: Invalid selection -- ABORTING!" 3
    fi
    profile_key=$(expr ${REPLY} - 1)
    break
  done
  echo

  profile=${profiles[$profile_key]}
}

check_empty_profile() {
  if [ "$profiles" = "" ]
    then interactive_new_profile
    create_new_profile
    profiles=($(dconf list $dconfdir/ | grep ^: | sed 's/\///g'))
  fi
}


validate_scheme() {
  local profile=$1
  in_array $scheme "${schemes[@]}" || die "$scheme is not a valid scheme" 2
}

###

create_new_profile() {
  profile_id="$(uuidgen)"
  dconf write $dconfdir/default "'$profile_id'"
  dconf write $dconfdir/list "['$profile_id']"
  profile_dir="$dconfdir/:$profile_id"
  dconf write $profile_dir/visible-name "'Default'"
}

to_dconf() {
    tr '\n' '~' | sed -e "s#~\$#']\n#" -e "s#~#', '#g" -e "s#^#['#"
}

to_gconf() {
    tr '\n' \: | sed 's#:$#\n#'
}

set_profile_colors() {
  local profile=$1
  local scheme=$2
  local scheme_dir=$dir/colors/$scheme

  if [ "$newGnome" = "1" ]
    then local profile_path=$dconfdir/$profile

    dconf write $profile_path/palette "$(to_dconf < $scheme_dir/palette)"
    dconf write $profile_path/bold-color "'$bd_color'"
    dconf write $profile_path/background-color "'$bg_color'"
    dconf write $profile_path/foreground-color "'$fg_color'"
    dconf write $profile_path/use-theme-colors "false"
    dconf write $profile_path/bold-color-same-as-fg "false"

  else
    local profile_path=$gconfdir/$profile

    gconftool-2 -s -t string $profile_path/palette "$(to_gconf < $scheme_dir/palette)"
    gconftool-2 -s -t string $profile_path/bold_color $bd_color
    gconftool-2 -s -t string $profile_path/background_color $bg_color
    gconftool-2 -s -t string $profile_path/foreground_color $fg_color
    gconftool-2 -s -t bool $profile_path/use_theme_colors false
    gconftool-2 -s -t bool $profile_path/bold_color_same_as_fg false
  fi
}

#####

interactive_select_scheme() {
  echo "Please select a color scheme:"
  select scheme
  do
    if [[ -z $scheme ]]
    then
      die "ERROR: Invalid selection -- ABORTING!" 2
    fi
    break
  done
  echo
}

interactive_confirm() {
  local confirmation

  echo    "You have selected:"
  echo
  echo    "  Scheme:  $scheme"
  echo    "  Profile: $(get_profile_name $profile)"
  echo
  echo    "Are you sure you want to overwrite the selected profile?"
  echo -n "(YES to continue) "

  read confirmation
  if [[ $(echo $confirmation | tr '[:lower:]' '[:upper:]') != YES ]]
  then
    die "⚡️ Error"
  fi

  echo "🍨"
}

while [ $# -gt 0 ]
do
  case $1 in
    --scheme=* )
      scheme=${1#*=}
    ;;
    -s | --scheme )
      scheme=$2
      shift
    ;;
    --profile=* )
      profile=${1#*=}
    ;;
    -p | --profile )
      profile=$2
      shift
    ;;
  esac
  shift
done

if [[ -n "$scheme" ]]
  then validate_scheme $scheme
else
  interactive_select_scheme "${schemes[@]}"
fi

if [[ -n "$profile" ]]
  then if [ "$newGnome" = "1" ]
    then profile="$(get_uuid "$profile")"
  fi
  validate_profile $profile
else
  if [ "$newGnome" = "1" ]
    then check_empty_profile
  fi
  interactive_select_profile "${profiles[@]}"
  interactive_confirm
fi

set_profile_colors $profile $scheme
